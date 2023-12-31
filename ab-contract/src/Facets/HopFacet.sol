// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp } from "../Interfaces/IApp.sol";
import { IHopBridge } from "../Interfaces/IHopBridge.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { LibDiamond } from "../Libraries/LibDiamond.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { InvalidConfig, AlreadyInitialized, NotInitialized } from "../Errors/GenericErrors.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title Hop Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Hop
contract HopFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    bytes32 internal constant NAMESPACE = keccak256("com.aggbridge.facets.hop");

    /// Types ///

    struct Storage {
        mapping(address => IHopBridge) bridges;
        bool initialized;
    }

    struct HopConfig {
        address assetId;
        address bridge;
    }

    struct HopData {
        uint256 bonderFee;
        uint256 amountOutMin;
        uint256 deadline;
        uint256 destinationAmountOutMin;
        uint256 destinationDeadline;
        address relayer;
        uint256 relayerFee;
        uint256 nativeFee;
    }

    /// Events ///

    event HopInitialized(HopConfig[] configs);
    event HopBridgeRegistered(address indexed assetId, address bridge);

    /// Init ///

    /// @notice Initialize local variables for the Hop Facet
    /// @param configs Bridge configuration data
    function initHop(HopConfig[] calldata configs) external {
        LibDiamond.enforceIsContractOwner();

        Storage storage s = getStorage();

        if (s.initialized) {
            revert AlreadyInitialized();
        }

        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].bridge == address(0)) {
                revert InvalidConfig();
            }
            s.bridges[configs[i].assetId] = IHopBridge(configs[i].bridge);
        }

        s.initialized = true;

        emit HopInitialized(configs);
    }

    /// External Methods ///

    /// @notice Register token and bridge
    /// @param assetId Address of token
    /// @param bridge Address of bridge for asset
    function registerBridge(address assetId, address bridge) external {
        LibDiamond.enforceIsContractOwner();

        Storage storage s = getStorage();

        if (!s.initialized) {
            revert NotInitialized();
        }

        if (bridge == address(0)) {
            revert InvalidConfig();
        }

        s.bridges[assetId] = IHopBridge(bridge);

        emit HopBridgeRegistered(assetId, bridge);
    }

    /// @notice Bridges tokens via Hop Protocol
    /// @param _bridgeData the core information needed for bridging
    /// @param _hopData data specific to Hop Protocol
    function startBridgeTokensViaHop(
        IApp.BridgeData memory _bridgeData,
        HopData calldata _hopData
    )
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
        _startBridge(_bridgeData, _hopData);
    }

    /// @notice deposit and swap wrapper
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    /// @param _hopData data specific to Hop Protocol
    function _depositAndSwapWrapper(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        HopData memory _hopData
    )internal returns(uint256) {
        return _depositAndSwap(
            _bridgeData.transactionId,
            _bridgeData.preBridgeAmount,
            _swapData,
            payable(msg.sender),
            _hopData.nativeFee,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
    }

    /// @notice Performs a swap before bridging via Hop Protocol
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    /// @param _hopData data specific to Hop Protocol
    function swapAndStartBridgeTokensViaHop(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        HopData memory _hopData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(
            _bridgeData,
            _swapData,
            _hopData
        );
        _startBridge(_bridgeData, _hopData);
    }

    /// private Methods ///

    /// @dev Contains the business logic for the bridge via Hop Protocol
    /// @param _bridgeData the core information needed for bridging
    /// @param _hopData data specific to Hop Protocol
    function _startBridge(
        IApp.BridgeData memory _bridgeData,
        HopData memory _hopData
    ) private {
        address sendingAssetId = _bridgeData.sendingAssetId;
        Storage storage s = getStorage();
        IHopBridge bridge = s.bridges[sendingAssetId];

        // Give Hop approval to bridge tokens
        LibAsset.maxApproveERC20(
            IERC20(sendingAssetId),
            address(bridge),
            _bridgeData.preBridgeAmount
        );

        uint256 value = LibAsset.isNativeAsset(address(sendingAssetId))
            ? _hopData.nativeFee + _bridgeData.preBridgeAmount
            : _hopData.nativeFee;

        if (block.chainid == 1 || block.chainid == 5) {
            // Ethereum L1
            bridge.sendToL2{ value: value }(
                _bridgeData.destinationChainId,
                _bridgeData.receiver,
                _bridgeData.preBridgeAmount,
                _hopData.destinationAmountOutMin,
                _hopData.destinationDeadline,
                _hopData.relayer,
                _hopData.relayerFee
            );
        } else {
            // L2
            // solhint-disable-next-line check-send-result
            bridge.swapAndSend{ value: value }(
                _bridgeData.destinationChainId,
                _bridgeData.receiver,
                _bridgeData.preBridgeAmount,
                _hopData.bonderFee,
                _hopData.amountOutMin,
                _hopData.deadline,
                _hopData.destinationAmountOutMin,
                _hopData.destinationDeadline
            );
        }
        emit TransferStarted(_bridgeData);
    }

    /// @dev fetch local storage
    function getStorage() private pure returns (Storage storage s) {
        bytes32 namespace = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
