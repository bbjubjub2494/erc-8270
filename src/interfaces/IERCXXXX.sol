// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8;

import {IERC721} from "dependencies/forge-std-1.16.0/src/interfaces/IERC721.sol";

interface IERCXXXX is IERC721 {
    function mint(bytes32 validatorKeyHi, bytes16 validatorKeyLo, address initialOwner)
        external
        returns (uint256 tokenId);

    function validatorKeyOf(uint256 tokenId) external returns (bytes32 validatorKeyHi, bytes16 validatorKeyLo);
}
