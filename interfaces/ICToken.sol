// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "OpenZeppelin/openzeppelin-contracts@4.7.3/contracts/token/ERC20/IERC20.sol";

interface ICToken is IERC20 {
    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    function mint(uint256) external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function exchangeRateCurrent() external returns (uint);
}
