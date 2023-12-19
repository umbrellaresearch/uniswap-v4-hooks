// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ILockCallback} from "v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {PoolKey} from "v4-core/contracts/types/PoolKey.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/contracts/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/contracts/types/Currency.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 *               . . .  . .-. .-. .-. .   .   .-.   .-. .-. .-. .-. .-. .-. .-. . .
 *               | | |\/| |(  |(  |-  |   |   |-|   |(  |-  `-. |-  |-| |(  |   |-|
 *               `-' '  ` `-' ' ' `-' `-' `-' ` '   ' ' `-' `-' `-' ` ' ' ' `-' ' `
 *
 *   @title      PoolOperator
 *   @notice     Proof of concept implementation for Pool Operator contract, in charge of managing the Pool Manager lock
 *               in order to allow users to perform swaps and modifyPosition operations.
 *   @author     Umbrella Research SL
 */
contract PoolOperator is ILockCallback {
    using CurrencyLibrary for Currency;

    /// @dev Thrown when msg.sender is not the pool operator (this contract)
    error NotPoolOperator();
    /// @dev Thrown when msg.sender is not the Uniswap V4 Pool Manager contract
    error NotPoolManager();
    /// @dev Thrown when actions performed while the lock has been acquired fail
    error LockFailure();

    /// @dev Uniswap V4 pool manager
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @dev Only the pool operator itself may call this function
    modifier poolOperatorOnly() {
        if (msg.sender != address(this)) revert NotPoolOperator();
        _;
    }

    ///////////////////////
    ////// Actions ////////
    ///////////////////////

    /// @notice Performs a swap operation
    /// @dev Requests a lock from the pool manager and when acquired, it performs the swap on the callback
    /// @param key Uniquely identifies the pool to use for the swap
    /// @param params Describes the swap operation
    function lockSwap(PoolKey memory key, IPoolManager.SwapParams memory params) public {
        poolManager.lock(abi.encodeCall(this.performSwap, (key, params, msg.sender)));
    }

    /// @notice Modifies a liquidity position
    /// @dev Requests a lock from the pool manager and when acquired, it performs a modifyPosition operation on the
    ///      callback
    /// @param key Uniquely identifies the pool to use for the swap
    /// @param params Describes the modifyPosition operation
    function lockModifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params) public {
        poolManager.lock(abi.encodeCall(this.performModifyPosition, (key, params, msg.sender)));
    }

    ///////////////////////////////////////
    ////// Lock Acquired Callback ////////
    //////////////////////////////////////

    /// @dev Callback from Uniswap V4 Pool Manager once the lock is acquired, so that pool actions can be performed.
    ///      The data will be a payload to execute against this contract.
    /// @param data Necessary data to perform the desired operations
    function lockAcquired(bytes calldata data) external virtual poolManagerOnly returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // If the call failed, bubble up the reason
        assembly ("memory-safe") {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    ///////////////////////
    ////// Handlers ///////
    ///////////////////////

    /// @dev Performs a swap operation only when the lock has been acquired
    /// @param key Unique identifier for the pool
    /// @param params Swap parameters
    /// @param user User address who wants to perform the swap
    function performSwap(PoolKey memory key, IPoolManager.SwapParams memory params, address user)
        external
        poolOperatorOnly
        returns (BalanceDelta delta)
    {
        // Call `swap` with the user address (initiator) encoded as `hookData`
        delta = poolManager.swap(key, params, abi.encode(user));

        // Swapping token0 for token1
        if (params.zeroForOne) {
            // User owes tokens to the pool
            if (delta.amount0() > 0) {
                IERC20(Currency.unwrap(key.currency0)).transfer(address(poolManager), uint128(delta.amount0()));
                poolManager.settle(key.currency0);
            }
            // Pool owes tokens to the user
            if (delta.amount1() < 0) {
                poolManager.take(key.currency1, user, uint128(-delta.amount1()));
            }
            // Swapping token1 for token0
        } else {
            // User owes tokens to the pool
            if (delta.amount1() > 0) {
                IERC20(Currency.unwrap(key.currency1)).transfer(address(poolManager), uint128(delta.amount1()));
                poolManager.settle(key.currency1);
            }
            // Pool owes tokens to the user
            if (delta.amount0() < 0) {
                poolManager.take(key.currency0, user, uint128(-delta.amount0()));
            }
        }
    }

    /// @dev Performs a modifyPosition operation only when the lock has been acquired
    /// @param key Unique identifier for the pool
    /// @param params ModifyPosition parameters
    /// @param user User address who wants to modify his liquidity position
    function performModifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params, address user)
        external
        poolOperatorOnly
        returns (BalanceDelta delta)
    {
        // Call `modifyPosition` with the user address (initiator) encoded as `hookData`
        delta = poolManager.modifyPosition(key, params, abi.encode(user));
        // At this point, the `beforeModifyPosition` in our hook contract has already been executed

        // User owes tokens to the pool
        if (delta.amount0() > 0) {
            IERC20(Currency.unwrap(key.currency0)).transferFrom(user, address(poolManager), uint128(delta.amount0()));
            poolManager.settle(key.currency0);
        }

        // Pool owes tokens to the user
        if (delta.amount0() < 0) {
            poolManager.take(key.currency0, user, uint128(-delta.amount0()));
        }

        // User owes tokens to the pool
        if (delta.amount1() > 0) {
            IERC20(Currency.unwrap(key.currency1)).transferFrom(user, address(poolManager), uint128(delta.amount1()));
            poolManager.settle(key.currency1);
        }

        // Pool owes tokens to the user
        if (delta.amount1() < 0) {
            poolManager.take(key.currency1, user, uint128(-delta.amount1()));
        }
    }
}
