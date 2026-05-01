// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Script, console2} from "dependencies/forge-std-1.16.0/src/Script.sol";

import {IERCXXXX} from "src/interfaces/IERCXXXX.sol";

contract DeployScript is Script {
    address immutable DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function deployDeterministic(bytes memory initCode) internal returns (address) {
        bytes32 initCodeHash = keccak256(initCode);

        bytes32 salt = 0;
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), DEPLOYMENT_PROXY, salt, initCodeHash)))));
        if (predicted.code.length == 0) {
            vm.broadcast();
            (bool ok,) = DEPLOYMENT_PROXY.call(bytes.concat(salt, initCode));
            assert(ok);
            assert(predicted.code.length != 0);
        }
        return predicted;
    }

    function setUp() external {
        setChain(
            "chiado", ChainData({name: "Gnosis Chiado Testnet", chainId: 10200, rpcUrl: "https://rpc.chiadochain.net"})
        );
    }

    function run() external {
        bytes memory wrCode = vm.getCode("src/core/WithdrawalReceiver.vy");
        bytes memory ercCode = bytes.concat(vm.getCode("src/core/ERCXXXX.vy"), abi.encode(wrCode));
        address erc = deployDeterministic(ercCode);
        console2.log("Deployed ERCXXXX at", erc);

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
        address deposits = deployDeterministic(bytes.concat(depositsCode, abi.encode(erc, depositContract)));
        console2.log("Deployed Deposits at", deposits);
    }
}
