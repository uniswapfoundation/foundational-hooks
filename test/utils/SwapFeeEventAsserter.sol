// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console2.sol";

library SwapFeeEventAsserter {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    //
    bytes32 internal constant SWAP_EVENT_SIGNATURE =
        keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    function getSwapFeeFromEvent(Vm.Log[] memory recordedLogs) internal pure returns (uint24 fee) {
        for (uint256 i; i < recordedLogs.length; i++) {
            if (recordedLogs[i].topics[0] == SWAP_EVENT_SIGNATURE) {
                (,,,,, fee) = abi.decode(recordedLogs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                break;
            }
        }
    }

    function assertSwapFee(Vm.Log[] memory recordedLogs, uint24 expectedFee) internal pure {
        _vm.assertEq(getSwapFeeFromEvent(recordedLogs), expectedFee);
    }
}
