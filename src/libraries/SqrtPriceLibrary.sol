// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SqrtPriceLibrary {
    uint160 internal constant Q96 = 2 ** 96;
    uint256 internal constant Q192 = 2 ** 192;

    /// @notice Calculates the absolute difference between two sqrt prices
    function absDifferenceX96(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96) internal pure returns (uint160) {
        return sqrtPriceAX96 < sqrtPriceBX96 ? (sqrtPriceBX96 - sqrtPriceAX96) : (sqrtPriceAX96 - sqrtPriceBX96);
    }

    /// @notice Calculates the percentage difference between two sqrt prices
    /// @dev i.e. sqrtPriceA - sqrtPriceB / sqrtPriceA
    /// @param sqrtPriceX96 The first sqrt price
    /// @param denominatorX96 The denominator for the percentage difference
    function percentageDifferenceX96(uint160 sqrtPriceX96, uint160 denominatorX96) internal pure returns (uint256) {
        // sqrt(A)*Q96 - sqrt(B)*Q96
        uint160 diffX96 = absDifferenceX96(sqrtPriceX96, denominatorX96);

        // (sqrt(A)*Q96 - sqrt(B)*Q96) * Q96 / (sqrt(A)*Q96)
        return (uint256(diffX96) * Q96) / uint256(denominatorX96);
    }

    /// @notice Calculates the percentage difference between two sqrt prices in WAD units
    /// @dev 0.05e18 = 5%
    /// @param sqrtPriceX96 The first sqrt price
    /// @param denominatorX96 The denominator for the percentage difference
    /// @return The percentage difference in WAD units
    function percentageDifferenceWad(uint160 sqrtPriceX96, uint160 denominatorX96) internal pure returns (uint256) {
        // (sqrt(A)*Q96 - sqrt(B)*Q96) * Q96 / (sqrt(A)*Q96)
        uint256 _percentageDiffX96 = percentageDifferenceX96(sqrtPriceX96, denominatorX96);

        // convert to WAD
        return (_percentageDiffX96 ** 2) * 1e18 / Q192;
    }
}
