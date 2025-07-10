// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

/**
 * What are our invariants?
 * - The total supply of DSC should be less than the total collateral value in USD
 * - Getter view function should never revert
 */
contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    Handler handler;

    address public weth;
    address public wbtc;
    address public wETHUsdPriceFeed;
    address public wBTCUsdPriceFeed;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wETHUsdPriceFeed, wBTCUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);

        targetContract(address(handler));
    }

    function invariant_totalSupplyOfDSCIsLessThanTotalCollateralValueInUSD() public view {
        // get teh value of al the collateral in teh protocol and comapre it to all the debt
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalwETHDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalwBTCDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wETHValue = dscEngine.getUSDValueOfToken(weth, totalwETHDeposited);
        uint256 wBTCValue = dscEngine.getUSDValueOfToken(wbtc, totalwBTCDeposited);

        console.log("totalSupply", totalSupply);
        console.log("wETHValue", wETHValue);
        console.log("wBTCValue", wBTCValue);
        console.log("timesMintCalled", handler.timesMintCalled());

        assert(totalSupply <= wETHValue + wBTCValue);
    }

    function invariant_gettersCantRevert() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationThreshold();
    }
}
