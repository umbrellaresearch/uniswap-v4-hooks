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

    uint256 public highVolatilityTrigger = 1400;
    uint256 public mediumVolatilityTrigger = 1000;

    uint24 public highVolatilityFee = 100;
    uint24 public mediumVolatilityFee = 30;
    uint24 public lowVolatilityFee = 5;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "RealizedVolatilityOracle: caller is not the updater");
        _;
    }

    constructor(
        IPoolManager _poolManager,
        RealizedVolatilityOracle _volatilityOracle,
        uint256 _highVolatilityTrigger,
        uint256 _mediumVolatilityTrigger,
        uint24 _highVolatilityFee,
        uint24 _mediumVolatilityFee,
        uint24 _lowVolatilityFee
    ) {
        highVolatilityTrigger = _highVolatilityTrigger;
        mediumVolatilityTrigger = _mediumVolatilityTrigger;
        highVolatilityFee = _highVolatilityFee;
        mediumVolatilityFee = _mediumVolatilityFee;
        lowVolatilityFee = _lowVolatilityFee;

        poolManager = _poolManager;
        volatilityOracle = _volatilityOracle;
        owner = msg.sender;
    }

    ////////////////////////////////
    //////     Setters      ////////
    ////////////////////////////////

    function setHighVolatilityTrigger(uint256 _highVolatilityTrigger) external onlyOwner {
        highVolatilityTrigger = _highVolatilityTrigger;
    }

    function setMediumVolatilityTrigger(uint256 _mediumVolatilityTrigger) external onlyOwner {
        mediumVolatilityTrigger = _mediumVolatilityTrigger;
    }

    function setHighVolatilityFee(uint24 _highVolatilityFee) external onlyOwner {
        highVolatilityFee = _highVolatilityFee;
    }

    function setMediumVolatilityFee(uint24 _mediumVolatilityFee) external onlyOwner {
        mediumVolatilityFee = _mediumVolatilityFee;
    }

    function setLowVolatilityFee(uint24 _lowVolatilityFee) external onlyOwner {
        lowVolatilityFee = _lowVolatilityFee;
    }

    ////////////////////////////////
    ////// Action Callbacks ////////
    ////////////////////////////////

    /// @notice Ensures the current fee is updated according to the latest volatility values
    /// @dev This function doesn't to use some of the parameters passed to it, but it is required by the hook callback interface
    function beforeSwap(address, PoolKey calldata _poolKey, IPoolManager.SwapParams calldata, bytes calldata)
        external
        returns (bytes4)
    {
        // Update the swap fee if the last update was before the latest volatility update
        if (lastUpdate < volatilityOracle.latestTimestamp()) {
            poolManager.updateDynamicSwapFee(_poolKey);
        }

        return this.beforeSwap.selector;
    }

    /////////////////////////////
    ////// Hook Getters ////////
    ////////////////////////////

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
    function getFee(address, PoolKey calldata) external view returns (uint24) {
        uint256 realizedVolatility = volatilityOracle.realizedVolatility();
        if (realizedVolatility > uint256(highVolatilityTrigger)) {
            return highVolatilityFee;
        } else if (realizedVolatility < highVolatilityTrigger && realizedVolatility > uint256(mediumVolatilityTrigger)) {
            return mediumVolatilityFee;
        } else {
            return lowVolatilityFee;
        }
    }
}
