// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp } from "../Interfaces/IApp.sol";
import { IConnextHandler } from "../Interfaces/IConnextHandler.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { InformationMismatch } from "../Errors/GenericErrors.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title Amarok Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Connext Amarok
contract AmarokFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The contract address of the connext handler on the source chain.
    IConnextHandler private immutable connextHandler;

    /// @param callData The data to execute on the receiving chain. If no crosschain call is needed, then leave empty.
    /// @param callTo The address of the contract on dest chain that will receive bridged funds and execute data
    /// @param relayerFee The amount of relayer fee the tx called xcall with
    /// @param slippageTol Max bps of original due to slippage (i.e. would be 9995 to tolerate .05% slippage)
    /// @param delegate Destination delegate address
    /// @param destChainDomainId The Amarok-specific domainId of the destination chain
    struct AmarokData {
        bytes callData;
        address callTo;
        uint256 relayerFee;
        uint256 slippageTol;
        address delegate;
        uint32 destChainDomainId;
        bool payFeeWithSendingAsset;
    }

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _connextHandler The contract address of the connext handler on the source chain.
    constructor(IConnextHandler _connextHandler) {
        connextHandler = _connextHandler;
    }

    /// External Methods ///

    /// @notice Bridges tokens via Amarok
    /// @param _bridgeData Data containing core information for bridging
    /// @param _amarokData Data specific to bridge
    function startBridgeTokensViaAmarok(
        BridgeData memory _bridgeData,
        AmarokData calldata _amarokData
    )
        external
        payable
        nonReentrant
        doesNotContainSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
        noNativeAsset(_bridgeData)
    {
        if (hasDestinationCall(_amarokData) != _bridgeData.hasDestinationCall) {
            revert InformationMismatch();
        }

        _bridgeData.preBridgeAmount = LibAsset.depositAsset(
            _bridgeData.transactionId,
            _bridgeData.sendingAssetId,
            _bridgeData.preBridgeAmount,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
        _startBridge(_bridgeData, _amarokData);
    }

    /// @notice deposit and swap wrapper
    /// @param _bridgeData The core information needed for bridging
    /// @param _swapData An array of swap related data for performing swaps before bridging
    function _depositAndSwapWrapper(
        BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData
    ) internal returns (uint256) {
        return
            _depositAndSwap(
                _bridgeData.transactionId,
                _bridgeData.preBridgeAmount,
                _swapData,
                payable(msg.sender),
                true,
                _bridgeData.integratorFee,
                _bridgeData.integratorAddress
            );
    }

    /// @notice Performs a swap before bridging via Amarok
    /// @param _bridgeData The core information needed for bridging
    /// @param _swapData An array of swap related data for performing swaps before bridging
    /// @param _amarokData Data specific to Amarok
    function swapAndStartBridgeTokensViaAmarok(
        BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        AmarokData calldata _amarokData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
        noNativeAsset(_bridgeData)
    {
        if (hasDestinationCall(_amarokData) != _bridgeData.hasDestinationCall) {
            revert InformationMismatch();
        }

        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(_bridgeData, _swapData);
        _startBridge(_bridgeData, _amarokData);
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via Amarok
    /// @param _bridgeData The core information needed for bridging
    /// @param _amarokData Data specific to Amarok
    function _startBridge(
        BridgeData memory _bridgeData,
        AmarokData calldata _amarokData
    ) private {
        // give max approval for token to Amarok bridge, if not already
        LibAsset.maxApproveERC20(
            IERC20(_bridgeData.sendingAssetId),
            address(connextHandler),
            _bridgeData.preBridgeAmount
        );

        // initiate bridge transaction
        if (_amarokData.payFeeWithSendingAsset) {
            connextHandler.xcall(
                _amarokData.destChainDomainId,
                _amarokData.callTo,
                _bridgeData.sendingAssetId,
                _amarokData.delegate,
                _bridgeData.preBridgeAmount - _amarokData.relayerFee,
                _amarokData.slippageTol,
                _amarokData.callData,
                _amarokData.relayerFee
            );
        } else {
            connextHandler.xcall{ value: _amarokData.relayerFee }(
                _amarokData.destChainDomainId,
                _amarokData.callTo,
                _bridgeData.sendingAssetId,
                _amarokData.delegate,
                _bridgeData.preBridgeAmount,
                _amarokData.slippageTol,
                _amarokData.callData
            );
        }

        emit TransferStarted(_bridgeData);
    }

    function hasDestinationCall(
        AmarokData calldata _amarokData
    ) private pure returns (bool) {
        return _amarokData.callData.length > 0;
    }
}
