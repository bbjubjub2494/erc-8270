// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {DepositsBase} from "src/periphery/DepositsBase.sol";

import {IDepositContract} from "src/interfaces/IDepositContract.sol";
import {IERCXXXX} from "src/interfaces/IERCXXXX.sol";

/// @title ERC-XXXX: Deposit Helper
/// @author bbjubjub.eth
/// @notice Deposit helper for ERC-XXXX wrapped validators.
contract Deposits is DepositsBase {
    IDepositContract public immutable DEPOSIT_CONTRACT;

    constructor(IERCXXXX _ercxxxx, IDepositContract _depositContract) DepositsBase(_ercxxxx) {
        DEPOSIT_CONTRACT = _depositContract;
    }

    function protected(
        uint256 id,
        bool compounding,
        bytes calldata signature,
        bytes32 depositDataRoot,
        bytes32 expectedDepositRoot
    ) external payable {
        require(DEPOSIT_CONTRACT.get_deposit_root() == expectedDepositRoot, DepositRootMismatch());
        _deposit(id, compounding, signature, depositDataRoot);
    }

    function frontrunnable(uint256 id, bool compounding, bytes calldata signature, bytes32 depositDataRoot)
        external
        payable
    {
        _deposit(id, compounding, signature, depositDataRoot);
    }

    function topup(uint256 id) external payable {
        uint256 amount = msg.value;
        (
            bytes memory validatorKey,
            bytes memory withdrawalCredential,
            bytes memory signature,
            bytes32 depositDataRoot
        ) = _prepareTopup(id, amount / 1 gwei);
        DEPOSIT_CONTRACT.deposit{value: msg.value}(validatorKey, withdrawalCredential, signature, depositDataRoot);
    }

    function _deposit(uint256 id, bool compounding, bytes calldata signature, bytes32 depositDataRoot) private {
        address withdrawalAddress = ERCXXXX.withdrawalAddressOf(id);
        (bytes32 validatorKeyHi, bytes16 validatorKeyLo) = ERCXXXX.validatorKeyOf(id);
        bytes memory validatorKey = bytes.concat(validatorKeyHi, validatorKeyLo);
        bytes32 withdrawalCredential = _makeWithdrawalCredential(withdrawalAddress, compounding);
        DEPOSIT_CONTRACT.deposit{value: msg.value}(
            validatorKey, bytes.concat(withdrawalCredential), signature, depositDataRoot
        );
    }
}
