// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 *               . . .  . .-. .-. .-. .   .   .-.   .-. .-. .-. .-. .-. .-. .-. . .
 *               | | |\/| |(  |(  |-  |   |   |-|   |(  |-  `-. |-  |-| |(  |   |-|
 *               `-' '  ` `-' ' ' `-' `-' `-' ` '   ' ' `-' `-' `-' ` ' ' ' `-' ' `
 *
 *   @title      RewardsDistributionRecipient
 *   @notice     Modified version of the Uniswap RewardsDistributionRecipient contract Unaudited, this is a proof of concept and NOT READY FOR PRODUCTION USE!
 *   @author     Umbrella Research SL
 */

abstract contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }
}
