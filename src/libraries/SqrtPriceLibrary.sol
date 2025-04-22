// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

library SqrtPriceLibrary {
    uint160 internal constant Q96 = 2 ** 96;
    uint256 internal constant Q192 = 2 ** 192;

    /// @notice Given an exchange rate against ETH, return the sqrtPriceX96
    /// @dev The exchange rate is in WAD format, e.g. 1e18 tokens exchange for 1.04e18 ETH
    /// @param exchangeRateWad The exchange rate in WAD format
    /// @return sqrtPriceX96 The sqrt price in sqrtX96 format
    function exchangeRateToSqrtPriceX96(uint256 exchangeRateWad) internal pure returns (uint160 sqrtPriceX96) {
        return fractionToSqrtPriceX96(1e18, exchangeRateWad);
    }

    /// @notice returns sqrt(numerator / denominator) * Q96
    function fractionToSqrtPriceX96(uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint160 sqrtPriceX96)
    {
        // sqrtPriceX96 = sqrt(numerator / denominator) * Q96)
        // sqrtPriceX96 = sqrt(numerator) * 2^96 / sqrt(denominator)
        return uint160(FixedPointMathLib.sqrt(numerator) * Q96 / FixedPointMathLib.sqrt(denominator));
    }

    /// @notice Calculates the absolute difference between two sqrt prices
    function absDifferenceX96(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96) internal pure returns (uint160) {
        return sqrtPriceAX96 < sqrtPriceBX96 ? (sqrtPriceBX96 - sqrtPriceAX96) : (sqrtPriceAX96 - sqrtPriceBX96);
    }

    /// @notice Divides two sqrtPriceX96 values, retaining sqrtX96 precision
    /// @param numeratorX96 The numerator, in sqrtX96 format
    /// @param denominatorX96 The denominator in sqrtX96 format
    /// @return The result of the division, in sqrtX96 format
    function divX96(uint160 numeratorX96, uint160 denominatorX96) internal pure returns (uint256) {
        return (uint256(numeratorX96) * uint256(Q96)) / uint256(denominatorX96);
    }

    /// @notice Calculates the absolute percentage difference between two sqrt prices in WAD units
    /// @dev 0.05e18 = 5%, for 95 vs 100 or 105 vs 100
    /// @param sqrtPriceX96 The first sqrt price
    /// @param denominatorX96 The denominator for the percentage difference
    /// @return The percentage difference in WAD units
    function absPercentageDifferenceWad(uint160 sqrtPriceX96, uint160 denominatorX96) internal pure returns (uint256) {
        uint256 _divX96 = divX96(sqrtPriceX96, denominatorX96);

        // convert to WAD
        uint256 _percentageDiffWad = ((_divX96 ** 2) * 1e18) / Q192;
        return (1e18 < _percentageDiffWad) ? _percentageDiffWad - 1e18 : 1e18 - _percentageDiffWad;
    }
}
