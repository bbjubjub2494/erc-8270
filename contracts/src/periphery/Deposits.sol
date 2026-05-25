// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {DepositsBase} from "src/periphery/DepositsBase.sol";

import {IDepositContract} from "src/interfaces/IDepositContract.sol";
import {IERC8270} from "src/interfaces/IERC8270.sol";

/// @title ERC-8270: Deposit Helper
/// @author bbjubjub.eth
/// @notice Deposit helper for ERC-8270 wrapped validators.
contract Deposits is DepositsBase {
    IDepositContract public immutable DEPOSIT_CONTRACT;

    constructor(IERC8270 _erc8270, IDepositContract _depositContract) DepositsBase(_erc8270) {
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
        address withdrawalAddress = ERC8270.withdrawalAddressOf(id);
        (bytes32 validatorKeyHi, bytes16 validatorKeyLo) = ERC8270.validatorKeyOf(id);
        bytes memory validatorKey = bytes.concat(validatorKeyHi, validatorKeyLo);
        bytes32 withdrawalCredential = _makeWithdrawalCredential(withdrawalAddress, compounding);
        DEPOSIT_CONTRACT.deposit{value: msg.value}(
            validatorKey, bytes.concat(withdrawalCredential), signature, depositDataRoot
        );
    }
}
