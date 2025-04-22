// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PegStabilityHook} from "../../PegStabilityHook.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SqrtPriceLibrary} from "../../libraries/SqrtPriceLibrary.sol";
import {IRateProvider} from "../../interfaces/IRateProvider.sol";

/// @title Parity Stability
/// @notice A peg stability hook, for pairs that trade at a 1:1 ratio
/// The hook charges 1 bip for trades moving towards the peg
/// otherwise it charges a linearly-scaled fee based on the distance from the peg
/// i.e. if the pool price is off by 0.05% the fee is 0.05%, if the price is off by 0.50% the fee is 0.5%
contract ParityStability is PegStabilityHook {
    IRateProvider public immutable rateProvider;

    // Fee bps range where 1_000_000 = 100 %
    uint24 public constant MAX_FEE_BPS = 10_000; // 1% max fee allowed, 1% = 10_000
    uint24 public constant MIN_FEE_BPS = 100; // 0.01% mix fee allowed

    uint24 public immutable maxFeeBps;
    uint24 public immutable minFeeBps;

    // Errors
    // @dev error when Invalid zero input params
    error InvalidZeroInput();

    /// @dev Error when custom max fee overflow
    error InvalidMaxFee();

    /// @dev Error when min fee overflow
    error InvalidMinFee();

    constructor(
        IPoolManager _poolManager,
        IRateProvider _rateProvider,
        uint24 _minFee,
        uint24 _maxFee
    ) PegStabilityHook(_poolManager) {
        // check for 0 value inputs
        if (
            address(_rateProvider) == address(0) || _minFee == 0 || _maxFee == 0
        ) revert InvalidZeroInput();

        // check for maxFee
        if (_maxFee > MAX_FEE_BPS) revert InvalidMaxFee();

        // check for minFee range
        if (_minFee > _maxFee || _minFee < MIN_FEE_BPS) revert InvalidMinFee();

        rateProvider = _rateProvider;
        minFeeBps = _minFee;
        maxFeeBps = _maxFee;
    }

    function _referencePriceX96(
        Currency,
        Currency
    ) internal view override returns (uint160) {
        // strongly pegged pools, the reference price is from rateProvider
        // returned in sqrtX96 format
        return
            uint160(
                (FixedPointMathLib.sqrt(1e18) * 2 ** 96) /
                    FixedPointMathLib.sqrt(rateProvider.getRate())
            );
    }

    /// @dev linearly scale the swap fee as a tenth of the percentage difference between pool price and reference price
    /// i.e. if pool price is off by 0.05% the fee is 0.05%, if the price is off by 0.50% the fee is 0.5%
    function _calculateFee(
        Currency,
        Currency,
        bool zeroForOne,
        uint160 poolSqrtPriceX96,
        uint160 referenceSqrtPriceX96
    ) internal view override returns (uint24) {
        // pool price is less than reference price (over pegged), or zeroForOne trades are moving towards the reference price
        if (zeroForOne || poolSqrtPriceX96 < referenceSqrtPriceX96)
            return minFeeBps; // minFee bip

        // computes the absolute percentage difference between the pool price and the reference price
        // i.e. 0.005e18 = 0.50% difference between pool price and reference price
        uint256 absPercentageDiffWad = SqrtPriceLibrary
            .absPercentageDifferenceWad(
                uint160(poolSqrtPriceX96),
                referenceSqrtPriceX96
            );

        // convert percentage WAD to pips, i.e. 0.05e18 = 5% = 50_000
        // the fee itself is the percentage difference
        uint24 fee = uint24(absPercentageDiffWad / 1e12);
        if (fee < minFeeBps) {
            // if % depeg is less than min fee %. charge minFee
            fee = minFeeBps;
        } else if (fee > maxFeeBps) {
            // if % depeg is more than max fee %. charge maxFee
            fee = maxFeeBps;
        }
        return fee;
    }
}
