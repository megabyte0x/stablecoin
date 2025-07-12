// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author @megabyte0x
 * @notice this library is used to check the chainlink oracle for stale data. We want to freeze DSC Engine if the price feed is stale.
 */
library OracleLib {
    ////////////////////////
    // Errors
    ////////////////////////

    error OracleLib__StalePrice();

    ////////////////////////
    // State variables
    ////////////////////////
    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 timeSinceLastUpdated = block.timestamp - updatedAt;
        if (timeSinceLastUpdated > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }
}
