// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {SqrtPriceLibrary} from "../../src/libraries/SqrtPriceLibrary.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

contract SqrtPriceLibraryTest is Test {
    function setUp() public {}

    function test_fuzz_absDifferenceX96(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96) public pure {
        uint160 result = SqrtPriceLibrary.absDifferenceX96(sqrtPriceAX96, sqrtPriceBX96);
        assertEq(
            result,
            sqrtPriceAX96 < sqrtPriceBX96
                ? (sqrtPriceBX96 - sqrtPriceAX96)
                : (sqrtPriceAX96 - sqrtPriceBX96)
        );
    }

    function test_percentageDifferenceWad_1() public pure {
        uint256 numeratorX96 = FixedPointMathLib.sqrt(107e18) * SqrtPriceLibrary.Q96;
        uint256 denominatorX96 = FixedPointMathLib.sqrt(100e18) * SqrtPriceLibrary.Q96;
        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(
            uint160(numeratorX96), uint160(denominatorX96)
        );
        assertApproxEqRel(result, 0.07e18, 0.00001e18);
    }

    function test_percentageDifferenceWad_2() public pure {
        uint256 numeratorX96 = FixedPointMathLib.sqrt(93e18) * SqrtPriceLibrary.Q96;
        uint256 denominatorX96 = FixedPointMathLib.sqrt(100e18) * SqrtPriceLibrary.Q96;
        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(
            uint160(numeratorX96), uint160(denominatorX96)
        );
        assertApproxEqRel(result, 0.07e18, 0.00001e18);
    }

    function test_percentageDifferenceWadEq() public pure {
        uint160 sqrtPriceX96 = uint160(2 ** 96);
        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(sqrtPriceX96, sqrtPriceX96);
        assertEq(result, 0);
    }

    function test_fuzz_percentageDifferenceWad(uint256 price, uint256 targetWad) public pure {
        price = bound(price, 0.00001e18, 100_000_000e18);
        uint160 sqrtPriceX96 = uint160(
            FixedPointMathLib.sqrt(price) * SqrtPriceLibrary.Q96 / FixedPointMathLib.sqrt(1e18)
        );

        // multiplier to determine the newSqrtPriceX96
        targetWad = bound(targetWad, 0.00001e18, 5e18);
        uint160 newSqrtPriceX96 = uint160(
            (uint256(sqrtPriceX96) * FixedPointMathLib.sqrt(targetWad))
                / FixedPointMathLib.sqrt(1e18)
        );
        vm.assume(newSqrtPriceX96 < TickMath.MAX_SQRT_PRICE);
        vm.assume(newSqrtPriceX96 > TickMath.MIN_SQRT_PRICE);

        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(newSqrtPriceX96, sqrtPriceX96);
        if (targetWad > 1e18) {
            targetWad = targetWad - 1e18;
        } else {
            targetWad = 1e18 - targetWad;
        }
        if (targetWad > 0.00001e18) assertApproxEqRel(result, targetWad, 0.000001e18);
    }

    function test_exchangeRateToSqrtPriceX96() public pure {
        uint256 exchangeRateWad = 1e18;
        uint160 sqrtPriceX96 = SqrtPriceLibrary.exchangeRateToSqrtPriceX96(exchangeRateWad);
        assertEq(sqrtPriceX96, SqrtPriceLibrary.Q96);

        exchangeRateWad = 1.04e18;
        sqrtPriceX96 = SqrtPriceLibrary.exchangeRateToSqrtPriceX96(exchangeRateWad);
        // 10 bips of error
        assertApproxEqAbs(
            sqrtPriceX96,
            77689605131987355976724378426,
            SqrtPriceLibrary.fractionToSqrtPriceX96(0.001e18, 1e18),
            "1.04"
        );

        exchangeRateWad = 1.04444444444444e18;
        sqrtPriceX96 = SqrtPriceLibrary.exchangeRateToSqrtPriceX96(exchangeRateWad);
        // 10 bips of error
        assertApproxEqAbs(
            sqrtPriceX96,
            77524131876742691217855037000,
            SqrtPriceLibrary.fractionToSqrtPriceX96(0.001e18, 1e18),
            "1.04444444444444"
        );

        exchangeRateWad = 1.05555555555555e18;
        sqrtPriceX96 = SqrtPriceLibrary.exchangeRateToSqrtPriceX96(exchangeRateWad);
        // 10 bips of error
        assertApproxEqAbs(
            sqrtPriceX96,
            77115030699858018365419924960,
            SqrtPriceLibrary.fractionToSqrtPriceX96(0.001e18, 1e18),
            "1.05555555555555"
        );

        exchangeRateWad = 2.129803478192837e18;
        sqrtPriceX96 = SqrtPriceLibrary.exchangeRateToSqrtPriceX96(exchangeRateWad);
        // 10 bips of error
        assertApproxEqAbs(
            sqrtPriceX96,
            54288746954863770371846037548,
            SqrtPriceLibrary.fractionToSqrtPriceX96(0.001e18, 1e18),
            "2.129803478192837"
        );
    }

    function test_fuzz_fractionToSqrtPriceX96(uint256 numerator, uint256 denominator) public pure {
        numerator = bound(numerator, 1e18, 10_000_000e18);
        denominator = bound(denominator, 1e18, 10_000_000e18);
        SqrtPriceLibrary.fractionToSqrtPriceX96(numerator, denominator);
    }

    function test_fuzz_exchangeRateToSqrtPriceX96(
        uint256 exchangeRateWad
    ) public pure {
        exchangeRateWad = bound(exchangeRateWad, 1e18, 10_000_000e18);
        SqrtPriceLibrary.exchangeRateToSqrtPriceX96(exchangeRateWad);
    }
}
