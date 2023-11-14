// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "v4-core/contracts/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/contracts/types/Currency.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract RBACHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    error MissingAmulet();
    error MissingPirateCredential();
    error NotPoolOperator();

    IERC1155 immutable pirateChest;

    address allowedPoolOperator;

    uint256 public constant AMULET = 1;
    uint256 public constant PIRATE_CREDENTIAL = 2;

    constructor(IPoolManager _poolManager, address _pirateChest, address _allowedPoolOperator) BaseHook(_poolManager) {
        allowedPoolOperator = _allowedPoolOperator;
        pirateChest = IERC1155(_pirateChest);
    }

    /// @dev Only the pool operator may call this function
    modifier poolOperatorOnly(address sender) {
        if (sender != address(allowedPoolOperator)) revert NotPoolOperator();
        _;
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    ////////////////////////////////
    ////// Action Callbacks ////////
    ////////////////////////////////

    function beforeSwap(address sender, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        view
        override
        returns (bytes4)
    {
        if (sender != allowedPoolOperator) {
            revert NotPoolOperator();
        }

        address user = abi.decode(hookData, (address));

        if (pirateChest.balanceOf(user, PIRATE_CREDENTIAL) == 0) {
            revert MissingPirateCredential();
        }

        return BaseHook.beforeSwap.selector;
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata hookData
    ) external view override returns (bytes4) {
        if (sender != allowedPoolOperator) {
            revert NotPoolOperator();
        }

        address user = abi.decode(hookData, (address));

        if (pirateChest.balanceOf(user, AMULET) == 0) {
            revert MissingAmulet();
        }

        return BaseHook.beforeModifyPosition.selector;
    }
}
