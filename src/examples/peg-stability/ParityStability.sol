// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PegStabilityHook} from "../../PegStabilityHook.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SqrtPriceLibrary} from "../../libraries/SqrtPriceLibrary.sol";

/// @title Parity Stability
/// @notice A peg stability hook, for pairs that trade at a 1:1 ratio
/// The hook charges 0.1 bip for trades moving towards the peg
/// otherwise it charges a linearly-scaled fee based on the distance from the peg
/// i.e. if the pool price is off by 0.05% the fee is 0.005%, if the price is off by 0.50% the fee is 0.05%
contract ParityStability is PegStabilityHook {
    constructor(IPoolManager _poolManager) PegStabilityHook(_poolManager) {}

    function _referencePriceX96(Currency, Currency) internal pure override returns (uint160) {
        // strongly pegged pools, the reference price is 1.0
        // returned in sqrtX96 format
        return uint160(FixedPointMathLib.sqrt(1)) * 2 ** 96;
    }

    /// @dev linearly scale the swap fee as a tenth of the percentage difference between pool price and reference price
    /// i.e. if pool price is off by 0.05% the fee is 0.005%, if the price is off by 0.50% the fee is 0.05%
    function _calculateFee(Currency, Currency, bool zeroForOne, uint160 poolSqrtPriceX96, uint160 referenceSqrtPriceX96)
        internal
        pure
        override
        returns (uint24)
    {
        // pool price is above reference price, and zeroForOne trades are moving towards the reference price
        if (zeroForOne && poolSqrtPriceX96 > referenceSqrtPriceX96) return 10; // 0.1 bip
        if (!zeroForOne && poolSqrtPriceX96 < referenceSqrtPriceX96) return 10; // 0.1 bip

        // computes the absolute percentage difference between the pool price and the reference price
        // i.e. 0.005e18 = 0.50% difference between pool price and reference price
        uint256 absPercentageDiffWad =
            SqrtPriceLibrary.absPercentageDifferenceWad(uint160(poolSqrtPriceX96), referenceSqrtPriceX96);

        // convert percentage WAD to pips, i.e. 0.05e18 = 5% = 50_000
        // the fee itself is a tenth of the percentage difference
        uint24 fee = uint24(absPercentageDiffWad / 1e12) / 10;
        return fee;
    }
}
