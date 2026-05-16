// SPDX-License-Identifier: CC-0
pragma solidity ^0.8;

import {IERC165} from "dependencies/forge-std-1.16.0/src/interfaces/IERC165.sol";

interface IERC5646 is IERC165 {
    /// @notice Function to return current token state fingerprint.
    /// @param tokenId Id of a token state in question.
    /// @return Current token state fingerprint.
    function getStateFingerprint(uint256 tokenId) external view returns (bytes32);
}
