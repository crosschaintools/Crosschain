// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp } from "../Interfaces/IApp.sol";
import { IHyphenRouter } from "../Interfaces/IHyphenRouter.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title Hyphen Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Hyphen
contract HyphenFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The contract address of the router on the source chain.
    IHyphenRouter private immutable router;

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _router The contract address of the router on the source chain.
    constructor(IHyphenRouter _router) {
        router = _router;
    }

    /// External Methods ///

    /// @notice Bridges tokens via Hyphen
    /// @param _bridgeData the core information needed for bridging
    function startBridgeTokensViaHyphen(IApp.BridgeData memory _bridgeData)
        external
        payable
        nonReentrant
        doesNotContainSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        _bridgeData.preBridgeAmount = LibAsset.depositAsset(
            _bridgeData.transactionId,
            _bridgeData.sendingAssetId,
            _bridgeData.preBridgeAmount,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
        _startBridge(_bridgeData);
    }

    /// @notice deposit and swap wrapper
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    function _depositAndSwapWrapper(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData
    ) internal returns(uint256) {
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

    /// @notice Performs a swap before bridging via Hyphen
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    function swapAndStartBridgeTokensViaHyphen(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(_bridgeData, _swapData);
        _startBridge(_bridgeData);
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via Hyphen
    /// @param _bridgeData the core information needed for bridging
    function _startBridge(IApp.BridgeData memory _bridgeData) private {
        if (!LibAsset.isNativeAsset(_bridgeData.sendingAssetId)) {
            // Give the Hyphen router approval to bridge tokens
            LibAsset.maxApproveERC20(
                IERC20(_bridgeData.sendingAssetId),
                address(router),
                _bridgeData.preBridgeAmount
            );

            router.depositErc20(
                _bridgeData.destinationChainId,
                _bridgeData.sendingAssetId,
                _bridgeData.receiver,
                _bridgeData.preBridgeAmount,
                "aggbridge"
            );
        } else {
            router.depositNative{ value: _bridgeData.preBridgeAmount}(
                _bridgeData.receiver,
                _bridgeData.destinationChainId,
                "aggbridge"
            );
        }

        emit TransferStarted(_bridgeData);
    }

    receive() external payable {
    }
}
