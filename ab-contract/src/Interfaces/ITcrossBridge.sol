// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITcrossBridge{
    function deposit(
        address tokenAddress,
        uint256 amount
    ) external payable returns (bool);
    
}
