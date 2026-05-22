// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test} from "dependencies/forge-std-1.16.1/src/Test.sol";

import {IERC20} from "dependencies/forge-std-1.16.1/src/interfaces/IERC20.sol";
import {IERC165} from "dependencies/forge-std-1.16.1/src/interfaces/IERC165.sol";
import {IERC721, IERC721TokenReceiver} from "dependencies/forge-std-1.16.1/src/interfaces/IERC721.sol";

interface IWithdrawalReceiver {
    function validator_key() external view returns (bytes32, bytes16);
    function set_controller(bytes32 key_hi, bytes16 key_lo) external;
    function _request_withdrawal(bytes8 amount) external payable;
    function _request_consolidation(bytes32 target_key_hi, bytes16 target_key_lo) external payable;
    function _arbitrary_call(address destination, bytes calldata data) external payable;
    function _pull_native_balance(address destination, bytes calldata data) external;
}

contract WithdrawalReceiverTest is Test {
    address constant WITHDRAWAL_REQUESTS = 0x00000961Ef480Eb55e80D19ad83579A64c007002; // EIP-7002 contract
    address constant CONSOLIDATION_REQUESTS = 0x0000BBdDc7CE488642fb579F8B00f3a590007251; // EIP-7251 contract

    address controller = makeAddr("controller");
    address user = makeAddr("user");
    bytes32 constant validatorKey1Hi = 0x00102030405060708090a0b0c0d0e0f112131415161718191a1b1c1d1e1f2232;
    bytes16 constant validatorKey1Lo = 0x425262728292a2b2c2d2e2f334353637;

    IWithdrawalReceiver dut;

    function setUp() external {
        vm.prank(controller);
        dut = IWithdrawalReceiver(deployCode("src/core/WithdrawalReceiver.vy"));
        vm.prank(controller);
        dut.set_controller(validatorKey1Hi, validatorKey1Lo);
    }

    function test_set_controller() public view {
        (bytes32 hi, bytes16 lo) = dut.validator_key();
        assertEq(hi, validatorKey1Hi);
        assertEq(lo, validatorKey1Lo);
    }

    function test_set_controller_only_controller() public {
        vm.prank(controller);
        IWithdrawalReceiver fresh = IWithdrawalReceiver(deployCode("src/core/WithdrawalReceiver.vy"));
        vm.prank(user);
        vm.expectRevert();
        fresh.set_controller(validatorKey1Hi, validatorKey1Lo);
    }

    function test_request_withdrawal(uint64 amount) public {
        uint256 fee = 1 gwei;
        vm.mockCall(WITHDRAWAL_REQUESTS, bytes(""), abi.encode(fee));
        vm.expectCall(WITHDRAWAL_REQUESTS, fee, bytes.concat(validatorKey1Hi, validatorKey1Lo, bytes8(amount)));
        vm.deal(address(dut), fee);
        vm.prank(controller);
        dut._request_withdrawal(bytes8(amount));
    }

    function test_request_withdrawal_only_controller() public {
        vm.prank(user);
        vm.expectRevert();
        dut._request_withdrawal(bytes8(0));
    }

    function test_request_consolidation(bytes32 target_key_hi, bytes16 target_key_lo) public {
        uint256 fee = 1 gwei;
        vm.mockCall(CONSOLIDATION_REQUESTS, bytes(""), abi.encode(fee));
        vm.expectCall(
            CONSOLIDATION_REQUESTS, fee, bytes.concat(validatorKey1Hi, validatorKey1Lo, target_key_hi, target_key_lo)
        );
        vm.deal(address(dut), fee);
        vm.prank(controller);
        dut._request_consolidation(target_key_hi, target_key_lo);
    }

    function test_request_consolidation_only_controller() public {
        vm.prank(user);
        vm.expectRevert();
        dut._request_consolidation(validatorKey1Hi, validatorKey1Lo);
    }

    function test_pull_native_balance(bytes calldata data) public {
        vm.deal(address(dut), 1 ether);
        vm.prank(user);
        vm.expectRevert();
        dut._pull_native_balance(user, data);

        vm.prank(controller);
        vm.expectCall(user, address(dut).balance, data);
        dut._pull_native_balance(user, data);
        assertEq(address(dut).balance, 0);
        assertEq(user.balance, 1 ether);
    }

    function test_default() public {
        bool ok;

        hoax(user);
        (ok,) = address(dut).call{value: 1 ether}("");
        assertTrue(ok, "ETH transfer succeeds");

        hoax(user);
        (ok,) = address(dut).call{value: 1 ether}(hex"abcdef01");
        assertFalse(ok, "call with unexpected calldata fails");
    }

    // Regression Tests //

    function test_inner_revert() public {
        // if internal calls fail, WR should propagate the revert.
        // false positive audit finding, but good to check
        address destination = makeAddr("destination");
        vm.etch(destination, hex"fe"); // INVALID

        vm.prank(controller);
        vm.expectRevert();
        dut._arbitrary_call(destination, hex"abcdef01");

        vm.deal(address(dut), 1 ether);
        vm.prank(controller);
        vm.expectRevert();
        dut._pull_native_balance(destination, "");
    }
}
