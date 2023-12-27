// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

contract Business {
	function deposit(address tokenAddr, uint256 amount) public {
		IERC20 token = IERC20(tokenAddr);
		token.transferFrom(msg.sender, address(this), amount);
	}
}

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address tokenOwner) external view returns (uint balance);
    function allowance(address tokenOwner, address spender) external view returns (uint remaining);
    function transfer(address to, uint tokens) external returns (bool success);
    function approve(address spender, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

