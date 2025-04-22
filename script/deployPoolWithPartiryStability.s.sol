// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {ParityStability} from "../src/examples/peg-stability/ParityStability.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {IRateProvider} from "../src/interfaces/IRateProvider.sol";

/// @notice Mines the address and deploys the ParityStability.sol Hook contract
contract ParityStabilityScript is Script {
    // TODO: configure
    address POOLMANAGER = address(0);
    IRateProvider rateProvider = IRateProvider(address(0));
    uint24 minFee = 100;
    uint24 maxFee = 10_000;

    // Pool configs
    // TODO: configure 0 zero values
    Currency currency0 = Currency.wrap(address(0)); // for ETH
    Currency currency1 = Currency.wrap(address(0)); // configure ezETH
    uint24 lpFee = 0;
    int24 tickSpacing;
    uint160 startingPrice; // starting price in sqrtPriceX96

    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(ParityStability).creationCode,
            constructorArgs
        );

        // Deploy the hook using CREATE2
        vm.broadcast();
        ParityStability parityStability = new ParityStability{salt: salt}(
            IPoolManager(POOLMANAGER),
            rateProvider,
            minFee,
            maxFee
        );
        require(
            address(parityStability) == hookAddress,
            "ParityStabilityScript: hook address mismatch"
        );

        //  deploy pool
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(parityStability))
        });

        IPoolManager(POOLMANAGER).initialize(pool, startingPrice);
    }
}
