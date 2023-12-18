// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ILockCallback} from "v4-core-last/src/interfaces/callback/ILockCallback.sol";
import {PoolKey} from "v4-core-last/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core-last/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core-last/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core-last/src/types/Currency.sol";
import {Hooks} from "v4-core-last/src/libraries/Hooks.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {RealizedVolatilityOracle} from "./RealizedVolatilityOracle.sol";
import {IDynamicFeeManager} from "v4-core-last/src/interfaces/IDynamicFeeManager.sol";
import "forge-std/console.sol";
/**
 *               . . .  . .-. .-. .-. .   .   .-.   .-. .-. .-. .-. .-. .-. .-. . .
 *               | | |\/| |(  |(  |-  |   |   |-|   |(  |-  `-. |-  |-| |(  |   |-|
 *               `-' '  ` `-' ' ' `-' `-' `-' ` '   ' ' `-' `-' `-' ` ' ' ' `-' ' `
 *
 *   @title      DynamicFeeHook
 *   @notice     Proof of concept implementation for a Dynamic Fee Hook.
 *   @author     Umbrella Research SL
 */

contract VolatilityFeeHook is IDynamicFeeManager {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable poolManager;
    RealizedVolatilityOracle public immutable volatilityOracle;
    uint256 lastUpdate;

    constructor(IPoolManager _poolManager, RealizedVolatilityOracle _volatilityOracle) {
        poolManager = _poolManager;
        volatilityOracle = _volatilityOracle;
    }

    /// @dev Lists the callbacks this hook implements. The hook address prefix should reflect this:
    ///      https://github.com/Uniswap/v4-core/blob/main/docs/whitepaper-v4.pdf
    function getHooksCalls() public pure returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: false,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    // @dev Returns a fee based on the realized volatility of the underlying asset
    // @return fee The fee to be charged
    // Realized Volatility (bps) | Fee (bps)
    // --------------------------|-----
    //  > 2200                   | 100
    // --------------------------|-----
    //  1800 to 2199             | 20
    // --------------------------|-----
    //  < 1800                   | 40
    // --------------------------|-----
    function getFee(address, PoolKey calldata) external view returns (uint24) {
        uint256 realizedVolatility = volatilityOracle.realizedVolatility();
        if (realizedVolatility > uint256(2200)) {
            // Realized volatility >22 %
            return 100;
        } else if (realizedVolatility < 2200 && realizedVolatility > uint256(1800)) {
            // Realized volatility is < 22% and > 18%
            return 30;
        } else {
            // Realized volatility is < 18%
            return 5;
        }
    }

    /// @notice Ensures the current fee is updated according to the latest volatility values
    /// @dev This function doesn't to use some of the parameters passed to it, but it is required by the hook callback interface
    function beforeSwap(address, PoolKey calldata _poolKey, IPoolManager.SwapParams calldata, bytes calldata)
        external
        returns (bytes4)
    {
        if (lastUpdate < volatilityOracle.latestTimestamp()) {
            poolManager.updateDynamicSwapFee(_poolKey);
        }

        return this.beforeSwap.selector;
    }
}
