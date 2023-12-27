// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ITransactionManager } from "../Interfaces/ITransactionManager.sol";
import { IApp } from "../Interfaces/IApp.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { LibUtil } from "../Libraries/LibUtil.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { InvalidReceiver, InformationMismatch, InvalidFallbackAddress } from "../Errors/GenericErrors.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title NXTP (Connext) Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through NXTP (Connext)
contract NXTPFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The contract address of the transaction manager on the source chain.
    ITransactionManager private immutable txManager;

    /// Errors ///

    error InvariantDataMismatch(string message);

    /// Types ///

    struct NXTPData {
        ITransactionManager.InvariantTransactionData invariantData;
        uint256 expiry;
        bytes encryptedCallData;
        bytes encodedBid;
        bytes bidSignature;
        bytes encodedMeta;
    }

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _txManager The contract address of the transaction manager on the source chain.
    constructor(ITransactionManager _txManager) {
        txManager = _txManager;
    }

    /// External Methods ///

    /// @notice This function starts a cross-chain transaction using the NXTP protocol
    /// @param _bridgeData the core information needed for bridging
    /// @param _nxtpData data needed to complete an NXTP cross-chain transaction
    function startBridgeTokensViaNXTP(
        IApp.BridgeData memory _bridgeData,
        NXTPData calldata _nxtpData
    )
        external
        payable
        nonReentrant
        doesNotContainSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        if (hasDestinationCall(_nxtpData) != _bridgeData.hasDestinationCall) {
            revert InformationMismatch();
        }
        validateInvariantData(_nxtpData.invariantData, _bridgeData);
        _bridgeData.preBridgeAmount = LibAsset.depositAsset(
            _bridgeData.transactionId,
            _nxtpData.invariantData.sendingAssetId,
            _bridgeData.preBridgeAmount,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
        _startBridge(_bridgeData, _nxtpData);
    }

    /// @notice deposit and swap wrapper
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData array of data needed for swaps
    function _depositAndSwapWrapper(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData
    )internal returns(uint256) {
        return _depositAndSwap(
            _bridgeData.transactionId,
            _bridgeData.preBridgeAmount,
            _swapData,
            payable(msg.sender),
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
    }

    /// @notice This function performs a swap or multiple swaps and then starts a cross-chain transaction
    ///         using the NXTP protocol.
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData array of data needed for swaps
    /// @param _nxtpData data needed to complete an NXTP cross-chain transaction
    function swapAndStartBridgeTokensViaNXTP(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        NXTPData calldata _nxtpData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        if (hasDestinationCall(_nxtpData) != _bridgeData.hasDestinationCall) {
            revert InformationMismatch();
        }

        validateInvariantData(_nxtpData.invariantData, _bridgeData);
        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(
            _bridgeData,
            _swapData
        );
        _startBridge(_bridgeData, _nxtpData);
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via NXTP
    /// @param _bridgeData the core information needed for bridging
    /// @param _nxtpData data specific to NXTP
    function _startBridge(
        IApp.BridgeData memory _bridgeData,
        NXTPData memory _nxtpData
    ) private {
        IERC20 sendingAssetId = IERC20(_nxtpData.invariantData.sendingAssetId);
        // Give Connext approval to bridge tokens
        LibAsset.maxApproveERC20(
            IERC20(sendingAssetId),
            address(txManager),
            _bridgeData.preBridgeAmount
        );

        {
            address sendingChainFallback = _nxtpData
                .invariantData
                .sendingChainFallback;
            address receivingAddress = _nxtpData
                .invariantData
                .receivingAddress;

            if (LibUtil.isZeroAddress(sendingChainFallback)) {
                revert InvalidFallbackAddress();
            }
            if (LibUtil.isZeroAddress(receivingAddress)) {
                revert InvalidReceiver();
            }
        }

        // Initiate bridge transaction on sending chain
        txManager.prepare{
            value: LibAsset.isNativeAsset(address(sendingAssetId))
                ? _bridgeData.preBridgeAmount
                : 0
        }(
            ITransactionManager.PrepareArgs(
                _nxtpData.invariantData,
                _bridgeData.preBridgeAmount,
                _nxtpData.expiry,
                _nxtpData.encryptedCallData,
                _nxtpData.encodedBid,
                _nxtpData.bidSignature,
                _nxtpData.encodedMeta
            )
        );

        emit TransferStarted(_bridgeData);
    }

    function validateInvariantData(
        ITransactionManager.InvariantTransactionData calldata _invariantData,
        IApp.BridgeData memory _bridgeData
    ) private pure {
        if (_invariantData.sendingAssetId != _bridgeData.sendingAssetId) {
            revert InvariantDataMismatch("sendingAssetId");
        }
        if (_invariantData.receivingAddress != _bridgeData.receiver) {
            revert InvariantDataMismatch("receivingAddress");
        }
        if (
            _invariantData.receivingChainId != _bridgeData.destinationChainId
        ) {
            revert InvariantDataMismatch("receivingChainId");
        }
    }

    function hasDestinationCall(NXTPData memory _nxtpData)
        private
        pure
        returns (bool)
    {
        return _nxtpData.encryptedCallData.length > 0;
    }
}
