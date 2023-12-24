// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RealizedVolatilityOracle {
    uint256 public realizedVolatility;
    uint256 public latestTimestamp;
    address public updater;

    modifier onlyUpdater() {
        require(msg.sender == updater, "RealizedVolatilityOracle: caller is not the updater");
        _;
    }

    constructor(address _updater) {
        updater = _updater;
    }

    function updateRealizedVolatility(uint256 _newVolatility) external onlyUpdater {
        realizedVolatility = _newVolatility;

        latestTimestamp = block.timestamp;
    }
}
