// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {Test} from "dependencies/forge-std-1.16.0/src/Test.sol";

import {IERC20} from "dependencies/forge-std-1.16.0/src/interfaces/IERC20.sol";
import {IERC165} from "dependencies/forge-std-1.16.0/src/interfaces/IERC165.sol";
import {IERC721} from "dependencies/forge-std-1.16.0/src/interfaces/IERC721.sol";

import {IERCXXXX} from "src/interfaces/IERCXXXX.sol";

contract ERCXXXXTest is Test {
    address user1 = makeAddr("user 1");
    address user2 = makeAddr("user 2");
    address user3 = makeAddr("user 3");
    bytes32 constant validatorKey1Hi = 0x00102030405060708090a0b0c0d0e0f112131415161718191a1b1c1d1e1f2232;
    bytes16 constant validatorKey1Lo = 0x425262728292a2b2c2d2e2f334353637;

    IERCXXXX dut;

    uint256 id1;

    function setUp() external {
        dut = IERCXXXX(deployCode("src/ERCXXXX.vy"));
        vm.prank(user1);
        id1 = dut.mint(validatorKey1Hi, validatorKey1Lo, user1);
    }

    // storage layout //

    function test_storage_layout() external {
        assertEq(vm.load(address(dut), bytes32(uint256(256))), bytes32(uint256(uint160(user1))));

        dut.mint(validatorKey1Hi, validatorKey1Lo, user2);
        assertEq(vm.load(address(dut), bytes32(uint256(264))), bytes32(uint256(uint160(user2))));
    }

    // ERC-165 //

    function test_supports_interface() external view {
        assertTrue(dut.supportsInterface(type(IERC721).interfaceId));
        assertTrue(dut.supportsInterface(type(IERC165).interfaceId));
        assertFalse(dut.supportsInterface(type(IERC20).interfaceId));
    }

    // ERC-721 //

    function test_mint(bytes32 validatorKey2Hi, bytes16 validatorKey2Lo) external {
        assertEq(dut.ownerOf(id1), user1);
        (bytes32 hi, bytes16 lo) = dut.validatorKeyOf(id1);
        assertEq(hi, validatorKey1Hi);
        assertEq(lo, validatorKey1Lo);

        // different validator, same user
        uint256 id2 = dut.mint(validatorKey2Hi, validatorKey2Lo, user1);
        assertEq(dut.ownerOf(id2), user1);

        // different user, same validator
        uint256 id3 = dut.mint(validatorKey1Hi, validatorKey1Lo, user2);
        assertEq(dut.ownerOf(id3), user2);
    }

    function test_mint_already_minted() external {
        // same user and validator, should fail due to create2 collision
        //vm.expectRevert("ERC-XXXX: already minted");
        dut.mint(validatorKey1Hi, validatorKey1Lo, user1);
    }

    function test_unauthorized() external {
        vm.prank(user2);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.approve(user2, id1);

        vm.prank(user2);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.transferFrom(user1, user2, id1);

        vm.prank(user2);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.safeTransferFrom(user1, user2, id1);
    }

    function test_transfer() external {
        uint256 snapshot = vm.snapshotState();

        vm.prank(user1);
        dut.transferFrom(user1, user2, id1);
        assertEq(dut.ownerOf(id1), user2);

        vm.revertToState(snapshot);

        vm.prank(user1);
        dut.approve(user2, id1);
        assertEq(dut.getApproved(id1), user2);

        vm.prank(user2);
        dut.transferFrom(user1, user3, id1);
        assertEq(dut.ownerOf(id1), user3);
        assertEq(dut.getApproved(id1), address(0));

        vm.revertToState(snapshot);

        vm.prank(user1);
        dut.setApprovalForAll(user2, true);
        assertTrue(dut.isApprovedForAll(user1, user2));

        vm.prank(user2);
        vm.expectRevert(bytes("TODO"));
        dut.safeTransferFrom(user1, user3, id1);
        // assertEq(dut.ownerOf(id1), user3);
        assertTrue(dut.isApprovedForAll(user1, user2));

        vm.prank(user1);
        dut.setApprovalForAll(user2, false);
        assertFalse(dut.isApprovedForAll(user1, user2));
    }
}
