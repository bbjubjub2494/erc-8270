// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {DepositsBase} from "src/periphery/DepositsBase.sol";

import {IERC677} from "src/interfaces/IERC677.sol";
import {ISBCDepositContract} from "src/interfaces/ISBCDepositContract.sol";
import {IERC8270} from "src/interfaces/IERC8270.sol";

/// @title ERC8270: Deposit Helper — Gnosis variant
/// @author bbjubjub.eth
/// @notice Deposit helper for ERC-8270 wrapped validators.
contract DepositsGno is DepositsBase {
    IERC677 public immutable GNO_TOKEN;
    ISBCDepositContract public immutable DEPOSIT_CONTRACT;

    constructor(IERC8270 _erc8270, ISBCDepositContract _depositContract) DepositsBase(_erc8270) {
        DEPOSIT_CONTRACT = _depositContract;
        GNO_TOKEN = _depositContract.stake_token();
    }

    function protected(
        uint256 id,
        bool compounding,
        bytes calldata signature,
        bytes32 depositDataRoot,
        uint256 amount,
        bytes32 expectedDepositRoot
    ) external {
        require(DEPOSIT_CONTRACT.get_deposit_root() == expectedDepositRoot, DepositRootMismatch());
        _deposit(id, compounding, signature, depositDataRoot, amount);
    }

    function frontrunnable(
        uint256 id,
        bool compounding,
        bytes calldata signature,
        bytes32 depositDataRoot,
        uint256 amount
    ) external {
        _deposit(id, compounding, signature, depositDataRoot, amount);
    }

    function topup(uint256 id, uint256 amount) external {
        (
            bytes memory validatorKey,
            bytes memory withdrawalCredential,
            bytes memory signature,
            bytes32 depositDataRoot
        ) = _prepareTopup(id, 32 * amount / 1e9);

        _deposit(amount, bytes.concat(withdrawalCredential, validatorKey, signature, depositDataRoot));
    }

    function _deposit(uint256 id, bool compounding, bytes calldata signature, bytes32 depositDataRoot, uint256 amount)
        private
    {
        address withdrawalAddress = ERC8270.withdrawalAddressOf(id);
        (bytes32 validatorKeyHi, bytes16 validatorKeyLo) = ERC8270.validatorKeyOf(id);
        bytes memory validatorKey = bytes.concat(validatorKeyHi, validatorKeyLo);
        bytes32 withdrawalCredential = _makeWithdrawalCredential(withdrawalAddress, compounding);
        _deposit(amount, bytes.concat(withdrawalCredential, validatorKey, signature, depositDataRoot));
    }

    function _deposit(uint256 amount, bytes memory depositData) private {
        require(GNO_TOKEN.transferFrom(msg.sender, address(this), amount));
        require(GNO_TOKEN.transferAndCall(DEPOSIT_CONTRACT, amount, depositData));
    }
}
