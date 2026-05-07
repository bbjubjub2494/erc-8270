// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test} from "dependencies/forge-std-1.16.0/src/Test.sol";

import {IERC20} from "dependencies/forge-std-1.16.0/src/interfaces/IERC20.sol";
import {IERC165} from "dependencies/forge-std-1.16.0/src/interfaces/IERC165.sol";
import {IERC721, IERC721TokenReceiver} from "dependencies/forge-std-1.16.0/src/interfaces/IERC721.sol";

interface IWithdrawalReceiver {
	function _pull_native_balance(address destination) external;
}

contract ERCXXXXTest is Test {
    address constant WITHDRAWAL_REQUESTS = 0x00000961Ef480Eb55e80D19ad83579A64c007002; // EIP-7002 contract
    address constant CONSOLIDATION_REQUESTS = 0x0000BBdDc7CE488642fb579F8B00f3a590007251; // EIP-7251 contract

    address controller = makeAddr("controller");
    address user = makeAddr("user");
    bytes32 constant validatorKey1Hi = 0x00102030405060708090a0b0c0d0e0f112131415161718191a1b1c1d1e1f2232;
    bytes16 constant validatorKey1Lo = 0x425262728292a2b2c2d2e2f334353637;

    IWithdrawalReceiver dut;

    function setUp() external {
	    vm.prank(controller);
        dut = IWithdrawalReceiver(deployCode("src/WithdrawalReceiver.vy"));
    }

    function test_pull_native_balance() public {
	    vm.deal(address(dut), 1 ether);
	    vm.prank(user);
	    vm.expectRevert();
	    dut._pull_native_balance(user);

	    vm.prank(controller);
	    dut._pull_native_balance(user);
	    assertEq(address(dut).balance, 0);
	    assertEq(user.balance, 1 ether);
    }
}
