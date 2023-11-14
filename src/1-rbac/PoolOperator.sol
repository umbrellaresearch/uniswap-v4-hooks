// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ILockCallback} from "v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {PoolKey} from "v4-core/contracts/types/PoolKey.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/contracts/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/contracts/types/Currency.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Simple example of smart contract implementing a lockCallback
 * @notice This smart contract has been simplified in purpose for the sake of readability, do not use it in production
 */
contract PoolOperator is ILockCallback {
    using CurrencyLibrary for Currency;

    error NotPoolManager();
    error LockFailure();

    IPoolManager public immutable poolManager;

    uint8 constant SWAP_ACTION = 0;
    uint8 constant MODIFY_POSITION_ACTION = 1;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    ///////////////////////
    ////// Actions ////////
    ///////////////////////

    function lockSwap(PoolKey memory key, IPoolManager.SwapParams memory params) public {
        poolManager.lock(abi.encodeCall(this.performSwap, (key, params, msg.sender)));
    }

    function lockModifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params) public {
        poolManager.lock(abi.encodeCall(this.performModifyPosition, (key, params, msg.sender)));
    }

    ///////////////////////////////////////
    ////// Lock Acquired Callback ////////
    //////////////////////////////////////

    function lockAcquired(bytes calldata data) external virtual poolManagerOnly returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    ///////////////////////
    ////// Handlers ///////
    ///////////////////////

    function performSwap(PoolKey memory key, IPoolManager.SwapParams memory params, address user)
        external
        returns (BalanceDelta delta)
    {
        require(msg.sender == address(this));
        delta = poolManager.swap(key, params, abi.encode(user));

        if (params.zeroForOne) {
            if (delta.amount0() > 0) {
                IERC20(Currency.unwrap(key.currency0)).transfer(address(poolManager), uint128(delta.amount0()));
                poolManager.settle(key.currency0);
            }
            if (delta.amount1() < 0) {
                poolManager.take(key.currency1, user, uint128(-delta.amount1()));
            }
        } else {
            if (delta.amount1() > 0) {
                IERC20(Currency.unwrap(key.currency1)).transfer(address(poolManager), uint128(delta.amount1()));
                poolManager.settle(key.currency1);
            }
            if (delta.amount0() < 0) {
                poolManager.take(key.currency0, user, uint128(-delta.amount0()));
            }
        }
    }

    function performModifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params, address user)
        external
        returns (BalanceDelta delta)
    {
        require(msg.sender == address(this));
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
