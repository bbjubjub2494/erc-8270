// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8;

import {IERC20} from "dependencies/forge-std-1.16.1/src/interfaces/IERC20.sol";

interface IERC677 is IERC20 {
    function transferAndCall(IERC677Receiver to, uint256 amount, bytes calldata data) external returns (bool success);

    event Transfer(address indexed, address indexed, uint256, bytes);
}

interface IERC677Receiver {
    function onTokenTransfer(address, uint256 amount, bytes calldata data) external returns (bool success);
}
