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
    ////////////////////////
    // State variables
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

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
     */
    function depositCollateralAndMintDSC() external {}

    /**
     * @notice Follows CEI
     * @param tokenCollateralAddress The address of the token being deposited.
     * @param amountCollateral The amount of the token being deposited.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @notice Follows CEI
     * @param amountDSCToMint The amount of DSC to mint.
     * @notice The collateral value must be more than the minimum threshold.
     */
    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        emit DSCEngine__DSCMinted(msg.sender, amountDSCToMint);

    
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    ////////////////////////
    // Private and Internal Functions
    ////////////////////////

    function _getAccountInformation(address user) private view returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD   ) {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    function _healthFactor(address user) private view returns (uint256) {

    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
    }


    ////////////////////////
    //Public and External View Functions
    ////////////////////////

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
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // 1 ETH = 1000 USD
        // Return price = 1000 x 1e8
        // amount is in 1e18
        // ((1000 * 1e8 * 1e10) * (amount*1e18)) / 1e18
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
