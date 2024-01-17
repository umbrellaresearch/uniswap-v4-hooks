// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/contracts/PoolManager.sol";
import {PoolKey} from "v4-core/contracts/types/PoolKey.sol";
import {Pool} from "v4-core/contracts/libraries/Pool.sol";
import {PoolId, PoolIdLibrary} from "v4-core/contracts/types/PoolId.sol";
import {Deployers} from "v4-core/test/foundry-tests/utils/Deployers.sol";
import {CurrencyLibrary, Currency} from "v4-core/contracts/types/Currency.sol";

import {RealizedVolatilityOracle} from "../src/2-dynamic-fees/RealizedVolatilityOracle.sol";
import {LiquidityIncentivesHook} from "../src/3-liquidity-incentives/LiquidityIncentivesHook.sol";
import {Deployers} from "v4-core/test/foundry-tests/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/contracts/test/PoolSwapTest.sol";
import {PoolModifyPositionTest} from "v4-core/contracts/test/PoolModifyPositionTest.sol";
import {TestERC20} from "v4-core/contracts/test/TestERC20.sol";
import {TickMath} from "v4-core/contracts/libraries/TickMath.sol";
import {FullRange} from "../src/3-liquidity-incentives/FullRange.sol";
import {HookTest} from "./utils/HookTest.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract LiquidityIncentivesHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Pool for Pool.State;

    Pool.State state;

    PoolManager manager;
    FullRange liquidityIncentivesHook;
    TestERC20 rewardsToken;

    int24 constant TICK_SPACING = 60;
    uint16 constant LOCKED_LIQUIDITY = 1000; // TODO UNDERSTAND THIS NUMBER
    uint256 constant MAX_DEADLINE = 12329839823;
    uint256 constant MAX_TICK_LIQUIDITY = 11505069308564788430434325881101412;
    uint8 constant DUST = 30;
    uint256 constant TOTAL_REWARDS_AMOUNT = 100000 ether;

    TestERC20 token0;
    TestERC20 token1;
    TestERC20 token2;
    TestERC20 token3;

    Currency currency0;
    Currency currency1;

    address deployerAddress = address(1);
    address user = address(2);
    address rewardsDistribution = address(3);

    // FullRangeImplementation fullRange = FullRangeImplementation(
    //     address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG))
    // );

    PoolKey key;
    PoolId id;

    PoolKey key2;
    PoolId id2;

    // For a pool that gets initialized with liquidity in setUp()
    PoolKey keyWithLiq;
    PoolId idWithLiq;

    // For a pool that gets initialized with liquidity staked in setUp()
    PoolKey keyWithLiqStaked;
    PoolId idWithLiqStaked;

    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;

    function setUp() public {
        console.log("setting up");
        token0 = new TestERC20(2 ** 128);
        token1 = new TestERC20(2 ** 128);
        token2 = new TestERC20(2 ** 128);
        token3 = new TestERC20(2 ** 128);

        rewardsToken = new TestERC20(TOTAL_REWARDS_AMOUNT);

        console.log("balance of rewards token", rewardsToken.balanceOf(address(this)));

        manager = new PoolManager(500000);

        address liquidityIncentivesHookAddress = deployHook();
        liquidityIncentivesHook = FullRange(liquidityIncentivesHookAddress);

        console.log("deployed hook at address %s", liquidityIncentivesHookAddress);

        key = PoolKey(
            Currency.wrap(address(token1)),
            Currency.wrap(address(token0)),
            3000,
            60,
            IHooks(liquidityIncentivesHookAddress)
        );
        id = key.toId();

        key2 = PoolKey(
            Currency.wrap(address(token1)),
            Currency.wrap(address(token2)),
            3000,
            60,
            IHooks(liquidityIncentivesHookAddress)
        );
        id2 = key.toId();

        keyWithLiq = PoolKey(
            Currency.wrap(address(token2)), // TODO CHANGE IT WHEN FIXED SYMBOL ISSUE
            Currency.wrap(address(token0)),
            3000,
            60,
            IHooks(liquidityIncentivesHookAddress)
        );
        idWithLiq = keyWithLiq.toId();

        keyWithLiqStaked = PoolKey(
            Currency.wrap(address(token3)), // TODO CHANGE IT WHEN FIXED SYMBOL ISSUE
            Currency.wrap(address(token0)),
            3000,
            60,
            IHooks(liquidityIncentivesHookAddress)
        );
        idWithLiqStaked = keyWithLiqStaked.toId();

        modifyPositionRouter = new PoolModifyPositionTest(manager);
        swapRouter = new PoolSwapTest(manager);

        token0.approve(address(liquidityIncentivesHook), type(uint256).max);
        token1.approve(address(liquidityIncentivesHook), type(uint256).max);
        token2.approve(address(liquidityIncentivesHook), type(uint256).max);
        token3.approve(address(liquidityIncentivesHook), type(uint256).max);

        console.log("setting up done, initializing");

        manager.initialize(keyWithLiq, SQRT_RATIO_1_1, ZERO_BYTES);
        manager.initialize(keyWithLiqStaked, SQRT_RATIO_1_1, ZERO_BYTES);

        console.log("initialized, adding liquidity");
        liquidityIncentivesHook.lockAddLiquidity(
            FullRange.AddLiquidityParams(
                keyWithLiq.currency0,
                keyWithLiq.currency1,
                3000,
                100 ether,
                100 ether,
                99 ether,
                99 ether,
                address(this),
                MAX_DEADLINE,
                false
            )
        );

        console.log("liquidity added, staking");
        liquidityIncentivesHook.lockAddLiquidity(
            FullRange.AddLiquidityParams(
                keyWithLiqStaked.currency0,
                keyWithLiqStaked.currency1,
                3000,
                100 ether,
                100 ether,
                99 ether,
                99 ether,
                address(this),
                MAX_DEADLINE,
                true
            )
        );
        console.log("staking done");

        rewardsToken.transfer(address(liquidityIncentivesHook), TOTAL_REWARDS_AMOUNT);

        vm.startPrank(rewardsDistribution);
        liquidityIncentivesHook.notifyRewardAmount(TOTAL_REWARDS_AMOUNT);
        vm.stopPrank();
    }

    ////////////////////////////////
    //////   Add Liquidity  ////////
    ////////////////////////////////

    //  1. Not Staking ///

    function testFullRange_addLiquidity_withoutStaking() public {
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        bool isStaking = false;

        (, address liquidityToken) = liquidityIncentivesHook.poolInfo(idWithLiq);

        uint256 prevBalance0 = keyWithLiq.currency0.balanceOf(address(this));
        uint256 prevBalance1 = keyWithLiq.currency1.balanceOf(address(this));
        uint256 prevLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 prevLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 prevTotalLiquidity = manager.getLiquidity(idWithLiq);

        FullRange.AddLiquidityParams memory addLiquidityParams = FullRange.AddLiquidityParams(
            keyWithLiq.currency0,
            keyWithLiq.currency1,
            3000,
            10 ether,
            10 ether,
            9 ether,
            9 ether,
            address(this),
            MAX_DEADLINE,
            isStaking
        );

        liquidityIncentivesHook.lockAddLiquidity(addLiquidityParams);

        (bool hasAccruedFees,) = liquidityIncentivesHook.poolInfo(idWithLiq);

        uint256 postBalance0 = keyWithLiq.currency0.balanceOf(address(this));
        uint256 postBalance1 = keyWithLiq.currency1.balanceOf(address(this));
        uint256 postLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 postLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 postTotalLiquidity = manager.getLiquidity(idWithLiq);

        assertEq(postBalance0, prevBalance0 - 10 ether);
        assertEq(postBalance1, prevBalance1 - 10 ether);
        assertEq(postLiquidityTokenBal, prevLiquidityTokenBal + 10 ether);
        assertEq(postLiquidityStaked, prevLiquidityStaked);
        assertEq(postTotalLiquidity, prevTotalLiquidity + 10 ether);

        assertEq(hasAccruedFees, false);
    }

    ////  2. Staking ///

    function testFullRange_addLiquidity_staking() public {
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        bool isStaking = true;

        (, address liquidityToken) = liquidityIncentivesHook.poolInfo(idWithLiq);

        uint256 prevBalance0 = keyWithLiq.currency0.balanceOf(address(this));
        uint256 prevBalance1 = keyWithLiq.currency1.balanceOf(address(this));
        uint256 prevLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 prevLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 prevTotalLiquidity = manager.getLiquidity(idWithLiq);

        FullRange.AddLiquidityParams memory addLiquidityParams = FullRange.AddLiquidityParams(
            keyWithLiq.currency0,
            keyWithLiq.currency1,
            3000,
            10 ether,
            10 ether,
            9 ether,
            9 ether,
            address(this),
            MAX_DEADLINE,
            isStaking
        );

        liquidityIncentivesHook.lockAddLiquidity(addLiquidityParams);

        (bool hasAccruedFees,) = liquidityIncentivesHook.poolInfo(idWithLiq);

        uint256 postBalance0 = keyWithLiq.currency0.balanceOf(address(this));
        uint256 postBalance1 = keyWithLiq.currency1.balanceOf(address(this));
        uint256 postLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 postLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 postTotalLiquidity = manager.getLiquidity(idWithLiq);

        assertEq(postBalance0, prevBalance0 - 10 ether);
        console.log("postBalance0", postBalance0);
        assertEq(postBalance1, prevBalance1 - 10 ether);
        console.log("postBalance1", postBalance1);
        assertEq(postLiquidityTokenBal, prevLiquidityTokenBal);
        console.log("postLiquidityTokenBal", postLiquidityTokenBal);
        assertEq(postLiquidityStaked, prevLiquidityStaked + 10 ether);
        console.log("postLiquidityStaked", postLiquidityStaked);
        assertEq(postTotalLiquidity, prevTotalLiquidity + 10 ether);
        console.log("postTotalLiquidity", postTotalLiquidity);
        assertEq(hasAccruedFees, false);
    }

    ////////////////////////////////
    //////  Remove Liquidity  //////
    ////////////////////////////////

    function testFullRange_removeLiquidity_withoutUnstaking() public {
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        bool isUnstaking = false;

        (, address liquidityToken) = liquidityIncentivesHook.poolInfo(idWithLiq);

        uint256 prevBalance0 = keyWithLiq.currency0.balanceOf(address(this));
        uint256 prevBalance1 = keyWithLiq.currency1.balanceOf(address(this));
        uint256 prevLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 prevLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 prevTotalLiquidity = manager.getLiquidity(idWithLiq);

        TestERC20(liquidityToken).approve(address(liquidityIncentivesHook), type(uint256).max);

        FullRange.RemoveLiquidityParams memory removeLiquidityParams = FullRange.RemoveLiquidityParams(
            keyWithLiq.currency0, keyWithLiq.currency1, 3000, 1 ether, MAX_DEADLINE, isUnstaking
        );

        liquidityIncentivesHook.lockRemoveLiquidity(removeLiquidityParams);

        (bool hasAccruedFees,) = liquidityIncentivesHook.poolInfo(idWithLiq);

        uint256 postBalance0 = keyWithLiq.currency0.balanceOf(address(this));
        uint256 postBalance1 = keyWithLiq.currency1.balanceOf(address(this));
        uint256 postLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 postLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 postTotalLiquidity = manager.getLiquidity(idWithLiq);

        assertEq(postBalance0, prevBalance0 + 1 ether - 1);
        assertEq(postBalance0, prevBalance0 + 1 ether - 1);
        assertEq(postLiquidityTokenBal, prevLiquidityTokenBal - 1 ether);
        assertEq(postLiquidityStaked, prevLiquidityStaked);
        assertEq(postTotalLiquidity, prevTotalLiquidity - 1 ether);

        assertEq(hasAccruedFees, false);
    }

    function testFullRange_removeLiquidity_unstaking() public {
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        bool isUnstaking = true;

        (, address liquidityToken) = liquidityIncentivesHook.poolInfo(idWithLiqStaked);

        uint256 prevBalance0 = keyWithLiqStaked.currency0.balanceOf(address(this));
        uint256 prevBalance1 = keyWithLiqStaked.currency1.balanceOf(address(this));
        uint256 prevLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 prevLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 prevTotalLiquidity = manager.getLiquidity(idWithLiqStaked);

        TestERC20(liquidityToken).approve(address(liquidityIncentivesHook), type(uint256).max);

        FullRange.RemoveLiquidityParams memory removeLiquidityParams = FullRange.RemoveLiquidityParams(
            keyWithLiqStaked.currency0, keyWithLiqStaked.currency1, 3000, 1 ether, MAX_DEADLINE, isUnstaking
        );

        liquidityIncentivesHook.lockRemoveLiquidity(removeLiquidityParams);

        (bool hasAccruedFees,) = liquidityIncentivesHook.poolInfo(idWithLiqStaked);

        uint256 postBalance0 = keyWithLiqStaked.currency0.balanceOf(address(this));
        uint256 postBalance1 = keyWithLiqStaked.currency1.balanceOf(address(this));
        uint256 postLiquidityTokenBal = TestERC20(liquidityToken).balanceOf(address(this));
        uint256 postLiquidityStaked = liquidityIncentivesHook.liquidityStakedPerUser(address(this));
        uint256 postTotalLiquidity = manager.getLiquidity(idWithLiqStaked);

        assertEq(postBalance0, prevBalance0 + 1 ether - 1);
        assertEq(postBalance0, prevBalance0 + 1 ether - 1);
        assertEq(postLiquidityTokenBal, prevLiquidityTokenBal);
        assertEq(postLiquidityStaked, prevLiquidityStaked - 1 ether);
        assertEq(postTotalLiquidity, prevTotalLiquidity - 1 ether);

        assertEq(hasAccruedFees, false);
    }

    /////////////////////////////////////
    //////  Liquidity Incentives  ///////
    ////////////////////////////////////

    function testFullRange_getReward() public {
        uint256 prevRewardsTokenBalance = rewardsToken.balanceOf(address(this));
        uint256 timeElapsed = 1000;

        vm.warp(block.timestamp + timeElapsed);

        liquidityIncentivesHook.getReward();

        uint256 postRewardsTokenBalance = rewardsToken.balanceOf(address(this));

        console.log("prevRewardsTokenBalance", prevRewardsTokenBalance);
        console.log("postRewardsTokenBalance", postRewardsTokenBalance);

        uint256 amountPerMilliSecond = TOTAL_REWARDS_AMOUNT * 1000 / 60 days;

        console.log("amountPerSecond", amountPerMilliSecond);

        assertGt(postRewardsTokenBalance, prevRewardsTokenBalance);
    }

    function deployHook() private returns (address) {
        vm.startPrank(deployerAddress);

        // Deploy the hook to an address with the correct flags
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_INITIALIZE_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployerAddress,
            flags,
            0,
            type(FullRange).creationCode,
            abi.encode(address(manager), address(rewardsToken), rewardsDistribution)
        );

        console.log("deploying hook at address %s", hookAddress);

        liquidityIncentivesHook = new FullRange{salt: salt}(manager, rewardsToken, rewardsDistribution);

        console.log("deployed hook at address %s", hookAddress);

        vm.stopPrank();
        return hookAddress;
    }
}
