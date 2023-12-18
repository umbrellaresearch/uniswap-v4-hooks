// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

contract RealizedVolatilityOracle {
    uint256 public realizedVolatility;
    uint256 public latestTimestamp;

    function updateRealizedVolatility(uint256 _newVolatility) external {
        realizedVolatility = _newVolatility;

        latestTimestamp = block.timestamp;
    }
}
