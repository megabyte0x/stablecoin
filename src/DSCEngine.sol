// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
/**
 * @title DSCEngine
 * @author @megabyte0x
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////////////
    // Errors
    ////////////////////////

    error DSCEngine__AmountMustBeGreaterThanZero();
    error DSCEngine__TokenAddressLengthNotEqualToPriceFeedAddressLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsNotBroken();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////////
    // Type
    ////////////////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////////////
    // State variables
    ////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////
    // Events
    ////////////////////////

    event DSCEngine__CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCEngine__DSCMinted(address indexed user, uint256 indexed amountDSCToMint);
    event DSCEngine__CollateralRedeemed(
        address indexed from, address indexed to, address indexed token, uint256 amountCollateralToRedeem
    );
    ////////////////////////
    // Modifiers
    ////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ////////////////////////
    // Functions
    ////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressLengthNotEqualToPriceFeedAddressLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions
    ////////////////////////

    /**
     * @notice deposits collateral and mints DSC.
     * @param tokenCollateralAddress The address of the token being deposited.
     * @param amountCollateral The amount of the token being deposited.
     * @param amountDscToMint The amount of DSC to mint.
     * @notice this function will deposit
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external moreThanZero(amountCollateral) moreThanZero(amountDscToMint) {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the token being deposited.
     * @param amountCollateral The amount of the token being deposited.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit DSCEngine__CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 amountDscToBurn
    ) public nonReentrant {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateralToRedeem);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateralToRedeem)
        public
        moreThanZero(amountCollateralToRedeem)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateralToRedeem);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI
     * @param amountDSCToMint The amount of DSC to mint.
     * @notice The collateral value must be more than the minimum threshold.
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        emit DSCEngine__DSCMinted(msg.sender, amountDSCToMint);

        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amountToBurn) public moreThanZero(amountToBurn) nonReentrant {
        _burnDSC(msg.sender, msg.sender, amountToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // NOTE: Not reachable
    }

    /**
     *
     * @param collateral The address of the collateral to liquidate.
     * @param user The address of the user to liquidate.
     * @param debtToCover The amount of debt to cover.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        address liquidator = msg.sender;
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsNotBroken();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        // 10% bonus for liquidator
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, liquidator, collateral, totalCollateralToRedeem);

        _burnDSC(user, liquidator, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(liquidator);
    }

    ////////////////////////
    // Private and Internal Functions
    ////////////////////////

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem
    ) internal {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateralToRedeem;
        emit DSCEngine__CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateralToRedeem);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateralToRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountToBurn) internal {
        s_DSCMinted[onBehalfOf] -= amountToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDSCMinted, totalCollateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    ////////////////////////
    //Public and External View Functions
    ////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // USD amount = $1000e18
        // ETH Price received = $2000e8
        // (1000e18 * 1e18 ) / (2000e8 * 1e10) = 5e17

        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValueOfToken(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValueOfToken(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // 1 ETH = 1000 USD
        // Return price = 1000 x 1e8
        // amount is in 1e18
        // ((1000 * 1e8 * 1e10) * (amount*1e18)) / 1e18
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        (totalDSCMinted, totalCollateralValueInUSD) = _getAccountInformation(user);
    }

    function getCollateralTokenAmount(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDSCMinted, totalCollateralValueInUSD);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getTokenPriceFeed(address collateralToken) external view returns (address priceFeed) {
        priceFeed = s_priceFeeds[collateralToken];
    }
}
