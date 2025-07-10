// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public helperConfig;
    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;

    address public USER = makeAddr("USER");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL_TO_REDEEM = 5 ether;
    uint256 public constant AMOUNT_DEBT_TO_COVER = 100e18;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 100e18;
    uint256 public constant AMOUNT_DSC_TO_BURN = 10e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////////////////////////////////
    ///// Constructor Tests
    ///////////////////////////////////////////////////////////
    function testRevertIfTokenLengthsDontMatch() public {
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressLengthNotEqualToPriceFeedAddressLength.selector);
        new DSCEngine(new address[](0), new address[](1), address(dsc));
    }

    /*/////////////////////////////////////////////////////////
    ///// Price Tests
    //////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18;

        uint256 actualUsd = dscEngine.getUSDValueOfToken(weth, ethAmount);

        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmountInWei = 100 ether;
        uint256 expectedWethAmount = 0.05 ether;

        uint256 actualWethAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmountInWei);

        assertEq(actualWethAmount, expectedWethAmount);
    }

    /////////////////////////////
    //// Deposit Collateral Tests
    /////////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertIfUnapprovedTokenIsDeposited() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(1), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInformation() public depositedCollateral {
        (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD) = dscEngine.getAccountInformation(USER);

        uint256 expectedDSCMinted = 0;
        uint256 actualCollateralTokenAmount = dscEngine.getTokenAmountFromUsd(weth, totalCollateralValueInUSD);

        assertEq(totalDSCMinted, expectedDSCMinted);
        assertEq(actualCollateralTokenAmount, AMOUNT_COLLATERAL);
    }

    /////////////////////////////
    //// Deposit Collateral and Mint DSC Tests
    /////////////////////////////

    modifier depositedCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testRevertIfCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.depositCollateralAndMintDSC(weth, 0, 1);

        vm.stopPrank();
    }

    function testRevertIfDSCIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 0);

        vm.stopPrank();
    }

    function testUserCollateralIsUpdated() public depositedCollateralAndMintDSC {
        uint256 afterCollateralDeposited = dscEngine.getCollateralTokenAmount(USER, weth);
        uint256 expectedCollateralDeposited = AMOUNT_COLLATERAL;

        assertEq(afterCollateralDeposited, expectedCollateralDeposited);
    }

    function testUserDSCIsUpdated() public depositedCollateralAndMintDSC {
        (uint256 totalDSCMinted,) = dscEngine.getAccountInformation(USER);

        uint256 expectedDSCMinted = AMOUNT_DSC_TO_MINT;
        uint256 actualDSCMinted = totalDSCMinted;

        assertEq(actualDSCMinted, expectedDSCMinted);
    }

    function testEventIsEmittedOnDepositCollateralAndMintDSC() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit();
        emit DSCEngine.DSCEngine__CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, 100);

        vm.stopPrank();
    }

    function testCollateralIsTransferredFromUser() public depositedCollateralAndMintDSC {
        uint256 expectedCollateralBalance = AMOUNT_COLLATERAL;
        uint256 actualCollateralBalance = ERC20Mock(weth).balanceOf(address(dscEngine));

        assertEq(actualCollateralBalance, expectedCollateralBalance);
    }

    function testRevertIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT * 10000);
        vm.stopPrank();
    }

    function testDSCMintedEventIsEmitted() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectEmit();
        emit DSCEngine.DSCEngine__DSCMinted(USER, AMOUNT_DSC_TO_MINT);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);

        vm.stopPrank();
    }

    /////////////////////////////
    //// Burn DSC Tests
    /////////////////////////////

    modifier burnDSC() {
        vm.startPrank(USER);
        DecentralizedStableCoin(address(dsc)).approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.burnDSC(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        _;
    }

    function testRevertIfBurnAmountIsZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.burnDSC(0);

        vm.stopPrank();
    }

    function testDSCMintedIsUpdatedAfterBurn() public depositedCollateralAndMintDSC burnDSC {
        (uint256 totalDSCMinted,) = dscEngine.getAccountInformation(USER);

        uint256 expectedDSCMinted = AMOUNT_DSC_TO_MINT - AMOUNT_DSC_TO_BURN;
        uint256 actualDSCMinted = totalDSCMinted;

        assertEq(actualDSCMinted, expectedDSCMinted);
    }

    function testDSCIsBurned() public depositedCollateralAndMintDSC burnDSC {
        uint256 beforeTotalSupply = dsc.totalSupply();
        uint256 afterTotalSupply = beforeTotalSupply - AMOUNT_DSC_TO_BURN;

        assertEq(beforeTotalSupply - afterTotalSupply, AMOUNT_DSC_TO_BURN);
    }

    /////////////////////////////
    //// Redeem Collateral Tests
    /////////////////////////////

    modifier redeemCollateral() {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        vm.stopPrank();
        _;
    }

    function testRevertIfRedeemCollateralAmountIsZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);

        vm.stopPrank();
    }

    function testCollateralIsUpdatedForUser() public depositedCollateralAndMintDSC redeemCollateral {
        uint256 expectedCollateral = AMOUNT_COLLATERAL - AMOUNT_COLLATERAL_TO_REDEEM;
        uint256 actualCollateral = dscEngine.getCollateralTokenAmount(USER, weth);

        assertEq(actualCollateral, expectedCollateral);
    }

    function testEventIsEmittedOnRedeemCollateral() public depositedCollateralAndMintDSC {
        vm.startPrank(USER);

        vm.expectEmit();
        emit DSCEngine.DSCEngine__CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL_TO_REDEEM);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        vm.stopPrank();
    }

    function testCollateralIsTransferredToUser() public depositedCollateralAndMintDSC {
        uint256 beforeRedeemingCollateralBalance = ERC20Mock(weth).balanceOf(USER);

        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM);
        vm.stopPrank();

        uint256 afterRedeemingCollateralBalance = ERC20Mock(weth).balanceOf(USER);

        assertEq(afterRedeemingCollateralBalance - beforeRedeemingCollateralBalance, AMOUNT_COLLATERAL_TO_REDEEM);
    }

    function testRevertIfHealthFactorIsBrokenAfterRedeem() public depositedCollateralAndMintDSC {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL_TO_REDEEM * 2);
        vm.stopPrank();
    }

    /////////////////////////////
    //// Mint DSC Tests
    /////////////////////////////

    modifier mintDSC() {
        vm.startPrank(USER);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testRevertIfMintAmountIsZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.mintDSC(0);

        vm.stopPrank();
    }

    function testDSCMintedIsUpdatedAfterMint() public depositedCollateral mintDSC {
        (uint256 totalDSCMinted,) = dscEngine.getAccountInformation(USER);

        uint256 expectedDSCMinted = AMOUNT_DSC_TO_MINT;
        uint256 actualDSCMinted = totalDSCMinted;

        assertEq(actualDSCMinted, expectedDSCMinted);
    }

    function testRevertIfHealthFactorIsBrokenAfterMint() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT * 10000);
        vm.stopPrank();
    }

    /////////////////////////////
    //// Liquidate Tests
    /////////////////////////////

    modifier liquidate() {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        DecentralizedStableCoin(address(dsc)).approve(address(dscEngine), AMOUNT_DSC_TO_MINT);
        dscEngine.liquidate(weth, USER, AMOUNT_DEBT_TO_COVER);
        vm.stopPrank();
        _;
    }

    function testDebtToCoverIsZero() public {
        vm.startPrank(LIQUIDATOR);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.liquidate(weth, USER, 0);

        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsNotBroken() public depositedCollateralAndMintDSC {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBroken.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralAmountReceivedAfterLiquidation() public depositedCollateralAndMintDSC {
        // Updating Price Feed
        int256 wethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(wethUsdUpdatedPrice);

        // Getting Token Amount from USD
        uint256 tokenAmountFromDebtCovered = dscEngine.getTokenAmountFromUsd(weth, AMOUNT_DEBT_TO_COVER);

        // 10% bonus for liquidator
        uint256 bonusCollateral =
            (tokenAmountFromDebtCovered * dscEngine.getLiquidationBonus()) / dscEngine.getLiquidationPrecision();

        // Expected Collateral Received
        uint256 expectedCollateralReceived = tokenAmountFromDebtCovered + bonusCollateral;

        // Liquidator Depositing Collateral, Minting DSC and  Liquidating the User for $100 DSC
        vm.startPrank(LIQUIDATOR);

        // Current price after above manipulation of 1 $ETH is 18 $DSC
        // Liquidator Depositing 10x Collateral to cover 100 $DSC debt
        // AMOUNT_COLLATERAL = 10 $ETH
        // AMOUNT_COLLATERAL * 10 = 100 $ETH
        // Collateral value in USD = 100 $ETH * 18 $DSC = 1800 $DSC
        // AMOUNT_DSC_TO_MINT = 100 $DSC
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL * 10);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL * 10, AMOUNT_DSC_TO_MINT);
        DecentralizedStableCoin(address(dsc)).approve(address(dscEngine), AMOUNT_DSC_TO_MINT);

        // wETH Balance of Liquidator Before Liquidation
        uint256 collateralAmountBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        dscEngine.liquidate(weth, USER, AMOUNT_DEBT_TO_COVER);

        vm.stopPrank();

        // wETH Balance of Liquidator After Liquidation
        uint256 collateralAmountAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        console.log("expectedCollateralReceived", expectedCollateralReceived);
        console.log("collateralAmountBefore", collateralAmountBefore);
        console.log("collateralAmountAfter", collateralAmountAfter);

        assertEq(collateralAmountAfter - collateralAmountBefore, expectedCollateralReceived);
    }
}
