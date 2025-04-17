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
            result, sqrtPriceAX96 < sqrtPriceBX96 ? (sqrtPriceBX96 - sqrtPriceAX96) : (sqrtPriceAX96 - sqrtPriceBX96)
        );
    }

    function test_percentageDifferenceWad_1() public pure {
        uint256 numeratorX96 = FixedPointMathLib.sqrt(107e18) * SqrtPriceLibrary.Q96;
        uint256 denominatorX96 = FixedPointMathLib.sqrt(100e18) * SqrtPriceLibrary.Q96;
        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(uint160(numeratorX96), uint160(denominatorX96));
        assertApproxEqRel(result, 0.07e18, 0.00001e18);
    }

    function test_percentageDifferenceWad_2() public pure {
        uint256 numeratorX96 = FixedPointMathLib.sqrt(93e18) * SqrtPriceLibrary.Q96;
        uint256 denominatorX96 = FixedPointMathLib.sqrt(100e18) * SqrtPriceLibrary.Q96;
        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(uint160(numeratorX96), uint160(denominatorX96));
        assertApproxEqRel(result, 0.07e18, 0.00001e18);
    }

    function test_fuzz_percentageDifferenceWad(uint160 sqrtPriceX96, uint256 targetWad) public pure {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        // multiplier to determine the newSqrtPriceX96
        targetWad = bound(targetWad, 0.00001e18, 3e18);
        uint160 newSqrtPriceX96 =
            uint160((uint256(sqrtPriceX96) * FixedPointMathLib.sqrt(targetWad)) / FixedPointMathLib.sqrt(1e18));
        vm.assume(newSqrtPriceX96 < TickMath.MAX_SQRT_PRICE);
        vm.assume(newSqrtPriceX96 > TickMath.MIN_SQRT_PRICE);

        uint256 result = SqrtPriceLibrary.absPercentageDifferenceWad(newSqrtPriceX96, sqrtPriceX96);
        if (targetWad > 1e18) {
            targetWad = targetWad - 1e18;
        } else {
            targetWad = 1e18 - targetWad;
        }
        assertApproxEqRel(result, targetWad, 0.000001e18);
    }
}
