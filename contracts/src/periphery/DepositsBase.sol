// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {IERC8270} from "src/interfaces/IERC8270.sol";

abstract contract DepositsBase {
    error DepositRootMismatch();
    error Uint64Overflow();

    IERC8270 public immutable ERC8270;

    constructor(IERC8270 _erc8270) {
        ERC8270 = _erc8270;
    }

    function _toUint64Checked(uint256 v256) internal pure returns (uint64) {
        require(v256 <= type(uint64).max, Uint64Overflow());
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(v256);
    }

    function _toBytes8LittleEndian(uint64 v) internal pure returns (bytes8 r) {
        assembly ("memory-safe") {
            r := shl(0xf8, byte(0x1f, v))
            r := or(r, shl(0xf0, byte(0x1e, v)))
            r := or(r, shl(0xe8, byte(0x1d, v)))
            r := or(r, shl(0xe0, byte(0x1c, v)))
            r := or(r, shl(0xd8, byte(0x1b, v)))
            r := or(r, shl(0xd0, byte(0x1a, v)))
            r := or(r, shl(0xc8, byte(0x19, v)))
            r := or(r, shl(0xc0, byte(0x18, v)))
        }
    }

    function _makeWithdrawalCredential(address withdrawalAddress, bool compounding) internal pure returns (bytes32) {
        return bytes32(bytes1(uint8(compounding ? 2 : 1))) | bytes32(uint256(uint160(withdrawalAddress)));
    }

    function _prepareTopup(uint256 id, uint256 amount)
        internal
        view
        returns (
            bytes memory validatorKey,
            bytes memory withdrawalCredential,
            bytes memory signature,
            bytes32 depositDataRoot
        )
    {
        (bytes32 validatorKeyHi, bytes16 validatorKeyLo) = ERC8270.validatorKeyOf(id);
        validatorKey = bytes.concat(validatorKeyHi, validatorKeyLo);
        withdrawalCredential = new bytes(32);
        signature = new bytes(96);

        bytes32 validatorKeyRoot = sha256(bytes.concat(validatorKey, bytes16(0)));
        // sha256(bytes.concat(sha256(bytes.concat(bytes32(0), bytes32(0))), sha256(bytes.concat(bytes32(0), bytes32(0)))))
        bytes32 signatureRoot = 0xdb56114e00fdd4c1f85c892bf35ac9a89289aaecb1ebd0a96cde606a748b5d71;
        bytes8 amountBytes = _toBytes8LittleEndian(_toUint64Checked(amount));
        depositDataRoot = sha256(
            bytes.concat(
                sha256(bytes.concat(validatorKeyRoot, bytes32(0))),
                sha256(bytes.concat(bytes32(amountBytes), signatureRoot))
            )
        );
    }
}
