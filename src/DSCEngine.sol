//SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.18;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSC Engine
 * @author Megabyte
 *  The system is designed to be as minimal as possible, and have the token maintains a 1 token == $1 Peg
 *  The stablecoin has the properties:
 *      - Exogenous Collateral
 *      - Dollar Pegged
 *      - Algoritmically Stable
 *  It is similar to DAI if DAI had no govenance, no fees, and was only backed by WETH and WBTC.
 *  Our DSC system should always be "over collaterized". At no point, should the value of all collateral <= the $ backed value of all the DSC.
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral
 *  @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /////////////
    // Errors //
    /////////////
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__DepositCollateralFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintDSCFailed();
    error DSCEngine__TransferFailed();

    /////////////
    // State Variables //
    /////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant HEALTH_FACTOR_THRESHOLD = 1;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 DSCMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;

    /////////////
    // Events //
    /////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DSCEngine__CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    /////////////
    // Modifiers //
    /////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////
    // Functions //
    /////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ///////////////////////

    /**
     * @notice Function to deposit collateral and mint DSC in a single transaction.
     *     @param _tokenCollateralAddress: The address of the token to deposit as collateral
     *     @param _amountCollateral: The amount of collateral to deposit
     *     @param _amountMintDSC: The amount of DSC to mint
     */
    function depositCollateralAndMintDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountMintDSC
    ) external {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDSC(_amountMintDSC);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions) pattern
     *     @param _tokenCollateralAddress: The address of the token to deposit as collateral
     *     @param _amountCollateral: The amount of collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert DSCEngine__DepositCollateralFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    /**
     * @notice In order to redeem collateral, the user must have health factor > 1 after the collateral is removed.
     *
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit DSCEngine__CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI (Checks, Effects, Interactions) pattern
     *     @param _amount: The amount of DSC to mint
     *     @notice they must have more collateeral value than the minimum threshold
     */
    function mintDSC(uint256 _amount) public moreThanZero(_amount) nonReentrant {
        s_DSCMinted[msg.sender] += _amount;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, _amount);
        if (!minted) {
            revert DSCEngine__MintDSCFailed();
        }
    }

    function burnDSC(uint256 _amountToBurn) external moreThanZero(_amountToBurn) {
        s_DSCMinted[msg.sender] -= _amountToBurn;
        bool success = i_dsc.transferFrom(msg.sender, address(this), _amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(_amountToBurn);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////
    // Private And Internal View Functions //
    /////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralDepositedValue)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralDepositedValue = getCollateralValueInUSD(user);
    }

    /**
     * Returns how close the user is to being liquidated
     * If user goes below 1, then they are liquidated
     * @param user: The address of the user to check
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 totalCollateralDepositedValue) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold =
            (totalCollateralDepositedValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * LIQUIDATION_PRECISION) / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < HEALTH_FACTOR_THRESHOLD) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    /////////////
    // Public And External View Functions //
    /////////////

    function getCollateralValueInUSD(address user) public view returns (uint256 totalColalteralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            totalColalteralValue += getUSDValue(token, collateralAmount);
        }
    }

    function getUSDValue(address _tokenAddress, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // Return value = 1000 * 1e8
        // aommunt is 10 * 1e18
        // ((1000 * 1e8 * 1e10) * 10 * 1e18)/ 1e18
        return (((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / 1e18);
    }
}
