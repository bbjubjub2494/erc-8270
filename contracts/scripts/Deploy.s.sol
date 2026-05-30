// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8;

import {Script, console2} from "dependencies/forge-std-1.16.1/src/Script.sol";
import {stdJson} from "dependencies/forge-std-1.16.1/src/StdJson.sol";
import {Vm} from "dependencies/forge-std-1.16.1/src/Vm.sol";

import {IERC8270} from "src/interfaces/IERC8270.sol";

using stdJson for string;

address constant DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

function deployCore() returns (address erc) {
    string[] memory args = new string[](3);
    args[0] = "uv";
    args[1] = "run";
    args[2] = "dependencies/ercs-unversioned/assets/erc-8270/prepare.py";
    string memory params = string(vm.ffi(args));
    return deployDeterministic(params.readBytes(".initcode"), "");
}

function deployDeterministic(bytes memory initCode, bytes32 salt) returns (address) {
    bytes32 initCodeHash = keccak256(initCode);

    address predicted = vm.computeCreate2Address(salt, initCodeHash, DEPLOYMENT_PROXY);
    if (predicted.code.length == 0) {
        vm.broadcast();
        (bool ok,) = DEPLOYMENT_PROXY.call(bytes.concat(salt, initCode));
        assert(ok);
        assert(predicted.code.length != 0);
    }
    return predicted;
}

contract DeployScript is Script {
    function setUp() external {
        setChain(
            "chiado", ChainData({name: "Gnosis Chiado Testnet", chainId: 10200, rpcUrl: "https://rpc.chiadochain.net"})
        );
    }

    function run() external {
        address erc = deployCore();
        console2.log("Deployed ERC8270 at", erc);

        address token;
        address depositContract = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        if (block.chainid == getChain("gnosis_chain").chainId) {
            token = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;
            depositContract = 0x0B98057eA310F4d31F2a452B414647007d1645d9;
        } else if (block.chainid == getChain("chiado").chainId) {
            token = 0x19C653Da7c37c66208fbfbE8908A5051B57b4C70;
            depositContract = 0xb97036A26259B7147018913bD58a774cf91acf25;
        }

        bytes memory depositsCode;
        if (token == address(0)) {
            // ETH variant
            depositsCode = vm.getCode("src/periphery/Deposits.sol");
        } else {
            depositsCode = vm.getCode("src/periphery/DepositsGno.sol");
        }
        address deposits = deployDeterministic(bytes.concat(depositsCode, abi.encode(erc, depositContract)), 0);
        console2.log("Deployed Deposits at", deposits);
    }
}
