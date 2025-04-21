// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {ParityStability} from "../../src/examples/peg-stability/ParityStability.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";

contract ParityStabilityTest is Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    ParityStability hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public virtual {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("ParityStability.sol:ParityStability", constructorArgs, flags);
        hook = ParityStability(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint256 liquidityAmount = 10_000e18;
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(liquidityAmount),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_fuzz_swap(bool zeroForOne, bool exactIn) public {
        int256 amountSpecified = exactIn ? -int256(1e18) : int256(1e18);
        BalanceDelta result = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        if (zeroForOne) {
            exactIn
                ? assertEq(int256(result.amount0()), amountSpecified)
                : assertLt(int256(result.amount0()), amountSpecified);
            exactIn ? assertGt(int256(result.amount1()), 0) : assertEq(int256(result.amount1()), amountSpecified);
        } else {
            exactIn
                ? assertEq(int256(result.amount1()), amountSpecified)
                : assertLt(int256(result.amount1()), amountSpecified);
            exactIn ? assertGt(int256(result.amount0()), 0) : assertEq(int256(result.amount0()), amountSpecified);
        }
    }

    /// @dev swaps moving away from peg are charged a high fee
    function test_fuzz_high_fee(bool zeroForOne) public {
        BalanceDelta ref = swap(key, zeroForOne, -int256(0.1e18), ZERO_BYTES);

        // move the pool price to off peg
        swap(key, zeroForOne, -int256(1000e18), ZERO_BYTES);

        // TODO: extract the swapFee from event and assert its greater

        // move the pool price away from peg
        BalanceDelta highFeeSwap = swap(key, zeroForOne, -int256(0.1e18), ZERO_BYTES);

        // output of the second swap is much less
        // highFeeSwap + offset < ref
        zeroForOne
            ? assertLt(highFeeSwap.amount1() + int128(0.001e18), ref.amount1())
            : assertLt(highFeeSwap.amount0() + int128(0.001e18), ref.amount0());
    }

    /// @dev swaps moving towards peg are charged a low fee
    function test_fuzz_low_fee(bool zeroForOne) public {
        // move the pool price to off peg
        swap(key, !zeroForOne, -int256(1000e18), ZERO_BYTES);

        // move the pool price away from peg
        BalanceDelta highFeeSwap = swap(key, !zeroForOne, -int256(0.1e18), ZERO_BYTES);

        // swap towards the peg
        BalanceDelta lowFeeSwap = swap(key, zeroForOne, -int256(0.1e18), ZERO_BYTES);

        // output of the second swap is much higher
        // lowFeeSwap > highFeeSwap
        zeroForOne
            ? assertGt(lowFeeSwap.amount1(), highFeeSwap.amount1())
            : assertGt(lowFeeSwap.amount0(), highFeeSwap.amount0());
    }
}
