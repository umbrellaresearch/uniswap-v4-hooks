// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "v4-core-last/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core-last/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core-last/src/PoolManager.sol";
import {IPoolManager} from "v4-core-last/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core-last/src/types/PoolKey.sol";
import {Pool} from "v4-core-last/src/libraries/Pool.sol";
import {HookMiner} from "./utils/HookMiner.sol";
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

    address user = vm.addr(1);
    address deployerAddress = vm.addr(2);

    function setUp() public {
        // 1. Deploy contracts
        manager = new PoolManager(500000);

        gold = new TestERC20(mintAmount);
        silver = new TestERC20(mintAmount);

        volatilityOracle = new RealizedVolatilityOracle();
        feeHook = VolatilityFeeHook(deployHook());
        
        modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));

        // 2. Initialize Pool
        uint24 DYNAMIC_FEE_FLAG = 0x800000; // 1000  // TODO: Explain how this flag works

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
            IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), int256(liquidityAmount)),
            bytes("")
        );
    }

    function testGetFee() public {
        uint256 fee;

        // Test case 1: Realized volatility > 2200
        volatilityOracle.updateRealizedVolatility(2300);
        fee = feeHook.getFee(address(0x00), poolKey);
        assertEq(fee, 100, "Incorrect fee for realized volatility > 2200");

        // Test case 2: Realized volatility < 2200 & > 1800
        volatilityOracle.updateRealizedVolatility(2000);
        fee = feeHook.getFee(address(0x00), poolKey);
        assertEq(fee, 30, "Incorrect fee for realized volatility < 2200 & > 1800");

        // Test case 3: Realized volatility < 1800
        volatilityOracle.updateRealizedVolatility(1500);
        fee = feeHook.getFee(address(0x00), poolKey);
        assertEq(fee, 5, "Incorrect fee for realized volatility < 1800");
    }

    function testBeforeSwap() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings(true, true);

        // Test case 1: Realized volatility > 2200
        volatilityOracle.updateRealizedVolatility(2300);
        swapRouter.swap(poolKey, params, settings, ZERO_BYTES);
        (Pool.Slot0 memory slot0HighVolatility,,,) = manager.pools(poolKey.toId());
        uint24 swapFeeHighVolatility = slot0HighVolatility.swapFee;
        assertEq(swapFeeHighVolatility, 100, "Incorrect fee for realized volatility > 2200");

        // Test case 2: Realized volatility < 2200 & > 1800
        volatilityOracle.updateRealizedVolatility(2000);
        swapRouter.swap(poolKey, params, settings, ZERO_BYTES);
        (Pool.Slot0 memory slot0MediumVolatility,,,) = manager.pools(poolKey.toId());
        uint24 swapFeeMediumVolatility = slot0MediumVolatility.swapFee;
        assertEq(swapFeeMediumVolatility, 30, "Incorrect fee for realized volatility < 2200 & > 1800");

        // Test case 3: Realized volatility < 1800
        volatilityOracle.updateRealizedVolatility(1500);
        swapRouter.swap(poolKey, params, settings, ZERO_BYTES);
        (Pool.Slot0 memory slot0LowVolatility,,,) = manager.pools(poolKey.toId());
        uint24 swapFeeLowVolatility = slot0LowVolatility.swapFee;
        assertEq(swapFeeLowVolatility, 5, "Incorrect fee for realized volatility < 1800");
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
            abi.encode(address(manager), address(volatilityOracle))
        );

        feeHook = new VolatilityFeeHook{salt: salt}(manager, volatilityOracle);

        vm.stopPrank();
        return hookAddress;
    }
}
