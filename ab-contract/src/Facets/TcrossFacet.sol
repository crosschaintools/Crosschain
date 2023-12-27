// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp } from "../Interfaces/IApp.sol";
import { ITcrossBridge } from "../Interfaces/ITcrossBridge.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { Validatable } from "../Helpers/Validatable.sol";

contract TcrossFacet is IApp, ReentrancyGuard, Validatable {


    /// Types ///

    struct TcrossData {
        uint256 toAmount;
    }

    /// Storage ///

    /// @notice The contract address of the connext handler on the source chain.
    ITcrossBridge private immutable bridge;

    /// Events ///

    event TcrossStarted(bytes32 indexed transactionId, TcrossData _tcorssData);

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _bridge The contract address of the bridge on the source chain.
    constructor(ITcrossBridge _bridge) {
        bridge = _bridge;
    }

    /// External Methods ///

    /// @notice Bridges tokens via Tcross
    /// @param _bridgeData Data containing core information for bridging
    function startBridgeTokensViaTcross(
        BridgeData memory _bridgeData,
        TcrossData memory _tcorssData
    )
        external
        payable
        nonReentrant
        doesNotContainSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
        noNativeAsset(_bridgeData)
    {
        _bridgeData.preBridgeAmount = LibAsset.depositAsset(
            _bridgeData.transactionId,
            _bridgeData.sendingAssetId,
            _bridgeData.preBridgeAmount,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
        _startBridge(_bridgeData, _tcorssData);
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via Amarok
    /// @param _bridgeData The core information needed for bridging
    function _startBridge(
        BridgeData memory _bridgeData,
        TcrossData memory _tcorssData
    ) private {
        bool isNative = _bridgeData.sendingAssetId == LibAsset.NATIVE_ASSETID;
        if(!isNative){
            // give max approval for token to Tcross bridge, if not already
            LibAsset.maxApproveERC20(
                IERC20(_bridgeData.sendingAssetId),
                address(bridge),
                _bridgeData.preBridgeAmount
            );
        }

        bridge.deposit{ value: isNative ? _bridgeData.preBridgeAmount: 0 }(
           _bridgeData.sendingAssetId,
           _bridgeData.preBridgeAmount
        );

        emit TransferStarted(_bridgeData);
        emit TcrossStarted(_bridgeData.transactionId, _tcorssData);
    }

    receive() external payable {
    }
}
