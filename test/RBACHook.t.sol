// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolOperator} from "../src/1-rbac/PoolOperator.sol";
import {RBACHook} from "../src/1-rbac/RBACHook.sol";
import {PirateChest} from "../src/1-rbac/utils/PirateChest.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {TestERC20} from "v4-core/src/test/TestERC20.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract RBACHookTest is Test, Fixtures {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    error MissingAmulet();
    error MissingPirateCredential();

    TestERC20 gold;
    TestERC20 silver;

    RBACHook rbacHook;
    PoolOperator poolOperator;
    PoolKey poolKey;
    PoolId poolId;
    PirateChest pirateChest;

    address deployerAddress = address(1);
    address amuletOwner = vm.addr(1);
    address pirateCredentialOwner = vm.addr(2);
    address unauthorizedUser = vm.addr(3);

    uint160 public constant SQRT_RATIO_1_1 = 79228162514264337593543950336;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        
        deployMintAndApprove2Currencies();

        // Amount of gold and silver that will be minted to the test user
        uint256 amount = 100 ether;

        gold = new TestERC20(amount);
        silver = new TestERC20(amount);

        manager = new PoolManager();
        poolOperator = new PoolOperator(manager);
        pirateChest = new PirateChest();

        address hookAddress = deployHook();

        rbacHook = RBACHook(hookAddress);

        // Send gold and silver to our users
        gold.mint(amuletOwner, amount);
        gold.mint(pirateCredentialOwner, amount);
        gold.mint(unauthorizedUser, amount);

        silver.mint(amuletOwner, amount);
        silver.mint(pirateCredentialOwner, amount);
        silver.mint(unauthorizedUser, amount);

        // Give test accounts some ETH to pay for transactions
        uint256 ethSeedAmount = 1 ether;
        vm.deal(amuletOwner, ethSeedAmount);
        vm.deal(pirateCredentialOwner, ethSeedAmount);
        vm.deal(unauthorizedUser, ethSeedAmount);

        // Mint an amulet and pirate credential for our users
        pirateChest.mintAmulet(amuletOwner);
        pirateChest.mintPirateCredential(pirateCredentialOwner);

        // Create the pool
        poolKey = PoolKey(Currency.wrap(address(gold)), Currency.wrap(address(silver)), 3000, 60, IHooks(rbacHook));
        poolId = poolKey.toId();

        manager.initialize(poolKey, SQRT_RATIO_1_1);
    }

    function testModifyLiquidityUnauthorized() public {
        // User doesn't have an amulet, should revert
        vm.startPrank(unauthorizedUser);

        // Approve gold and silver for liquidity provision from our user
        gold.approve(address(poolOperator), type(uint256).max);
        silver.approve(address(poolOperator), type(uint256).max);

        vm.expectRevert();
        poolOperator.lockModifyPosition(poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether, ""));
    }

    function testModifyLiquidityAuthorized() public {
        vm.startPrank(amuletOwner);

        // Approve gold and silver for liquidity provision from our user
        gold.approve(address(poolOperator), type(uint256).max);
        silver.approve(address(poolOperator), type(uint256).max);

        // User does have an amulet, it should pass
        poolOperator.lockModifyPosition(poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether, ""));
    }

    function testSwapUnauthorized() public {
        // User doesn't have an amulet, should revert
        vm.startPrank(unauthorizedUser);

        // Approve gold for a swap from our user
        gold.approve(address(poolOperator), type(uint256).max);

        bool zeroForOne = true;

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: !zeroForOne,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        vm.expectRevert();
        poolOperator.lockSwap(poolKey, params);
    }

    function testSwapAuthorized() public {
        vm.startPrank(pirateCredentialOwner);

        // Approve gold and silver for liquidity provision from our user
        gold.approve(address(poolOperator), type(uint256).max);

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 2,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        // User does have an amulet, it should pass
        poolOperator.lockSwap(poolKey, params);
    }

    function deployHook() private returns (address) {
        vm.startPrank(deployerAddress);

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployerAddress,
            flags,
            type(RBACHook).creationCode,
            abi.encode(address(manager), address(pirateChest), address(poolOperator))
        );

        rbacHook = new RBACHook{salt: salt}(manager, address(pirateChest), address(poolOperator));

        vm.stopPrank();
        return hookAddress;
    }
}
