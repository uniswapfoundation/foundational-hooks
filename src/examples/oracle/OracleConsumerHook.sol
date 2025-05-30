// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {BaseOracleProvider} from "./BaseOracleProvider.sol";

contract OracleConsumerHook is BaseOracleProvider {
    // Truncated Oracle uses 9116 ticks per block. Can be customized.
    // 9116 ticks = ~2.5x price change per block.
    // See https://blog.uniswap.org/uniswap-v3-oracles
    constructor(
        IPoolManager _manager
    ) BaseOracleProvider(_manager, 9116) {}

    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) internal virtual override returns (bytes4) {
        _initializeOracle(key, tick);

        return this.afterInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        _updateOracle(key);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function increaseObservationCardinalityNext(
        PoolKey calldata key,
        uint16 observationCardinalityNext
    ) external {
        // No-op if already equal or higher
        _increaseObservationCardinality(key, observationCardinalityNext);
    }
}
