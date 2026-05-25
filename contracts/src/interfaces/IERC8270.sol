// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {IERC721Enumerable, IERC721Metadata} from "dependencies/forge-std-1.16.1/src/interfaces/IERC721.sol";
import {IERC5646} from "src/interfaces/IERC5646.sol";

interface IERC8270 is IERC721Enumerable, IERC721Metadata, IERC5646 {
    event ConsolidationRequest(uint256 indexed tokenId, bytes32 targetKeyHi, bytes16 targetKeyLo);

    event ArbitraryCall(uint256 indexed tokenId, address target, bytes data);

    event PullNativeBalance(uint256 indexed tokenId, address target, bytes data);

    /**
     * @notice Prepare a token intended to wrap the given validator.
     *   @dev The withdrawal address of the token depends only on the parameters of this function, hence it can be determined counterfactually.
     *   @dev This function cannot guarantee that the validator will set its withdrawal credentials to the withdrawal address associated with this token.
     *   @param validatorKeyHi The 256 most significant bits of the validator BLS12 public key.
     *   @param validatorKeyLo The 128 least significant bits of the validator BLS12 public key.
     *   @param initialOwner The address that should be the owner of the ERC-721 token.
     * 	  @return tokenId The ERC-721 id of the new token.
     */
    function mint(bytes32 validatorKeyHi, bytes16 validatorKeyLo, address initialOwner)
        external
        returns (uint256 tokenId);

    /**
     * @notice Query the validator BLS12 public key associated with this token.
     * 	  @param tokenId The ERC-721 id of the token.
     *   @return validatorKeyHi The 256 most significant bits of the validator BLS12 public key.
     *   @return validatorKeyLo The 128 least significant bits of the validator BLS12 public key.
     */
    function validatorKeyOf(uint256 tokenId) external view returns (bytes32 validatorKeyHi, bytes16 validatorKeyLo);

    /**
     * @notice Query the withdrawal address associated with this token.
     * 	  @param tokenId The ERC-721 id of the token.
     */
    function withdrawalAddressOf(uint256 tokenId) external view returns (address);

    /**
     * @notice Request an EIP-7002 partial withdrawal of the validator controlled by this token.
     *   @dev The caller may add ether value to the call in order to cover the EIP-7002 fee.
     * 	  @param tokenId The ERC-721 id of the token.
     * 	  @param amount the amount to withdraw, in consensus layer units.
     */
    function requestPartialWithdrawal(uint256 tokenId, uint64 amount) external payable;

    /**
     * @notice Request an EIP-7002 full withdrawal and exit of the validator controlled by this token.
     *   @dev The caller may add ether value to the call in order to cover the EIP-7002 fee.
     * 	  @param tokenId The ERC-721 id of the token.
     */
    function requestFullWithdrawal(uint256 tokenId) external payable;

    /**
     * @notice Request an EIP-7251 consolidation of the validator controlled by this token.
     *   @dev The caller may add ether value to the call in order to cover the EIP-7251 fee.
     * 	  @param tokenId The ERC-721 id of the token.
     *   @param targetKeyHi The 256 most significant bits of the target validator's BLS12 public key.
     *   @param targetKeyLo The 128 least significant bits of the target validator's BLS12 public key.
     */
    function requestConsolidation(uint256 tokenId, bytes32 targetKeyHi, bytes16 targetKeyLo) external payable;

    /**
     * @notice Request an EIP-7251 switch to compounding exit credentials of the validator controlled by this token.
     *   @dev The caller may add ether value to the call in order to cover the EIP-7251 fee.
     * 	  @param tokenId The ERC-721 id of the token.
     */
    function requestSwitchToCompounding(uint256 tokenId) external payable;

    /**
     * @notice Send the ether balance of the withdrawal address the the caller
     * @param tokenId The ERC-721 id of the token.
     */
    function pullNativeBalance(uint256 tokenId) external;

    /**
     * @notice Take the ether balance of the withdrawal address.
     * @param tokenId The ERC-721 id of the token.
     * @param target the account to send the ether to.
     */
    function pullNativeBalance(uint256 tokenId, address target) external;

    /**
     * @notice Take the ether balance of the withdrawal address.
     * @param tokenId The ERC-721 id of the token.
     * @param target the account to send the ether to.
     * @param data calldata to use for the transfer.
     */
    function pullNativeBalance(uint256 tokenId, address target, bytes calldata data) external;

    /**
     * @notice Perform an arbitrary EVM call from the withdrawal address.
     *   @dev the call value will be forwarded in the resulting call.
     * @param tokenId The ERC-721 id of the token.
     * @param target The contract to call.
     * @param data The calldata to use.
     */
    function arbitraryCall(uint256 tokenId, address target, bytes calldata data) external payable;
}
