// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/contracts/types/PoolKey.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

/**
 *              . . .  . .-. .-. .-. .   .   .-.   .-. .-. .-. .-. .-. .-. .-. . .
 *              | | |\/| |(  |(  |-  |   |   |-|   |(  |-  `-. |-  |-| |(  |   |-|
 *              `-' '  ` `-' ' ' `-' `-' `-' ` '   ' ' `-' `-' `-' ` ' ' ' `-' ' `
 *
 *  @title      RBACHook
 *  @notice     Proof of concept implementation for a Role-Based Access Hook.
 *  @author     Umbrella Research SL
 */
contract RBACHook is BaseHook {
    /// @dev Thrown when trying to perform a modifyPosition operation without the proper credential
    error MissingAmulet();
    /// @dev Thrown when trying to perform a swap operation without the proper credential
    error MissingPirateCredential();
    /// @dev Thrown when the lock acquirer does not match the allowed pool operator
    error NotPoolOperator();

    /// @dev IERC1155 Multi Token Standard contract that contains the credentials to operate with this pool
    IERC1155 immutable pirateChest;
    /// @dev Only our specific pool operator may engage with pool to swap or modifyPosition and thus, with these hooks.
    address allowedPoolOperator;

    /// @dev ID for the credential necessary to perform modifyPosition operations
    uint256 public constant AMULET = 1;
    /// @dev ID for the credential necessary to perform swap operations
    uint256 public constant PIRATE_CREDENTIAL = 2;

    constructor(IPoolManager _poolManager, address _pirateChest, address _allowedPoolOperator) BaseHook(_poolManager) {
        allowedPoolOperator = _allowedPoolOperator;
        pirateChest = IERC1155(_pirateChest);
    }

    /// @dev Only the pool operator may call this function
    /// @param sender The address which called the Pool Manager to request the swap / modifyPosition action
    modifier poolOperatorOnly(address sender) {
        if (sender != address(allowedPoolOperator)) revert NotPoolOperator();
        _;
    }

    /// @dev Lists the callbacks this hook implements. The hook address prefix should reflect this:
    ///      https://github.com/Uniswap/v4-core/blob/main/docs/whitepaper-v4.pdf
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

    /// @notice Ensures the original user possesses the necessary credential to perform swaps on this pool
    /// @param sender The address that initiated the swap. It will revert if it is not the allowed operator.
    /// @param hookData Extra custom data for the hook, contains the original user address (who initiated the transaction)
    function beforeSwap(address sender, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        view
        override
        returns (bytes4)
    {
        if (sender != allowedPoolOperator) {
            revert NotPoolOperator();
        }

        address user = _getUserAddress(hookData);

        if (pirateChest.balanceOf(user, PIRATE_CREDENTIAL) == 0) {
            revert MissingPirateCredential();
        }

        return BaseHook.beforeSwap.selector;
    }

    /// @notice Ensures the original user possesses the necessary credential to modify liquidity positions on this pool
    /// @param sender The address that initiated the modifyPosition. It will revert if it is not the allowed operator.
    /// @param hookData Extra custom data for the hook, contains the original user address (who initiated the transaction)
    function beforeModifyPosition(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata hookData
    ) external view override returns (bytes4) {
        if (sender != allowedPoolOperator) {
            revert NotPoolOperator();
        }

        address user = _getUserAddress(hookData);

        if (pirateChest.balanceOf(user, AMULET) == 0) {
            revert MissingAmulet();
        }

        return BaseHook.beforeModifyPosition.selector;
    }

    //////////////////////////////////
    ////// Internal Functions ////////
    //////////////////////////////////

    function _getUserAddress(bytes calldata hookData) internal pure returns (address user) {
        user = abi.decode(hookData, (address));
    }
}
