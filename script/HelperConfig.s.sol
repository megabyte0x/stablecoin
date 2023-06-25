// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethAddress;
        address wbtcAddress;
        address wethPriceFeedAddress;
        address wbtcPriceFeedAddress;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_PRICE = 2000e8;
    int256 public constant BTC_PRICE = 1000e8;
    uint256 public constant PRIVATE_KEY = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wethAddress: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtcAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        ERC20Mock weth = new ERC20Mock();
        weth.mint(msg.sender, 1000e8);

        MockV3Aggregator btcPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        ERC20Mock wbtc = new ERC20Mock();
        wbtc.mint(msg.sender, 1000e8);

        vm.stopBroadcast();

        return NetworkConfig({
            wethPriceFeedAddress: address(ethPriceFeed),
            wbtcPriceFeedAddress: address(btcPriceFeed),
            wethAddress: address(weth),
            wbtcAddress: address(wbtc),
            deployerKey: PRIVATE_KEY
        });
    }
}
