// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "v4-core-last/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core-last/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core-last/src/PoolManager.sol";
import {IPoolManager} from "v4-core-last/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core-last/src/types/PoolKey.sol";
import {Pool} from "v4-core-last/src/libraries/Pool.sol";
import {PoolId, PoolIdLibrary} from "v4-core-last/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core-last/src/types/Currency.sol";
import {RealizedVolatilityOracle} from "../src/2-dynamic-fees/RealizedVolatilityOracle.sol";
import {VolatilityFeeHook} from "../src/2-dynamic-fees/VolatilityFeeHook.sol";
import {Deployers} from "v4-core/test/foundry-tests/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core-last/src/test/PoolSwapTest.sol";
import {PoolModifyPositionTest} from "v4-core-last/src/test/PoolModifyPositionTest.sol";
import {TestERC20} from "v4-core-last/src/test/TestERC20.sol";
import {TickMath} from "v4-core-last/src/libraries/TickMath.sol";
import {HookTest} from "./utils/HookTest.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract VolatilityFeeHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Pool for Pool.State;

    Pool.State state;

    PoolManager manager;
    RealizedVolatilityOracle volatilityOracle;
    VolatilityFeeHook feeHook;

    PoolKey poolKey;
    PoolId poolId;

    TestERC20 gold;
    TestERC20 silver;

    PoolSwapTest swapRouter;
    PoolModifyPositionTest modifyPositionRouter;

    // Amount of gold and silver that will be minted to the test user
    uint256 mintAmount = 100 ether;
    uint256 liquidityAmount = 10 ether;
    uint256 swapAmount = 1 ether;

    uint256 public highVolatilityTrigger = 1400;
    uint256 public mediumVolatilityTrigger = 1000;

    uint24 public highVolatilityFee = 100;
    uint24 public mediumVolatilityFee = 30;
    uint24 public lowVolatilityFee = 5;

    address user = vm.addr(1);
    address deployerAddress = vm.addr(2);
    address volatilityOracleUpdater = vm.addr(3);

    function setUp() public {
        // 1. Deploy contracts
        manager = new PoolManager(500000);

        gold = new TestERC20(mintAmount);
        silver = new TestERC20(mintAmount);

        volatilityOracle = new RealizedVolatilityOracle(volatilityOracleUpdater);
        feeHook = VolatilityFeeHook(deployHook());

        modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));

        // 2. Initialize Pool
        uint24 DYNAMIC_FEE_FLAG = 0x800000; // 1000

        poolKey = PoolKey(
            Currency.wrap(address(gold)), Currency.wrap(address(silver)), DYNAMIC_FEE_FLAG, 60, IHooks(address(feeHook))
        );
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

        // 3. Add liquidity to the Pool
        gold.approve(address(modifyPositionRouter), 100 ether);
        silver.approve(address(modifyPositionRouter), 100 ether);
        silver.approve(address(swapRouter), uint256(liquidityAmount));

        modifyPositionRouter.modifyPosition(
            poolKey,
            IPoolManager.ModifyPositionParams(
                TickMath.minUsableTick(60), TickMath.maxUsableTick(60), int256(liquidityAmount)
            ),
            bytes("")
        );
    }

    function testGetFee() public {
        uint256 fee;

        // Test case 1: Update volatility oracle with high volatility
        vm.startPrank(volatilityOracleUpdater);
        volatilityOracle.updateRealizedVolatility(highVolatilityTrigger + 1);
        vm.stopPrank();

        // Get fee should return highVolatilityFee
        fee = feeHook.getFee(address(0x00), poolKey);
        assertEq(fee, highVolatilityFee, "Incorrect fee for realized volatility > highVolatilityTrigger");

        // Test case 2: Update volatility oracle with medium volatility
        vm.startPrank(volatilityOracleUpdater);
        volatilityOracle.updateRealizedVolatility(mediumVolatilityTrigger + 1);
        vm.stopPrank();

        // Get fee should return mediumVolatilityFee
        fee = feeHook.getFee(address(0x00), poolKey);
        assertEq(
            fee,
            mediumVolatilityFee,
            "Incorrect fee for realized volatility < highVolatilityTrigger & > mediumVolatilityTrigger"
        );

        // Test case 3: Update volatility oracle with low volatility
        vm.startPrank(volatilityOracleUpdater);
        volatilityOracle.updateRealizedVolatility(mediumVolatilityTrigger - 1);
        vm.stopPrank();

        // Get fee should return lowVolatilityFee
        fee = feeHook.getFee(address(0x00), poolKey);
        assertEq(fee, lowVolatilityFee, "Incorrect fee for realized volatility < mediumVolatilityTrigger");
    }

    function testBeforeSwapUpdatesFee() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings(true, true);

        // Test case 1: Update volatility oracle with high volatility
        vm.startPrank(volatilityOracleUpdater);
        volatilityOracle.updateRealizedVolatility(highVolatilityTrigger + 1);
        vm.stopPrank();

        // BeforeSwap callback should have updated the fee to highVolatilityFee
        swapRouter.swap(poolKey, params, settings, ZERO_BYTES);
        (Pool.Slot0 memory slot0HighVolatility,,,) = manager.pools(poolKey.toId());
        uint24 swapFeeHighVolatility = slot0HighVolatility.swapFee;
        assertEq(
            swapFeeHighVolatility, highVolatilityFee, "Incorrect fee for realized volatility > highVolatilityTrigger"
        );

        // Test case 2: Update volatility oracle with medium volatility
        vm.startPrank(volatilityOracleUpdater);
        volatilityOracle.updateRealizedVolatility(mediumVolatilityTrigger + 1);
        vm.stopPrank();

        // BeforeSwap callback should have updated the fee to mediumVolatilityFee
        swapRouter.swap(poolKey, params, settings, ZERO_BYTES);
        (Pool.Slot0 memory slot0MediumVolatility,,,) = manager.pools(poolKey.toId());
        uint24 swapFeeMediumVolatility = slot0MediumVolatility.swapFee;
        assertEq(
            swapFeeMediumVolatility,
            mediumVolatilityFee,
            "Incorrect fee for realized volatility < highVolatilityTrigger & > mediumVolatilityTrigger"
        );

        // Test case 3: Update volatility oracle with low volatility
        vm.startPrank(volatilityOracleUpdater);
        volatilityOracle.updateRealizedVolatility(mediumVolatilityTrigger - 1);
        vm.stopPrank();

        // BeforeSwap callback should have updated the fee to lowVolatilityFee
        swapRouter.swap(poolKey, params, settings, ZERO_BYTES);
        (Pool.Slot0 memory slot0LowVolatility,,,) = manager.pools(poolKey.toId());
        uint24 swapFeeLowVolatility = slot0LowVolatility.swapFee;
        assertEq(
            swapFeeLowVolatility, lowVolatilityFee, "Incorrect fee for realized volatility < mediumVolatilityTrigger"
        );
    }

    function deployHook() private returns (address) {
        vm.startPrank(deployerAddress);

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployerAddress,
            flags,
            0,
            type(VolatilityFeeHook).creationCode,
            abi.encode(
                address(manager),
                address(volatilityOracle),
                highVolatilityTrigger,
                mediumVolatilityTrigger,
                highVolatilityFee,
                mediumVolatilityFee,
                lowVolatilityFee
            )
        );

        feeHook =
        new VolatilityFeeHook{salt: salt}(manager, volatilityOracle, highVolatilityTrigger, mediumVolatilityTrigger, highVolatilityFee, mediumVolatilityFee, lowVolatilityFee);

        vm.stopPrank();
        return hookAddress;
    }
}
