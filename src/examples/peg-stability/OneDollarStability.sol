// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PegStabilityHook} from "../../PegStabilityHook.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {SqrtPriceLibrary} from "../../libraries/SqrtPriceLibrary.sol";

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
        uint256 absPercentageDiffWad =
            SqrtPriceLibrary.absPercentageDifferenceWad(uint160(poolSqrtPriceX96), referenceSqrtPriceX96);

        // convert percentage WAD to pips, i.e. 0.05e18 = 5% = 50_000
        // where the fee itself is a tenth of the percentage difference
        uint24 fee = uint24(absPercentageDiffWad / 1e12) / 10;
        return fee;
    }
}
