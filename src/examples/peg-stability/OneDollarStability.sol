// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PegStabilityHook} from "../../PegStabilityHook.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

contract OneDollarStability is PegStabilityHook {
    constructor(IPoolManager _poolManager) PegStabilityHook(_poolManager) {}

    function _referencePriceX96(Currency, Currency) internal pure override returns (uint160) {
        // for one-dollar pegged pools, the reference price is 1.0
        // return in sqrtX96 format
        return uint160(FixedPointMathLib.sqrt(1)) * 2 ** 96;
    }

    /// @dev linearly scale the swap fee based on the distance between pool price and reference price
    /// i.e. if pool price is off by 0.05% the fee is 0.005%, if the price is off by 0.50% the fee is 0.05%
    function _calculateFee(Currency, Currency, bool, uint160 poolSqrtPriceX96, uint160 referenceSqrtPriceX96)
        internal
        pure
        override
        returns (uint24)
    {
        /*
        obtain the percentage difference in price as WAD
        i.e. we want to extract `(A - B) / A` from sqrt((A - B) / A) * Q96
        -> (sqrt((A - B) / A) * Q96)**2
        -> ((A - B) * Q192) / A
        -> ((A - B) * 1e18) * Q192 / (A * Q192)
        
        to obtain: sqrt((A - B) / A) * Q96
        -> (sqrt(A - B) / sqrt(A)) * Q96
        -> (sqrt(A - B) * Q96) / sqrt(A)
        -> ((sqrt(A) - sqrt(B)) * Q96)) / sqrt(A)
        -> (sqrt(A)*Q96 - sqrt(B)*Q96) / sqrt(A)
        -> (sqrt(A)*Q96 - sqrt(B)*Q96) * Q96 / (sqrt(A)*Q96)
        */
        // sqrt(A)*Q96 - sqrt(B)*Q96
        uint160 diffX96 = poolSqrtPriceX96 < referenceSqrtPriceX96
            ? (referenceSqrtPriceX96 - poolSqrtPriceX96)
            : poolSqrtPriceX96 - referenceSqrtPriceX96;

        // (sqrt(A)*Q96 - sqrt(B)*Q96) * Q96 / (sqrt(A)*Q96)
        uint256 percentageDiffX96 = uint256(diffX96 * 2 ** 96) / uint256(referenceSqrtPriceX96);

        // convert to WAD, 0.05e18 = 5%
        uint256 percentageDiffWad = (percentageDiffX96 ** 2) * 1e18 / 2 ** 192;

        // convert percentage WAD to pips, i.e. 0.05e18 = 5% = 50_000

        uint24 fee = uint24(percentageDiffWad / 1e12);

        return fee;
    }
}
