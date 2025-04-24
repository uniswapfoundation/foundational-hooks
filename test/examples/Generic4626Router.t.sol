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
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {SwapFeeEventAsserter} from "../utils/SwapFeeEventAsserter.sol";
import {MinimalRouter} from "../utils/MinimalRouter.sol";

import {Generic4626Router} from "../../src/examples/4626-router/Generic4626Router.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/src/test/utils/mocks/MockERC4626.sol";

contract Generic4626RouterTest is Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SwapFeeEventAsserter for Vm.Log[];

    MinimalRouter minimalRouter;

    Generic4626Router hook;

    MockERC4626 public vault;
    MockERC20 public asset;

    uint256 tokenId;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public virtual {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);

        deployCodeTo("Generic4626Router.sol:Generic4626Router", constructorArgs, flags);
        hook = Generic4626Router(flags);

        // Deploy mock asset and vault
        asset = new MockERC20("Asset Token", "ASSET", 18);
        vault = new MockERC4626(asset, "Vault Token", "VAULT");

        (key,) = hook.initializePool(vault);

        minimalRouter = new MinimalRouter(manager);

        asset.mint(alice, 1000 ether);
        asset.mint(bob, 1000 ether);

        asset.mint(address(this), 2000 ether);
        asset.approve(address(vault), 2000 ether);
        vault.deposit(1000 ether, alice);
        vault.deposit(1000 ether, bob);
    }

    function test_wrapping_exactInput() public {
        uint256 wrapAmount = 1 ether;
        uint256 expectedOutput = vault.convertToShares(wrapAmount);

        vm.startPrank(alice);
        asset.approve(address(minimalRouter), type(uint256).max);

        uint256 aliceAssetBefore = asset.balanceOf(alice);
        uint256 aliceVaultBefore = vault.balanceOf(alice);
        uint256 managerAssetBefore = asset.balanceOf(address(manager));
        uint256 managerVaultBefore = vault.balanceOf(address(manager));

        minimalRouter.swap(key, true, wrapAmount, 0, "");

        vm.stopPrank();

        assertEq(aliceAssetBefore - asset.balanceOf(alice), wrapAmount);
        assertEq(vault.balanceOf(alice) - aliceVaultBefore, expectedOutput);
        assertEq(managerAssetBefore, asset.balanceOf(address(manager)));
        assertEq(managerVaultBefore, vault.balanceOf(address(manager)));
    }
}
