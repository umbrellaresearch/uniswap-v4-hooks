// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {FullRange} from "./FullRange.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {IERC20Minimal} from "v4-core/contracts/interfaces/external/IERC20Minimal.sol";

/**
 *               . . .  . .-. .-. .-. .   .   .-.   .-. .-. .-. .-. .-. .-. .-. . .
 *               | | |\/| |(  |(  |-  |   |   |-|   |(  |-  `-. |-  |-| |(  |   |-|
 *               `-' '  ` `-' ' ' `-' `-' `-' ` '   ' ' `-' `-' `-' ` ' ' ' `-' ' `
 *
 *   @title      LiquidityIncentivesHook
 *   @notice     Proof of concept implementation for a Liquidity Incentives Hook.
 *   @author     Umbrella Research SL
 */

contract LiquidityIncentivesHook is FullRange {
    constructor(IPoolManager _poolManager, IERC20Minimal _rewardsToken, address _rewardsDistribution)
        FullRange(_poolManager, _rewardsToken, _rewardsDistribution)
    {}

    // /* ========== STATE VARIABLES ========== */

    // IERC20 public rewardsToken;
    // IERC20 public stakingToken;
    // uint256 public periodFinish = 0;
    // uint256 public rewardRate = 0;
    // uint256 public rewardsDuration = 60 days;
    // uint256 public lastUpdateTime;
    // uint256 public rewardPerTokenStored;

    // mapping(address => uint256) public userRewardPerTokenPaid;
    // mapping(address => uint256) public rewards;

    // uint256 private _totalSupply;
    // mapping(address => uint256) private _balances;

    // /* ========== CONSTRUCTOR ========== */

    // constructor(
    //     address _rewardsDistribution,
    //     address _rewardsToken,
    //     address _stakingToken
    // ) public {
    //     rewardsToken = IERC20(_rewardsToken);
    //     stakingToken = IERC20(_stakingToken);
    //     rewardsDistribution = _rewardsDistribution;
    // }

    // Hook specific functions

    ////////////////////////////////
    ////// Action Callbacks ////////
    ////////////////////////////////
}
