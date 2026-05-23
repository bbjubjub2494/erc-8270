// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {Test} from "dependencies/forge-std-1.16.1/src/Test.sol";
import {stdJson} from "dependencies/forge-std-1.16.1/src/StdJson.sol";

import {IERC20} from "dependencies/forge-std-1.16.1/src/interfaces/IERC20.sol";
import {IERC165} from "dependencies/forge-std-1.16.1/src/interfaces/IERC165.sol";
import {
    IERC721,
    IERC721Enumerable,
    IERC721Metadata,
    IERC721TokenReceiver
} from "dependencies/forge-std-1.16.1/src/interfaces/IERC721.sol";

import {IERC5646} from "src/interfaces/IERC5646.sol";
import {IERCXXXX} from "src/interfaces/IERCXXXX.sol";

using stdJson for string;

contract ERCXXXXTest is Test {
    address constant WITHDRAWAL_REQUESTS = 0x00000961Ef480Eb55e80D19ad83579A64c007002; // EIP-7002 contract
    address constant CONSOLIDATION_REQUESTS = 0x0000BBdDc7CE488642fb579F8B00f3a590007251; // EIP-7251 contract

    address user1 = makeAddr("user 1");
    address user2 = makeAddr("user 2");
    address user3 = makeAddr("user 3");
    bytes32 constant validatorKey1Hi = 0x00102030405060708090a0b0c0d0e0f112131415161718191a1b1c1d1e1f2232;
    bytes16 constant validatorKey1Lo = 0x425262728292a2b2c2d2e2f334353637;

    IERCXXXX dut;

    uint256 id1;

    function setUp() external {
        bytes memory wrCode = vm.getCode("src/core/WithdrawalReceiver.vy");
        dut = IERCXXXX(deployCode("src/core/ERCXXXX.vy", abi.encode(wrCode)));

        assertEq(dut.totalSupply(), 0);
        vm.expectRevert("ERC-721: invalid index");
        dut.tokenByIndex(0);
        assertEq(dut.balanceOf(user1), 0);
        vm.expectRevert("ERC-721: invalid index");
        dut.tokenOfOwnerByIndex(user1, 0);

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(address(0), user1, 1);
        vm.prank(user1);
        id1 = dut.mint(validatorKey1Hi, validatorKey1Lo, user1);
    }

    // storage layout //

    function test_storage_layout() external {
        assertEq(vm.load(address(dut), bytes32(uint256(256))), bytes32(uint256(uint160(user1))));

        dut.mint(validatorKey1Hi, validatorKey1Lo, user2);
        assertEq(vm.load(address(dut), bytes32(uint256(260))), bytes32(uint256(uint160(user2))));
    }

    // ERC-165 //

    function test_supports_interface() external view {
        assertTrue(dut.supportsInterface(type(IERC165).interfaceId));
        assertTrue(dut.supportsInterface(type(IERC721).interfaceId));
        assertTrue(dut.supportsInterface(type(IERC721Enumerable).interfaceId));
        assertTrue(dut.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(dut.supportsInterface(type(IERC5646).interfaceId));
        assertFalse(dut.supportsInterface(type(IERC20).interfaceId));
    }

    // ERC-721 Metadata //

    function test_metadata() external view {
        assertEq(dut.name(), "ERC-XXXX Wrapped Beacon Stake");
        assertEq(dut.symbol(), "ERCXXXX");
    }

    function test_token_uri_reverts_nonexistent() external {
        vm.expectRevert("ERC-721: token does not exist");
        dut.tokenURI(999);
        string memory buf = dut.tokenURI(id1);
        string memory expectedPrefix = "data:application/json,";
        uint256 length;
        assembly {
            length := mload(buf)
            mstore(buf, mload(expectedPrefix)) // truncation
        }
        assertEq(buf, expectedPrefix);

        assembly {
            // cut out uri prefix
            let jsonlength := sub(length, mload(expectedPrefix))
            mcopy(add(buf, 32), add(add(buf, 32), mload(expectedPrefix)), jsonlength)
            mstore(buf, jsonlength)
        }
        assertEq(buf.readString(".name"), "ERC-XXXX Token #1");
        assertEq(buf.readString(".attributes[0].trait_type"), "Validator Key");
        assertEq(vm.parseBytes(buf.readString(".attributes[0].value")), bytes.concat(validatorKey1Hi, validatorKey1Lo));
        assertEq(buf.readString(".attributes[1].trait_type"), "Withdrawal Address");
        assertEq(buf.readString(".attributes[1].value"), vm.toString(dut.withdrawalAddressOf(id1)));
    }

    // ERC-721 //

    function test_mint(bytes32 validatorKey2Hi, bytes16 validatorKey2Lo) external {
        vm.assume(validatorKey2Hi >= hex"80");

        assertEq(dut.ownerOf(id1), user1);
        (bytes32 hi, bytes16 lo) = dut.validatorKeyOf(id1);
        assertEq(hi, validatorKey1Hi);
        assertEq(lo, validatorKey1Lo);

        // different validator, same user
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(address(0), user1, 2);
        uint256 id2 = dut.mint(validatorKey2Hi, validatorKey2Lo, user1);
        assertEq(dut.ownerOf(id2), user1);

        // different user, same validator
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(address(0), user2, 3);
        uint256 id3 = dut.mint(validatorKey1Hi, validatorKey1Lo, user2);
        assertEq(dut.ownerOf(id3), user2);
    }

    function test_mint_already_minted() external {
        // same user and validator, should fail due to create2 collision
        vm.expectRevert("ERC-XXXX: already minted");
        dut.mint(validatorKey1Hi, validatorKey1Lo, user1);
    }

    function test_unauthorized() external {
        vm.prank(user2);
        vm.expectRevert("ERC-721: not owner or operator");
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

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user2, id1);
        vm.prank(user1);
        dut.transferFrom(user1, user2, id1);
        assertEq(dut.ownerOf(id1), user2);

        vm.revertToState(snapshot);

        vm.expectEmit(address(dut));
        emit IERC721.Approval(user1, user2, id1);
        vm.prank(user1);
        dut.approve(user2, id1);
        assertEq(dut.getApproved(id1), user2);

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user3, id1);
        vm.prank(user2);
        dut.transferFrom(user1, user3, id1);
        assertEq(dut.ownerOf(id1), user3);
        assertEq(dut.getApproved(id1), address(0));

        vm.revertToState(snapshot);

        vm.expectEmit(address(dut));
        emit IERC721.ApprovalForAll(user1, user2, true);
        vm.prank(user1);
        dut.setApprovalForAll(user2, true);
        assertTrue(dut.isApprovedForAll(user1, user2));

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user3, id1);
        vm.prank(user2);
        dut.safeTransferFrom(user1, user3, id1);
        assertEq(dut.ownerOf(id1), user3);
        assertTrue(dut.isApprovedForAll(user1, user2));

        vm.expectEmit(address(dut));
        emit IERC721.ApprovalForAll(user1, user2, false);
        vm.prank(user1);
        dut.setApprovalForAll(user2, false);
        assertFalse(dut.isApprovedForAll(user1, user2));

        vm.prank(user1);
        vm.expectRevert("ERC-721: approve to caller");
        dut.setApprovalForAll(user1, true);
    }

    function test_safe_transfer_1() public {
        // not a contract = no call
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user2, id1);
        vm.prank(user1);
        vm.expectCall(user2, "", 0);
        dut.safeTransferFrom(user1, user2, id1);
    }

    function test_safe_transfer_2() public {
        vm.etch(user2, "code");
        vm.expectCall(user2, abi.encodeCall(IERC721TokenReceiver.onERC721Received, (user1, user1, id1, "")));
        vm.mockCall(user2, bytes(""), abi.encode(IERC721TokenReceiver.onERC721Received.selector));
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user2, id1);
        vm.prank(user1);
        dut.safeTransferFrom(user1, user2, id1);
    }

    function test_safe_transfer_3() public {
        vm.etch(user2, "code");
        vm.expectCall(user2, abi.encodeCall(IERC721TokenReceiver.onERC721Received, (user1, user1, id1, "")));
        vm.mockCall(user2, bytes(""), abi.encode(bytes4(0x12345678)));
        vm.expectRevert("ERC-721: receiver rejected transfer");
        vm.prank(user1);
        dut.safeTransferFrom(user1, user2, id1);
    }

    function test_safe_transfer_4() public {
        vm.etch(user2, "code");
        vm.expectCall(user2, abi.encodeCall(IERC721TokenReceiver.onERC721Received, (user3, user1, id1, "data")));
        vm.mockCall(user2, bytes(""), abi.encode(IERC721TokenReceiver.onERC721Received.selector));
        vm.expectEmit(address(dut));
        emit IERC721.Approval(user1, user3, id1);
        vm.prank(user1);
        dut.approve(user3, id1);
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user2, id1);
        vm.prank(user3);
        dut.safeTransferFrom(user1, user2, id1, "data");
    }

    // ERC-721 Enumerable //

    function _checkTokensByIndex(uint256[] memory expected) internal {
        _checkTokensOfOwnerByIndex(address(0), expected);
    }

    function _checkTokensOfOwnerByIndex(address owner, uint256[] memory expected) internal {
        bool total = owner == address(0);
        assertEq(total ? dut.totalSupply() : dut.balanceOf(owner), expected.length);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(total ? dut.tokenByIndex(i) : dut.tokenOfOwnerByIndex(owner, i), expected[i]);
        }
        vm.expectRevert("ERC-721: invalid index");
        if (total) {
            dut.tokenByIndex(expected.length);
        } else {
            dut.tokenOfOwnerByIndex(owner, expected.length);
        }
    }

    // workaround for no literals
    function _a() internal pure returns (uint256[] memory a) {
        a = new uint256[](0);
    }

    function _a(uint256 v0) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = v0;
    }

    function _a(uint256 v0, uint256 v1) internal pure returns (uint256[] memory a) {
        a = new uint256[](2);
        a[0] = v0;
        a[1] = v1;
    }

    function _a(uint256 v0, uint256 v1, uint256 v2) internal pure returns (uint256[] memory a) {
        a = new uint256[](3);
        a[0] = v0;
        a[1] = v1;
        a[2] = v2;
    }

    function test_enumerate() external {
        bytes32 validatorKey2Hi = 0x8111111111111111111111111111111111111111111111111111111111111111;
        bytes16 validatorKey2Lo = 0x22222222222222222222222222222222;

        _checkTokensByIndex(_a(id1));
        _checkTokensOfOwnerByIndex(user1, _a(id1));

        // different validator, same user
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(address(0), user1, 2);
        uint256 id2 = dut.mint(validatorKey2Hi, validatorKey2Lo, user1);
        _checkTokensByIndex(_a(id1, id2));
        _checkTokensOfOwnerByIndex(user1, _a(id1, id2));

        // different user, same validator
        assertEq(dut.balanceOf(user2), 0);
        vm.expectEmit(address(dut));
        emit IERC721.Transfer(address(0), user2, 3);
        uint256 id3 = dut.mint(validatorKey1Hi, validatorKey1Lo, user2);
        _checkTokensByIndex(_a(id1, id2, id3));
        _checkTokensOfOwnerByIndex(user2, _a(id3));

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user1, user3, id1);
        vm.prank(user1);
        dut.transferFrom(user1, user3, id1);
        _checkTokensByIndex(_a(id1, id2, id3));
        _checkTokensOfOwnerByIndex(user1, _a(id2));
        _checkTokensOfOwnerByIndex(user3, _a(id1));

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user2, user3, id3);
        vm.prank(user2);
        dut.transferFrom(user2, user3, id3);
        _checkTokensByIndex(_a(id1, id2, id3));
        _checkTokensOfOwnerByIndex(user2, _a());
        _checkTokensOfOwnerByIndex(user3, _a(id1, id3));

        vm.expectEmit(address(dut));
        emit IERC721.Transfer(user3, user2, id3);
        vm.prank(user3);
        dut.transferFrom(user3, user2, id3);
        _checkTokensOfOwnerByIndex(user3, _a(id1));
        _checkTokensOfOwnerByIndex(user2, _a(id3));
    }

    // ERC-5646 //

    struct ConsolidationRequested {
        bytes32 previousFingerprint;
        bytes32 targetKeyHi;
        bytes16 targetKeyLo;
    }

    struct NativeBalancePulled {
        bytes32 previousFingerprint;
        address target;
        bytes data;
    }

    struct ArbitraryCall {
        bytes32 previousFingerprint;
        address target;
        bytes data;
    }

    function test_state_fingerprint() public {
        uint256 fee = 1 wei;
        _mockQueryFee(WITHDRAWAL_REQUESTS, fee);
        _mockQueryFee(CONSOLIDATION_REQUESTS, fee);
        bytes32 validatorKey2Hi = 0x8111111111111111111111111111111111111111111111111111111111111111;
        bytes16 validatorKey2Lo = 0x22222222222222222222222222222222;

        bytes32 expected = vm.eip712HashStruct("Minted()", "");
        assertEq(dut.getStateFingerprint(id1), expected);

        vm.prank(user1);
        dut.pullNativeBalance(id1, user1);
        expected = vm.eip712HashStruct(
            "NativeBalancePulled(bytes32 previousFingerprint, address target, bytes data)",
            abi.encode(NativeBalancePulled(expected, user1, ""))
        );
        assertEq(dut.getStateFingerprint(id1), expected);

        hoax(user1);
        dut.requestFullWithdrawal{value: fee}(id1);
        // no change
        assertEq(dut.getStateFingerprint(id1), expected);

        hoax(user1);
        dut.requestPartialWithdrawal{value: fee}(id1, 1 ether);
        // no change
        assertEq(dut.getStateFingerprint(id1), expected);

        hoax(user1);
        dut.requestSwitchToCompounding{value: fee}(id1);
        expected = vm.eip712HashStruct(
            "ConsolidationRequested(bytes32 previousFingerprint, bytes32 targetKeyHi, bytes16 targetKeyLo)",
            abi.encode(ConsolidationRequested(expected, validatorKey1Hi, validatorKey1Lo))
        );
        assertEq(dut.getStateFingerprint(id1), expected);

        hoax(user1);
        dut.requestConsolidation{value: fee}(id1, validatorKey2Hi, validatorKey2Lo);
        expected = vm.eip712HashStruct(
            "ConsolidationRequested(bytes32 previousFingerprint, bytes32 targetKeyHi, bytes16 targetKeyLo)",
            abi.encode(ConsolidationRequested(expected, validatorKey2Hi, validatorKey2Lo))
        );
        assertEq(dut.getStateFingerprint(id1), expected);

        vm.prank(user1);
        dut.transferFrom(user1, user1, id1);
        // no change
        assertEq(dut.getStateFingerprint(id1), expected);

        address target = makeAddr("target");
        vm.prank(user1);
        dut.arbitraryCall(id1, target, "data");
        expected = vm.eip712HashStruct(
            "ArbitraryCall(bytes32 previousFingerprint, address target, bytes data)",
            abi.encode(ArbitraryCall(expected, target, "data"))
        );
        assertEq(dut.getStateFingerprint(id1), expected);
    }

    // ERC-XXXX //

    function _mockQueryFee(address systemContract, uint256 fee) internal {
        vm.mockCall(systemContract, bytes(""), abi.encode(fee));
    }

    function _mockWithdrawalRequest(uint256 fee, uint64 amount) internal {
        _mockQueryFee(WITHDRAWAL_REQUESTS, fee);
        vm.expectCall(WITHDRAWAL_REQUESTS, fee, bytes.concat(validatorKey1Hi, validatorKey1Lo, bytes8(amount)));
    }

    function _mockConsolidationRequest(uint256 fee, bytes32 validatorKey2Hi, bytes16 validatorKey2Lo) internal {
        _mockQueryFee(CONSOLIDATION_REQUESTS, fee);
        vm.expectCall(
            CONSOLIDATION_REQUESTS,
            fee,
            bytes.concat(validatorKey1Hi, validatorKey1Lo, validatorKey2Hi, validatorKey2Lo)
        );
    }

    function test_request_full_withdrawal() public {
        uint256 fee = 1 wei;

        _mockWithdrawalRequest(fee, 0);
        hoax(user1, 1 ether);
        dut.requestFullWithdrawal{value: 2}(id1);

        hoax(user2, 1 ether);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.requestFullWithdrawal{value: 2}(id1);
    }

    function test_request_full_withdrawal_fee_from_receiver() public {
        uint256 fee = 1 gwei;
        vm.deal(dut.withdrawalAddressOf(id1), fee);

        _mockWithdrawalRequest(fee, 0);
        vm.prank(user1);
        dut.requestFullWithdrawal(id1);
    }

    function test_request_partial_withdrawal(uint64 amount) public {
        vm.assume(amount != 0);
        uint256 fee = 1 wei;

        _mockWithdrawalRequest(fee, amount);
        hoax(user1, 1 ether);
        dut.requestPartialWithdrawal{value: 2}(id1, amount);

        hoax(user2, 1 ether);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.requestPartialWithdrawal{value: 2}(id1, amount);
    }

    function test_request_partial_withdrawal_fee_from_receiver(uint64 amount) public {
        vm.assume(amount != 0);
        uint256 fee = 1 gwei;
        vm.deal(dut.withdrawalAddressOf(id1), fee);

        _mockWithdrawalRequest(fee, amount);
        vm.prank(user1);
        dut.requestPartialWithdrawal(id1, amount);
    }

    function test_request_partial_withdrawal_reject_zero() public {
        uint256 fee = 1 wei;

        hoax(user1, 1 ether);
        vm.expectRevert("ERC-XXXX: zero partial withdrawal amount");
        dut.requestPartialWithdrawal{value: fee}(id1, 0);
    }

    function test_request_switch_to_compounding_withdrawal() public {
        uint256 fee = 1 wei;

        _mockConsolidationRequest(fee, validatorKey1Hi, validatorKey1Lo);
        vm.expectEmit();
        emit IERCXXXX.ConsolidationRequest(id1, validatorKey1Hi, validatorKey1Lo);
        hoax(user1, 1 ether);
        dut.requestSwitchToCompounding{value: 2}(id1);

        hoax(user2, 1 ether);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.requestSwitchToCompounding{value: 2}(id1);
    }

    function test_request_switch_to_compounding_fee_from_receiver() public {
        uint256 fee = 1 gwei;
        vm.deal(dut.withdrawalAddressOf(id1), fee);

        _mockConsolidationRequest(fee, validatorKey1Hi, validatorKey1Lo);
        vm.prank(user1);
        dut.requestSwitchToCompounding(id1);
    }

    function test_request_consolidation(bytes32 validatorKey2Hi, bytes16 validatorKey2Lo) public {
        uint256 fee = 1 wei;

        _mockConsolidationRequest(fee, validatorKey2Hi, validatorKey2Lo);
        vm.expectEmit();
        emit IERCXXXX.ConsolidationRequest(id1, validatorKey2Hi, validatorKey2Lo);
        hoax(user1, 1 ether);
        dut.requestConsolidation{value: 2}(id1, validatorKey2Hi, validatorKey2Lo);

        hoax(user2, 1 ether);
        vm.expectRevert("ERC-721: not owner or approved");
        dut.requestConsolidation{value: 2}(id1, validatorKey2Hi, validatorKey2Lo);
    }

    function test_request_consolidation_fee_from_receiver(bytes32 validatorKey2Hi, bytes16 validatorKey2Lo) public {
        uint256 fee = 1 gwei;
        vm.deal(dut.withdrawalAddressOf(id1), fee);

        _mockConsolidationRequest(fee, validatorKey2Hi, validatorKey2Lo);
        vm.prank(user1);
        dut.requestConsolidation(id1, validatorKey2Hi, validatorKey2Lo);
    }

    function test_pull_native_balance(address destination) public {
        assumeNotPrecompile(destination);
        assumePayable(destination);
        vm.assume(destination != address(0));

        vm.deal(dut.withdrawalAddressOf(id1), 1 ether);

        vm.expectRevert("ERC-721: not owner or approved");
        vm.prank(user2);
        dut.pullNativeBalance(id1, destination);

        vm.expectCall(destination, 1 ether, "");
        vm.expectEmit();
        emit IERCXXXX.PullNativeBalance(id1, destination, "");
        vm.prank(user1);
        dut.pullNativeBalance(id1, destination);

        vm.expectRevert("ERC-XXXX: pull native balance to zero");
        vm.prank(user1);
        dut.pullNativeBalance(id1, address(0));
    }

    function test_arbitrary_call(address target, uint256 value, bytes calldata data) public {
        assumeNotPrecompile(target);
        // WithdrawalReceiver will revert due to access control
        vm.assume(data.length == 0 || target != dut.withdrawalAddressOf(id1));

        vm.expectRevert("ERC-721: not owner or approved");
        hoax(user2, value);
        dut.arbitraryCall{value: value}(id1, target, data);

        vm.expectCall(target, value, data);
        vm.expectEmit();
        emit IERCXXXX.ArbitraryCall(id1, target, data);
        hoax(user1, value);
        dut.arbitraryCall{value: value}(id1, target, data);
    }

    function test_pull_native_balance_with_data(address target, bytes calldata data) public {
        assumeNotPrecompile(target);
        assumePayable(target);
        vm.assume(data.length == 0 || target != dut.withdrawalAddressOf(id1));
        vm.assume(target != address(0));

        vm.deal(dut.withdrawalAddressOf(id1), 1 ether);

        vm.expectRevert("ERC-721: not owner or approved");
        vm.prank(user2);
        dut.pullNativeBalance(id1, target, data);

        vm.expectCall(target, 1 ether, data);
        vm.expectEmit();
        emit IERCXXXX.PullNativeBalance(id1, target, data);
        vm.prank(user1);
        dut.pullNativeBalance(id1, target, data);
    }

    // Regression tests //
    function test_stale_index_after_transfer() external {
        bytes32 validatorKey2Hi = 0x8111111111111111111111111111111111111111111111111111111111111111;
        bytes16 validatorKey2Lo = 0x22222222222222222222222222222222;
        uint256 id2 = dut.mint(validatorKey2Hi, validatorKey2Lo, user1); // user1 = [id1, id2]

        vm.prank(user1);
        dut.transferFrom(user1, user2, id1); // id2 moves to index 0; its stored index is still 1

        vm.prank(user1);
        // reverts if stored index is stale
        dut.transferFrom(user1, user2, id2);
    }

    function test_approve_by_operator() public {
        vm.prank(user1);
        dut.setApprovalForAll(user2, true);

        // the owner field should be the owner, not the caller
        vm.expectEmit();
        emit IERC721.Approval(user1, user3, id1);
        vm.prank(user2);
        dut.approve(user3, id1);
    }

    function test_approve_by_approvee() public {
        vm.prank(user1);
        dut.approve(user2, id1);

        // the approvee cannot set a new approvee.
        // ERC-721 conformance
        vm.expectRevert("ERC-721: not owner or operator");
        vm.prank(user2);
        dut.approve(user3, id1);
    }
}
