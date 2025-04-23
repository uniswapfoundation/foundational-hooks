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
import {SqrtPriceLibrary} from "../src/libraries/SqrtPriceLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {IRateProvider} from "../src/interfaces/IRateProvider.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

/// @notice Mines the address and deploys the ParityStability.sol Hook contract
contract ParityStabilityScript is Script {
    // TODO: configure
    // sepolia configurations
    address POOLMANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    IRateProvider rateProvider =
        IRateProvider(0x44Ad1be5B5912a497dAa147B7A3c55DC6067BFcF);
    uint24 minFee = 100;
    uint24 maxFee = 10_000;

    // Pool configs
    // TODO: configure 0 zero values
    Currency currency0 = Currency.wrap(address(0)); // for ETH
    Currency currency1 =
        Currency.wrap(0x8d7F20137041334FBd7c87796f03b1999770Cc5f); // configure ezETH
    int24 tickSpacing = 60;
    uint160 startingPrice; // starting price in sqrtPriceX96

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            POOLMANAGER,
            rateProvider,
            minFee,
            maxFee
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_FACTORY,
            flags,
            type(ParityStability).creationCode,
            constructorArgs
        );

        startingPrice = SqrtPriceLibrary.exchangeRateToSqrtPriceX96(
            rateProvider.getRate()
        );
        // Deploy the hook using CREATE2
        vm.startBroadcast();
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
        vm.stopBroadcast();

        console2.log("poolId of the deployed pool - ");
        console2.logBytes32(PoolId.unwrap(pool.toId()));
    }
}
