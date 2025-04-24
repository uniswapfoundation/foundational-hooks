// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Constants} from "./sepolia/Constants.sol";
import {Config} from "./sepolia/Config.sol";

contract SwapScript is Script, Constants, Config {
    // slippage tolerance to allow for unlimited price impact
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    /////////////////////////////////////
    // --- Parameters to Configure --- //
    /////////////////////////////////////

    // PoolSwapTest Contract address, sepolia
    PoolSwapTest swapRouter =
        PoolSwapTest(0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe);

    // --- pool configuration --- //
    // fees paid by swappers that accrue to liquidity providers
    uint24 lpFee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
    int24 tickSpacing = 60;

    address caller = 0xAd0f3f4BEC42CdA68d2cd31301B3C3De3B0F50E2;

    function run() external {
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        // approve tokens to the swap router
        if (!currency0.isAddressZero()) {
            vm.broadcast();
            token0.approve(address(swapRouter), type(uint256).max);
        }
        if (
            !currency1.isAddressZero() &&
            token1.allowance(caller, address(swapRouter)) < type(uint256).max
        ) {
            vm.broadcast();
            token1.approve(address(swapRouter), type(uint256).max);
        }

        // ------------------------------ //
        // Swap 100e18 token0 into token1 //
        // ------------------------------ //
        bool zeroForOne = true;
        int256 amount = 0.01e18;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: zeroForOne ? -amount : amount,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT // unlimited impact
        });

        // in v4, users have the option to receieve native ERC20s or wrapped ERC1155 tokens
        // here, we'll take the ERC20s
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        bytes memory hookData = new bytes(0);
        vm.broadcast();
        zeroForOne
            ? swapRouter.swap{value: uint256(amount)}(
                pool,
                params,
                testSettings,
                hookData
            )
            : swapRouter.swap(pool, params, testSettings, hookData);
    }
}
