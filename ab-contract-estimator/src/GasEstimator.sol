// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract GasEstimator {
    // estimate gas excluding calldata cost using eth_call
    function estimate(
        address target, 
        bytes memory input, 
        uint value
    ) external returns (
        bool success, 
        uint gasConsumed,
        bytes memory returnData
    ) {

        uint initialGas = gasleft();
        (success, returnData) = target.call{value: value}(input);
        gasConsumed = initialGas - gasleft();
    }
}