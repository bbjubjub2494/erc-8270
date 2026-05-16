// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {IERC677, IERC677Receiver} from "src/interfaces/IERC677.sol";

// truncated to relevant functions.
/// @notice Interface of the modified Gnosis Beacon Chain deposit contract.
interface ISBCDepositContract is IERC677Receiver {
    /// @notice A processed deposit event.
    event DepositEvent(bytes pubkey, bytes withdrawalCredentials, bytes amount, bytes signature, bytes index);

    // forge-lint: disable-next-line(mixed-case-function)
    function stake_token() external view returns (IERC677);

    /// @notice Submit a Phase 0 DepositData object.
    /// @param pubkey A BLS12-381 public key.
    /// @param withdrawalCredentials Commitment to a public key for withdrawals.
    /// @param signature A BLS12-381 signature.
    /// @param depositDataRoot The SHA-256 hash of the SSZ-encoded DepositData object.
    /// Used as a protection against malformed input.
    function deposit(
        bytes memory pubkey,
        bytes memory withdrawalCredentials,
        bytes memory signature,
        bytes32 depositDataRoot,
        uint256 stakeAmount
    ) external;

    /// @notice Query the current deposit root hash.
    /// @return The deposit root hash.
    // forge-lint: disable-next-line(mixed-case-function)
    function get_deposit_root() external view returns (bytes32);

    /// @notice Query the current deposit count.
    /// @return The deposit count encoded as a little endian 64-bit number.
    // forge-lint: disable-next-line(mixed-case-function)
    function get_deposit_count() external view returns (bytes memory);

    /// @notice Query a balance held in this contract as a result of withdrawals.
    /// @param _address Address whose balance to query
    function withdrawableAmount(address _address) external view returns (uint256);

    /**
     * @dev Claim withdrawal amount for an address
     * @param _address Address to transfer withdrawable tokens
     */
    function claimWithdrawal(address _address) external;
}
