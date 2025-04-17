// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseOverrideFee} from "uniswap-hooks/fee/BaseOverrideFee.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

abstract contract PegStabilityHook is BaseOverrideFee {
    using StateLibrary for IPoolManager;

    constructor(IPoolManager _poolManager) BaseOverrideFee(_poolManager) {}

    /// @dev return a reference price in sqrtX96 format, sqrt(currency1 / currency0) * 2**96
    function _referencePriceX96(Currency currency0, Currency currency1) internal virtual returns (uint160);

    /// @dev return a swap fee given currencies, direction, pool price, and reference price
    /// @return fee in pips, i.e. 3000 = 0.3%
    function _calculateFee(
        Currency currency0,
        Currency currency1,
        bool zeroForOne,
        uint160 poolSqrtPriceX96,
        uint160 referenceSqrtPriceX96
    ) internal virtual returns (uint24);

    function _getFee(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        virtual
        override
        returns (uint24)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        return _calculateFee(
            key.currency0,
            key.currency1,
            params.zeroForOne,
            sqrtPriceX96,
            _referencePriceX96(key.currency0, key.currency1)
        );
    }
}
