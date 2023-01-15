// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol";

interface IWNative is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}
