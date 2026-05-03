// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Script, console2} from "dependencies/forge-std-1.16.0/src/Script.sol";

import {IERCXXXX} from "src/interfaces/IERCXXXX.sol";

contract DeployScript is Script {
    function run() external {
        bytes memory wrCode = vm.getCode("src/WithdrawalReceiver.vy");
        bytes memory code = bytes.concat(vm.getCode("src/ERCXXXX.vy"), abi.encode(wrCode));
	bytes32 salt = 0;
	address out;
	vm.broadcast();
	assembly {
		out := create2(0, add(code, 32), mload(code), salt)
	}
	require(out != address(0));
	console2.log("Deployed ERCXXXX at", out);
    }
}
