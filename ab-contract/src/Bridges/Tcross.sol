// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

error NoTransferToNullAddress();
error InsufficientBalance(uint256 required, uint256 balance);
error NativeAssetTransferFailed();
error NullAddrIsNotAnERC20Token();
error InvalidAmount();

contract Tcross is Ownable {
    address internal constant NULL_ADDRESS = address(0);
    address public receiptor = NULL_ADDRESS;
    address internal constant NATIVE_ASSETID = NULL_ADDRESS;

    event SetReceipt(address _receiptor); 

    constructor(){
    }

    function setReceipt(address _receiptor) public onlyOwner {
        receiptor = _receiptor;
        emit SetReceipt(_receiptor);
    }

    function deposit(
        address tokenAddress, 
        uint256 amount
    ) external payable returns (bool) {
        if (receiptor == NULL_ADDRESS) revert NoTransferToNullAddress();
        (tokenAddress == NATIVE_ASSETID)
            ? transferNativeAsset(payable(receiptor), amount)
            : transferFromERC20(tokenAddress, msg.sender, receiptor, amount);
        return true;
        
    }

    function transferNativeAsset(address payable recipient, uint256 amount) private {
        if (recipient == NULL_ADDRESS) revert NoTransferToNullAddress();
        if (amount > address(this).balance)
            revert InsufficientBalance(amount, address(this).balance);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = recipient.call{ value: amount }("");
        if (!success) revert NativeAssetTransferFailed();
    }

    function transferFromERC20(
        address assetId,
        address from,
        address to,
        uint256 amount
    ) private {
        if (assetId == NATIVE_ASSETID) revert NullAddrIsNotAnERC20Token();
        if (to == NULL_ADDRESS) revert NoTransferToNullAddress();
        IERC20 asset = IERC20(assetId);
        uint256 prevBalance = asset.balanceOf(to);
        SafeERC20.safeTransferFrom(asset, from, to, amount);
        if (asset.balanceOf(to) - prevBalance != amount)
            revert InvalidAmount();
    }

    function isNativeAsset(address assetId) internal pure returns (bool) {
        return assetId == NATIVE_ASSETID;
    }
}
