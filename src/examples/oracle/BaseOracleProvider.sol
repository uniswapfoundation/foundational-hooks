// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import {OracleLibrary} from "./OracleLibrary.sol";

abstract contract BaseOracleProvider is BaseHook {
    using OracleLibrary for OracleLibrary.Observation[65535];
    using StateLibrary for IPoolManager;

    error OracleProvider__InvalidSetup();

    /// @notice Contains information about the current number of observations stored.
    /// @param observationIndex The most-recently updated index of the observations buffer
    /// @param observationCardinality The current maximum number of observations that are being stored
    /// @param observationCardinalityNext The next maximum number of observations that can be stored
    struct ObservationState {
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
    }

    /// @notice The list of observations for a given pool ID
    mapping(PoolId => OracleLibrary.Observation[65535]) private observationsById;

    /// @notice The current observation array state for the given pool ID
    mapping(PoolId => ObservationState) private stateById;

    /// @notice The maximum absolute tick delta that can be observed for the truncated oracle.
    int24 public immutable MAX_ABS_TICK_DELTA;

    constructor(IPoolManager _manager, int24 _maxAbsTickDelta) BaseHook(_manager) {
        _validatePermissions();

        MAX_ABS_TICK_DELTA = _maxAbsTickDelta;
    }

    function _validatePermissions() internal view {
        Hooks.Permissions memory permissions = this.getHookPermissions();

        if (!permissions.afterInitialize || !permissions.beforeSwap) {
            revert OracleProvider__InvalidSetup();
        }
    }

    function _initializeOracle(PoolKey calldata key, int24 tick) internal {
        PoolId poolId = key.toId();

        (uint16 cardinality, uint16 cardinalityNext) =
            observationsById[poolId].initialize(uint32(block.timestamp), tick);

        stateById[poolId] = ObservationState({
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext
        });
    }

    function _updateOracle(
        PoolKey calldata key
    ) internal {
        PoolId poolId = key.toId();

        ObservationState memory _observationState = stateById[poolId];

        (, int24 tick,,) = poolManager.getSlot0(poolId);

        (_observationState.observationIndex, _observationState.observationCardinality) =
        observationsById[poolId].write(
            _observationState.observationIndex,
            uint32(block.timestamp),
            tick,
            _observationState.observationCardinality,
            _observationState.observationCardinalityNext,
            MAX_ABS_TICK_DELTA
        );

        stateById[poolId] = _observationState;
    }

    function _increaseObservationCardinality(
        PoolKey calldata key,
        uint16 observationCardinalityNext
    ) internal {
        PoolId poolId = key.toId();

        uint16 observationCardinalityNextNew = observationsById[poolId].grow(
            stateById[poolId].observationCardinalityNext, observationCardinalityNext
        );

        stateById[poolId].observationCardinalityNext = observationCardinalityNextNew;
    }

    /// @notice Returns the cumulative tick as of each timestamp `secondsAgo` from the current block timestamp on `underlyingPoolId`.
    /// @dev Note that the second return value, seconds per liquidity, is not implemented in this oracle hook and will always return 0 -- it has been retained for interface compatibility.
    /// @dev To get a time weighted average tick, you must call this with two values, one representing
    /// the beginning of the period and another for the end of the period. E.g., to get the last hour time-weighted average tick,
    /// you must call it with secondsAgos = [3600, 0].
    /// @dev The time weighted average tick represents the geometric time weighted average price of the pool, in
    /// log base sqrt(1.0001) of currency1 / currency0. The TickMath library can be used to go from a tick value to a ratio.
    /// @param secondsAgos From how long ago each cumulative tick and liquidity value should be returned
    /// @param underlyingPoolId The pool ID of the underlying V4 pool
    /// @return Cumulative tick values as of each `secondsAgos` from the current block timestamp
    /// @return Truncated cumulative tick values as of each `secondsAgos` from the current block timestamp
    function observe(
        uint32[] calldata secondsAgos,
        PoolId underlyingPoolId
    ) external view returns (int56[] memory, int56[] memory) {
        ObservationState memory _observationState = stateById[underlyingPoolId];

        (, int24 tick,,) = poolManager.getSlot0(underlyingPoolId);

        return observationsById[underlyingPoolId].observe(
            uint32(block.timestamp),
            secondsAgos,
            tick,
            _observationState.observationIndex,
            _observationState.observationCardinality,
            MAX_ABS_TICK_DELTA
        );
    }
}
