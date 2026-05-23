// SPDX-License-Identifier: AGPL-3.0-only

// modified from Solmate

pragma solidity ^0.8;

import {IERC677, IERC677Receiver} from "src/interfaces/IERC677.sol";

// @notice This is a simple ERC677, standing in for the GNO token on Gnosis chains.
contract GnosisToken is IERC677 {
    error TransferRejected();

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    function name() public pure returns (string memory) {
        return "Mock Gnosis Token";
    }

    function symbol() public pure returns (string memory) {
        return "GNO";
    }

    uint8 public immutable decimals = 18;

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);

        return true;
    }

    function transferAndCall(IERC677Receiver to, uint256 amount, bytes calldata data) external returns (bool success) {
        if (!transfer(address(to), amount)) {
            return false;
        }
        emit IERC677.Transfer(msg.sender, address(to), amount, data);
        bool ok = to.onTokenTransfer(msg.sender, amount, data);
        require(ok, TransferRejected());
        return true;
    }
}
