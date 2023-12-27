// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { LibAsset } from "../Libraries/LibAsset.sol";
import { LibUtil } from "../Libraries/LibUtil.sol";
import { InvalidReceiver, InformationMismatch, InvalidSendingToken, InvalidAmount, NativeAssetNotSupported, InvalidDestinationChain, CannotBridgeToSameNetwork } from "../Errors/GenericErrors.sol";
import { IApp } from "../Interfaces/IApp.sol";
import { LibSwap } from "../Libraries/LibSwap.sol";

contract Validatable {
    modifier validateBridgeData(IApp.BridgeData memory _bridgeData) {
        if (LibUtil.isZeroAddress(_bridgeData.receiver)) {
            revert InvalidReceiver();
        }
        if (_bridgeData.preBridgeAmount == 0) {
            revert InvalidAmount();
        }
        if (_bridgeData.destinationChainId == block.chainid) {
            revert CannotBridgeToSameNetwork();
        }
        _;
    }

    modifier noNativeAsset(IApp.BridgeData memory _bridgeData) {
        if (LibAsset.isNativeAsset(_bridgeData.sendingAssetId)) {
            revert NativeAssetNotSupported();
        }
        _;
    }

    modifier onlyAllowSourceToken(
        IApp.BridgeData memory _bridgeData,
        address _token
    ) {
        if (_bridgeData.sendingAssetId != _token) {
            revert InvalidSendingToken();
        }
        _;
    }

    modifier onlyAllowDestinationChain(
        IApp.BridgeData memory _bridgeData,
        uint256 _chainId
    ) {
        if (_bridgeData.destinationChainId != _chainId) {
            revert InvalidDestinationChain();
        }
        _;
    }

    modifier containsSourceSwaps(IApp.BridgeData memory _bridgeData) {
        if (!_bridgeData.hasSourceSwaps) {
            revert InformationMismatch();
        }
        _;
    }

    modifier doesNotContainSourceSwaps(IApp.BridgeData memory _bridgeData) {
        if (_bridgeData.hasSourceSwaps) {
            revert InformationMismatch();
        }
        _;
    }

    modifier doesNotContainDestinationCalls(
        IApp.BridgeData memory _bridgeData
    ) {
        if (_bridgeData.hasDestinationCall) {
            revert InformationMismatch();
        }
        _;
    }
}
