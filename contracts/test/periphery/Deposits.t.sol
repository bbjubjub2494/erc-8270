// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {Test} from "dependencies/forge-std-1.16.1/src/Test.sol";

import {IERC8270} from "src/interfaces/IERC8270.sol";
import {IDepositContract} from "src/interfaces/IDepositContract.sol";
import {DepositsBase} from "src/periphery/DepositsBase.sol";
import {Deposits} from "src/periphery/Deposits.sol";

import {DepositContractMock} from "test/mock/DepositContractMock.sol";

import {deployCore} from "scripts/Deploy.s.sol";

contract DepositsTest is Test {
    DepositContractMock constant depositContract = DepositContractMock(0x00000000219ab540356cBB839Cbe05303d7705Fa);

    address user1 = makeAddr("user 1");
    address user2 = makeAddr("user 2");
    address user3 = makeAddr("user 3");
    bytes32 constant validatorKey1Hi = 0x00102030405060708090a0b0c0d0e0f112131415161718191a1b1c1d1e1f2232;
    bytes16 constant validatorKey1Lo = 0x425262728292a2b2c2d2e2f334353637;
    bytes constant validatorKey1 = bytes.concat(validatorKey1Hi, validatorKey1Lo);
    bytes constant signature =
        hex"00102030405060708090a0b0c0d0e0f112131415161718191a1b1c1d1e1f2232425262728292a2b2c2d2e2f33435363738393a3b3c3d3e3f445464748494a4b4c4d4e4f5565758595a5b5c5d5e5f66768696a6b6c6d6e6f778797a7b7c7d7e7f"; // pwn cyclic -n 2 -a 0123456789abcdef 192

    uint256 id1;

    IERC8270 erc8270;
    Deposits dut;

    function setUp() public {
        deployCodeTo("test/mock/DepositContractMock.sol", address(depositContract));
        erc8270 = IERC8270(deployCore());
        vm.prank(user1);
        id1 = erc8270.mint(validatorKey1Hi, validatorKey1Lo, user1);

        dut = new Deposits(erc8270, depositContract);
    }

    function expectDeposit(bytes memory validatorKey, bytes32 withdrawalCredentials, bytes memory sig, uint256 amount)
        internal
    {
        amount /= 1e9;
        bytes memory amountBytes = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            amountBytes[i] = bytes1(uint8(amount >> (8 * i)));
        }
        bytes memory indexBytes = new bytes(8);
        vm.expectEmit(address(depositContract));
        emit IDepositContract.DepositEvent(
            validatorKey, bytes.concat(withdrawalCredentials), amountBytes, sig, indexBytes
        );
    }

    function test_frontrunnable_deposit() public {
        uint256 amount = 1 ether;
        bytes32 withdrawalCredentials =
            bytes32(bytes1(uint8(1))) | bytes32(uint256(uint160(erc8270.withdrawalAddressOf(id1))));
        bytes32 depositDataRoot =
            depositContract._computeDepositDataRoot(validatorKey1, signature, withdrawalCredentials, amount);
        expectDeposit(validatorKey1, withdrawalCredentials, signature, amount);
        dut.frontrunnable{value: amount}(id1, false, signature, depositDataRoot);
    }

    function test_topup_deposit() public {
        uint256 amount = 1 ether;
        bytes memory expectedSignature = new bytes(96);
        expectDeposit(validatorKey1, bytes32(0), expectedSignature, amount);
        dut.topup{value: amount}(id1);
    }

    function test_topup_extra_value() public {
        // audit false positive
        uint256 amount = 1 ether + 1;
        vm.expectRevert("DepositContract: deposit value not multiple of gwei");
        dut.topup{value: amount}(id1);
    }

    function test_protected_deposit() public {
        uint256 amount = 1 ether;
        bytes32 withdrawalCredentials =
            bytes32(bytes1(uint8(1))) | bytes32(uint256(uint160(erc8270.withdrawalAddressOf(id1))));
        bytes32 depositDataRoot =
            depositContract._computeDepositDataRoot(validatorKey1, signature, withdrawalCredentials, amount);
        bytes32 depositRoot = depositContract.get_deposit_root();

        expectDeposit(validatorKey1, withdrawalCredentials, signature, amount);
        dut.protected{value: amount}(id1, false, signature, depositDataRoot, depositRoot);
    }

    function test_protected_deposit_wrongRoot() public {
        uint256 amount = 1 ether;
        bytes32 withdrawalCredentials =
            bytes32(bytes1(uint8(1))) | bytes32(uint256(uint160(erc8270.withdrawalAddressOf(id1))));
        bytes32 depositDataRoot =
            depositContract._computeDepositDataRoot(validatorKey1, signature, withdrawalCredentials, amount);
        bytes32 wrongRoot = bytes32(uint256(12345));

        vm.expectRevert(DepositsBase.DepositRootMismatch.selector);
        dut.protected{value: amount}(id1, false, signature, depositDataRoot, wrongRoot);
    }
}
