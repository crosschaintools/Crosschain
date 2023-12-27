// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IApp } from "../Interfaces/IApp.sol";
import { IAcrossSpokePool } from "../Interfaces/IAcrossSpokePool.sol";
import { LibAsset } from "../Libraries/LibAsset.sol";
import { LibSwap } from "../Libraries/LibSwap.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { SwapperV2 } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title Across Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Across Protocol
contract AcrossFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The contract address of the spoke pool on the source chain.
    IAcrossSpokePool private immutable spokePool;

    /// @notice The WETH address on the current chain.
    address private immutable wrappedNative;

    /// Types ///

    /// @param relayerFeePct The relayer fee in token percentage with 18 decimals.
    /// @param quoteTimestamp The timestamp associated with the suggested fee.
    /// @param message Arbitrary data that can be used to pass additional information to the recipient along with the tokens.
    /// @param maxCount Used to protect the depositor from frontrunning to guarantee their quote remains valid.
    struct AcrossData {
        int64 relayerFeePct;
        uint32 quoteTimestamp;
        bytes message;
        uint256 maxCount;
    }

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _spokePool The contract address of the spoke pool on the source chain.
    /// @param _wrappedNative The address of the wrapped native token on the source chain.
    constructor(IAcrossSpokePool _spokePool, address _wrappedNative) {
        spokePool = _spokePool;
        wrappedNative = _wrappedNative;
    }

    /// External Methods ///

    /// @notice Bridges tokens via Across
    /// @param _bridgeData the core information needed for bridging
    /// @param _acrossData data specific to Across
    function startBridgeTokensViaAcross(
        IApp.BridgeData memory _bridgeData,
        AcrossData calldata _acrossData
    )
        external
        payable
        nonReentrant
        validateBridgeData(_bridgeData)
        doesNotContainSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
    {
        _bridgeData.preBridgeAmount = LibAsset.depositAsset(
            _bridgeData.transactionId,
            _bridgeData.sendingAssetId,
            _bridgeData.preBridgeAmount,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
        _startBridge(_bridgeData, _acrossData);
    }


    /// @notice deposit and swap wrapper
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    function _depositAndSwapWrapper(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData
    ) internal returns(uint256){
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

    /// @notice Performs a swap before bridging via Across
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    /// @param _acrossData data specific to Across
    function swapAndStartBridgeTokensViaAcross(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        AcrossData memory _acrossData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(_bridgeData, _swapData);
        _startBridge(_bridgeData, _acrossData);
    }

    /// Internal Methods ///

    /// @dev Contains the business logic for the bridge via Across
    /// @param _bridgeData the core information needed for bridging
    /// @param _acrossData data specific to Across
    function _startBridge(
        IApp.BridgeData memory _bridgeData,
        AcrossData memory _acrossData
    ) internal {
        bool isNative = _bridgeData.sendingAssetId == LibAsset.NATIVE_ASSETID;
        address sendingAsset = _bridgeData.sendingAssetId;
        if (isNative) sendingAsset = wrappedNative;
        else
            LibAsset.maxApproveERC20(
                IERC20(_bridgeData.sendingAssetId),
                address(spokePool),
                _bridgeData.preBridgeAmount
            );

        spokePool.deposit{ value: isNative ? _bridgeData.preBridgeAmount: 0 }(
            _bridgeData.receiver,
            sendingAsset,
            _bridgeData.preBridgeAmount,
            _bridgeData.destinationChainId,
            _acrossData.relayerFeePct,
            _acrossData.quoteTimestamp,
            _acrossData.message,
            _acrossData.maxCount
        );

        emit TransferStarted(_bridgeData);
    }

    receive() external payable {
    }
}
