// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract AggregatorV3Fake {
    int public round = 2313557000000;

    function setCost(int _cost) external {
        round = _cost;
    }
    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "Hello World!))))";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        pure
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint80 _round = _roundId + 1;
        return (_round, 149098073, 1, 1, 1);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (5, round, 1, 1, 1);
    }
}
