// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Generic4626Router, IPoolManager} from "src/examples/4626-router/Generic4626Router.sol";

string constant junkSeedPhrase = "test test test test test test test test test test test junk";

contract DeploySpell is Script {
    address private CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address private POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    function setUp() external view {
        require(block.chainid == 8453);

        console2.log("Chain:", block.chainid);
    }

    function run() external {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory constructorArgs = abi.encode(POOL_MANAGER);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, flags, type(Generic4626Router).creationCode, constructorArgs
        );

        vm.startBroadcast();

        Generic4626Router deployedRouter = new Generic4626Router{salt: salt}(
            IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b)
        );

        vm.stopBroadcast();

        require(address(deployedRouter) == hookAddress, "DeployScript: hook address mismatch");
        console2.log("Deployed Router: %s", address(deployedRouter));
    }
}
