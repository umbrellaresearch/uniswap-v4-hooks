// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FullRange} from "./FullRange.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {IERC20Minimal} from "v4-core/contracts/interfaces/external/IERC20Minimal.sol";
import "./StakingRewards.sol";

/**
 *               . . .  . .-. .-. .-. .   .   .-.   .-. .-. .-. .-. .-. .-. .-. . .
 *               | | |\/| |(  |(  |-  |   |   |-|   |(  |-  `-. |-  |-| |(  |   |-|
 *               `-' '  ` `-' ' ' `-' `-' `-' ` '   ' ' `-' `-' `-' ` ' ' ' `-' ' `
 *
 *   @title      LiquidityIncentivesHook
 *   @notice     Proof of concept implementation for a Liquidity Incentives Hook.
 *   @author     Umbrella Research SL
 */

contract LiquidityIncentivesHook is FullRange, StakingRewards {
    constructor(IPoolManager _poolManager, IERC20Minimal _rewardsToken, address _rewardsDistribution)
        FullRange(_poolManager)
        StakingRewards(_rewardsToken, _rewardsDistribution)
    {}

    ////////////////////////////////
    ////// Action Callbacks ////////
    ////////////////////////////////

    function addLiquidityAndStake(AddLiquidityParams calldata params) external {
        // 1: Add liquidity to the pool
        uint256 liquidity = _addLiquidity(params);

        // 2: Stake the liquidity
        _stake(liquidity, params.to);
    }

    function removeLiquidityAndUnstake(RemoveLiquidityParams calldata params) external {
        // 1: Remove the liquidity from the pool
        _removeLiquidity(params);

        // 2: Unstake the liquidity from the msgSender
        _withdraw(params.liquidity, msg.sender);
    }

    function liquidityStakedPerUser(address user) external view returns (uint256) {
        return _balances[user];
    }
}
