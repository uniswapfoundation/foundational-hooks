// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    toBeforeSwapDelta,
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {CurrencySettler} from "uniswap-hooks/utils/CurrencySettler.sol";

import {DeltaResolver} from "v4-periphery/src/base/DeltaResolver.sol";

import {ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";

/// @title Generic Router for ERC4626 Token Wrappers
/// @dev Only supports symmetric ERC4626 Vaults
contract Generic4626Router is BaseHook {
    using CurrencySettler for Currency;
    using SafeCast for int256;
    using SafeCast for uint256;

    error Generic4626Router__NotAllowed();
    error Generic4626Router__InvalidPoolFee();

    struct PoolDetails {
        bool isInitialized;
        bool wrapsZeroToOne;
    }

    mapping(PoolId poolId => PoolDetails details) public poolDetails;

    constructor(
        IPoolManager _manager
    ) BaseHook(_manager) {}

    function initializePool(
        ERC4626 vault
    ) external returns (PoolKey memory poolKey, PoolId poolId) {
        ERC20 underlying = vault.asset();
        bool wrapZeroForOne = address(underlying) < address(vault);

        poolKey = PoolKey({
            currency0: wrapZeroForOne
                ? Currency.wrap(address(underlying))
                : Currency.wrap(address(vault)),
            currency1: wrapZeroForOne
                ? Currency.wrap(address(vault))
                : Currency.wrap(address(underlying)),
            fee: 0,
            tickSpacing: 1, // Irrelevant
            hooks: IHooks(address(this))
        });

        poolId = poolKey.toId();

        poolDetails[poolId] = PoolDetails({isInitialized: true, wrapsZeroToOne: wrapZeroForOne});
        underlying.approve(address(vault), type(uint256).max);

        poolManager.initialize(poolKey, 2 ** 96);
    }

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true, // Validate settings
            beforeAddLiquidity: true, // Disallow adding liquidity
            beforeSwap: true, // Handle wrapping/unwrapping
            beforeSwapReturnDelta: true, // Async Swap via the vault
            afterSwap: false,
            afterInitialize: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeDonate: false,
            afterDonate: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(
        address,
        PoolKey calldata poolKey,
        uint160
    ) internal view override returns (bytes4) {
        if (poolKey.fee != 0) {
            revert Generic4626Router__InvalidPoolFee();
        }

        PoolId poolId = poolKey.toId();
        PoolDetails memory details = poolDetails[poolId];

        if (!details.isInitialized) {
            // We enforce pool initialization via the hook, this way we can
            // ensure that the pool is initialized with the correct parameters
            revert Generic4626Router__NotAllowed();
        }

        return IHooks.beforeInitialize.selector;
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert Generic4626Router__NotAllowed();
    }

    function _beforeSwap(
        address,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = poolKey.toId();
        PoolDetails memory details = poolDetails[poolId];

        bool isExactInput = params.amountSpecified < 0;
        int128 amountUnspecified;

        (Currency vault, Currency underlying) = _getVaultUnderlying(poolKey, details.wrapsZeroToOne);

        if (params.zeroForOne == details.wrapsZeroToOne) {
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getUnderlyingForShares(
                    ERC4626(Currency.unwrap(vault)), uint256(params.amountSpecified)
                );

            underlying.take(poolManager, address(this), inputAmount, false);

            uint256 shares = _deposit(
                ERC20(Currency.unwrap(underlying)), ERC4626(Currency.unwrap(vault)), inputAmount
            );

            amountUnspecified =
                isExactInput ? -shares.toInt256().toInt128() : inputAmount.toInt256().toInt128();
        } else {
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getSharesForUnderlying(
                    ERC4626(Currency.unwrap(vault)), uint256(params.amountSpecified)
                );

            vault.take(poolManager, address(this), inputAmount, false);

            uint256 underlyingAmount = _withdraw(
                ERC20(Currency.unwrap(underlying)), ERC4626(Currency.unwrap(vault)), inputAmount
            );

            amountUnspecified = isExactInput
                ? -underlyingAmount.toInt256().toInt128()
                : inputAmount.toInt256().toInt128();
        }

        return (
            IHooks.beforeSwap.selector,
            toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified),
            0
        );
    }

    function _getVaultUnderlying(
        PoolKey calldata poolKey,
        bool wrapsZeroToOne
    ) internal pure returns (Currency vault, Currency underlying) {
        if (wrapsZeroToOne) {
            vault = poolKey.currency1;
            underlying = poolKey.currency0;
        } else {
            vault = poolKey.currency0;
            underlying = poolKey.currency1;
        }
    }

    function _deposit(
        ERC20 underlying,
        ERC4626 vault,
        uint256 underlyingAmount
    ) internal returns (uint256 shares) {
        if (underlying.allowance(address(this), address(vault)) < underlyingAmount) {
            underlying.approve(address(vault), type(uint256).max);
        }

        poolManager.sync(Currency.wrap(address(vault)));
        shares = vault.deposit(underlyingAmount, address(poolManager));
        poolManager.settle();
    }

    function _withdraw(
        ERC20 underlying,
        ERC4626 vault,
        uint256 shares
    ) internal returns (uint256 underlyingAmount) {
        poolManager.sync(Currency.wrap(address(underlying)));
        underlyingAmount = vault.redeem(shares, address(poolManager), address(this));
        poolManager.settle();
    }

    function _getUnderlyingForShares(
        ERC4626 vault,
        uint256 shares
    ) internal view returns (uint256) {
        return vault.convertToAssets(shares);
    }

    function _getSharesForUnderlying(
        ERC4626 vault,
        uint256 underlyingAmount
    ) internal view returns (uint256) {
        return vault.convertToShares(underlyingAmount);
    }
}
