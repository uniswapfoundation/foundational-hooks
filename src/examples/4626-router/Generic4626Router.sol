// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {DeltaResolver} from "v4-periphery/src/base/DeltaResolver.sol";

import {ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";

/// @title Generic Router for ERC4626 Token Wrappers
/// @dev Only supports symmetric ERC4626 Vaults
contract Generic4626Router is BaseHook, DeltaResolver {
    using SafeCast for int256;
    using SafeCast for uint256;

    error Generic4626Router__NotAllowed();
    error Generic4626Router__InvalidPoolFee();

    struct PoolDetails {
        bool isInitialized;
        bool wrapDirection; // true if zeroToOne, false if oneToZero
        ERC4626 vault;
        ERC20 underlying;
    }

    mapping(PoolId poolId => PoolDetails details) public poolDetails;

    constructor(IPoolManager _manager) BaseHook(_manager) {}

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

        poolDetails[poolId] = PoolDetails({
            isInitialized: true,
            wrapDirection: wrapZeroForOne,
            vault: vault,
            underlying: underlying
        });

        // TODO: I wonder if pool price is truly irrelevant here
        poolManager.initialize(poolKey, 2 ** 96);
    }

    /// @inheritdoc BaseHook
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
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

    function beforeInitialize(
        address,
        PoolKey calldata poolKey,
        uint160
    ) external view override returns (bytes4) {
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

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert Generic4626Router__NotAllowed();
    }

    function beforeSwap(
        address,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    )
        external
        override
        returns (
            bytes4 selector,
            BeforeSwapDelta swapDelta,
            uint24 lpFeeOverride
        )
    {
        PoolId poolId = poolKey.toId();
        PoolDetails memory details = poolDetails[poolId];

        bool isExactInput = params.amountSpecified < 0;

        // This following section is hard to follow, I initially wrote this with currency0 and currency1
        // but it was truly impossible to follow. Ended up storing the vault and underlying.
        // Although, I think I got a hang of it so might go back
        if (params.zeroForOne == details.wrapDirection) {
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getUnderlyingForShares(
                    details.vault,
                    uint256(params.amountSpecified)
                );

            _take(
                Currency.wrap(address(details.underlying)),
                address(this),
                inputAmount
            );

            uint256 shares = _deposit(
                details.underlying,
                details.vault,
                inputAmount
            );

            _settle(
                Currency.wrap(address(details.vault)),
                address(this),
                shares
            );

            int128 amountUnspecified = isExactInput
                ? -shares.toInt256().toInt128()
                : inputAmount.toInt256().toInt128();

            swapDelta = toBeforeSwapDelta(
                -params.amountSpecified.toInt128(),
                amountUnspecified
            );
        } else {
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getSharesForUnderlying(
                    details.vault,
                    uint256(params.amountSpecified)
                );

            _take(
                Currency.wrap(address(details.vault)),
                address(this),
                inputAmount
            );

            uint256 underlyingAmount = _withdraw(details.vault, inputAmount);

            _settle(
                Currency.wrap(address(details.underlying)),
                address(this),
                underlyingAmount
            );

            int128 amountUnspecified = isExactInput
                ? -underlyingAmount.toInt256().toInt128()
                : inputAmount.toInt256().toInt128();

            swapDelta = toBeforeSwapDelta(
                -params.amountSpecified.toInt128(),
                amountUnspecified
            );
        }

        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    function _pay(Currency token, address, uint256 amount) internal override {
        token.transfer(address(poolManager), amount);
    }

    function _deposit(
        ERC20 underlying,
        ERC4626 vault,
        uint256 underlyingAmount
    ) internal returns (uint256 shares) {
        // TODO: Is it worth protecting from lingering approvals, or just approve max in initializer?
        underlying.approve(address(vault), underlyingAmount);

        return vault.deposit(underlyingAmount, address(this));
    }

    function _withdraw(
        ERC4626 vault,
        uint256 shares
    ) internal returns (uint256 underlyingAmount) {
        return vault.redeem(shares, address(this), address(this));
    }

    function _getUnderlyingForShares(
        ERC4626 vault,
        uint256 shares
    ) internal view returns (uint256 underlyingAmount) {
        return vault.convertToAssets(shares);
    }

    function _getSharesForUnderlying(
        ERC4626 vault,
        uint256 underlyingAmount
    ) internal view returns (uint256 shares) {
        return vault.convertToShares(underlyingAmount);
    }
}
