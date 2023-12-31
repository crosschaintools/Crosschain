// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp} from "../Interfaces/IApp.sol";
import { IStargateRouter } from "../Interfaces/IStargateRouter.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { LibDiamond } from "../Libraries/LibDiamond.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { InformationMismatch, InvalidConfig, AlreadyInitialized, NotInitialized } from "../Errors/GenericErrors.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { LibMappings } from "../Libraries/LibMappings.sol";
import { Validatable } from "../Helpers/Validatable.sol";

/// @title Stargate Facet
/// @author Li.Finance (https://li.finance)
/// @notice Provides functionality for bridging through Stargate
contract StargateFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {
    /// Storage ///

    /// @notice The contract address of the stargate router on the source chain.
    IStargateRouter private immutable router;

    /// Types ///
    struct ChainIdConfig {
        uint256 chainId;
        uint16 layerZeroChainId;
    }

    /// @param srcPoolId Source pool id.
    /// @param dstPoolId Dest pool id.
    /// @param minAmountLD The min qty you would accept on the destination.
    /// @param dstGasForCall Additional gas fee for extral call on the destination.
    /// @param lzFee Estimated message fee.
    /// @param refundAddress Refund adddress. Extra gas (if any) is returned to this address
    /// @param callTo The address to send the tokens to on the destination.
    /// @param callData Additional payload.
    struct StargateData {
        uint256 srcPoolId;
        uint256 dstPoolId;
        uint256 minAmountLD;
        uint256 dstGasForCall;
        uint256 lzFee;
        address payable refundAddress;
        bytes callTo;
        bytes callData;
    }

    /// Errors ///

    error UnknownLayerZeroChain();
    error InvalidStargateRouter();

    /// Events ///

    event StargateInitialized(
        ChainIdConfig[] chainIdConfigs
    );

    event LayerZeroChainIdSet(
        uint256 indexed chainId,
        uint16 layerZeroChainId
    );

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _router The contract address of the stargate router on the source chain.
    constructor(IStargateRouter _router) {
        router = _router;
    }

    /// Init ///

    /// @notice Initialize local variables for the Stargate Facet
    /// @param chainIdConfigs Chain Id configuration data
    function initStargate(
        ChainIdConfig[] calldata chainIdConfigs
    ) external {
        LibDiamond.enforceIsContractOwner();

        LibMappings.StargateMappings storage sm = LibMappings
            .getStargateMappings();

        if (sm.initialized) {
            revert AlreadyInitialized();
        }

        for (uint256 i = 0; i < chainIdConfigs.length; i++) {
            sm.layerZeroChainId[chainIdConfigs[i].chainId] = chainIdConfigs[i]
                .layerZeroChainId;
        }

        sm.initialized = true;

        emit StargateInitialized(chainIdConfigs);
    }

    /// External Methods ///

    /// @notice Bridges tokens via Stargate Bridge
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _stargateData Data specific to Stargate Bridge
    function startBridgeTokensViaStargate(
        IApp.BridgeData memory _bridgeData,
        StargateData calldata _stargateData
    )
        external
        payable
        nonReentrant
        doesNotContainSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
        noNativeAsset(_bridgeData)
    {
        validateDestinationCallFlag(_bridgeData, _stargateData);
        _bridgeData.preBridgeAmount = LibAsset.depositAsset(
            _bridgeData.transactionId,
            _bridgeData.sendingAssetId,
            _bridgeData.preBridgeAmount,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
        _startBridge(_bridgeData, _stargateData);
    }

    /// @notice deposit and swap wrapper
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _swapData An array of swap related data for performing swaps before bridging
    /// @param _stargateData Data specific to Stargate Bridge
    function _depositAndSwapWrapper(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        StargateData calldata _stargateData
    )internal returns(uint256) {
        return _depositAndSwap(
            _bridgeData.transactionId,
            _bridgeData.preBridgeAmount,
            _swapData,
            payable(msg.sender),
            _stargateData.lzFee,
            true,
            _bridgeData.integratorFee,
            _bridgeData.integratorAddress
        );
    }

    /// @notice Performs a swap before bridging via Stargate Bridge
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _swapData An array of swap related data for performing swaps before bridging
    /// @param _stargateData Data specific to Stargate Bridge
    function swapAndStartBridgeTokensViaStargate(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        StargateData calldata _stargateData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        validateBridgeData(_bridgeData)
        noNativeAsset(_bridgeData)
    {
        validateDestinationCallFlag(_bridgeData, _stargateData);
        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(_bridgeData,_swapData,_stargateData);

        _startBridge(_bridgeData, _stargateData);
    }

    function quoteLayerZeroFee(
        uint256 _destinationChainId,
        StargateData calldata _stargateData
    ) external view returns (uint256, uint256) {
        return
            router.quoteLayerZeroFee(
                getLayerZeroChainId(_destinationChainId),
                1, // TYPE_SWAP_REMOTE on Bridge
                _stargateData.callTo,
                _stargateData.callData,
                IStargateRouter.lzTxObj(
                    _stargateData.dstGasForCall,
                    0,
                    toBytes(msg.sender)
                )
            );
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via Stargate Bridge
    /// @param _bridgeData Data used purely for tracking and analytics
    /// @param _stargateData Data specific to Stargate Bridge
    function _startBridge(
        IApp.BridgeData memory _bridgeData,
        StargateData calldata _stargateData
    ) private noNativeAsset(_bridgeData) {
        LibAsset.maxApproveERC20(IERC20(_bridgeData.sendingAssetId),
                                address(router),
                                _bridgeData.preBridgeAmount);

        router.swap{ value: _stargateData.lzFee }(
            getLayerZeroChainId(_bridgeData.destinationChainId),
            _stargateData.srcPoolId,
            _stargateData.dstPoolId,
            _stargateData.refundAddress,
            _bridgeData.preBridgeAmount,
            _stargateData.minAmountLD,
            IStargateRouter.lzTxObj(
                _stargateData.dstGasForCall,
                0,
                toBytes(0x0000000000000000000000000000000000000000)
            ),
            _stargateData.callTo,
            _stargateData.callData);

        emit TransferStarted(_bridgeData);
    }

    function validateDestinationCallFlag(
        IApp.BridgeData memory _bridgeData,
        StargateData calldata _stargateData
    ) private pure {
        if (
            (_stargateData.callData.length > 0) !=
            _bridgeData.hasDestinationCall
        ) {
            revert InformationMismatch();
        }
    }

    /// Mappings management ///

    /// @notice Sets the Layer 0 chain ID for a given chain ID
    /// @param _chainId uint16 of the chain ID
    /// @param _layerZeroChainId uint16 of the Layer 0 chain ID
    /// @dev This is used to map a chain ID to its Layer 0 chain ID
    function setLayerZeroChainId(uint256 _chainId, uint16 _layerZeroChainId)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibMappings.StargateMappings storage sm = LibMappings
            .getStargateMappings();

        if (!sm.initialized) {
            revert NotInitialized();
        }

        sm.layerZeroChainId[_chainId] = _layerZeroChainId;
        emit LayerZeroChainIdSet(_chainId, _layerZeroChainId);
    }

    /// @notice Gets the Layer 0 chain ID for a given chain ID
    /// @param _chainId uint256 of the chain ID
    /// @return uint16 of the Layer 0 chain ID
    function getLayerZeroChainId(uint256 _chainId)
        public
        view
        returns (uint16)
    {
        LibMappings.StargateMappings storage sm = LibMappings
            .getStargateMappings();
        uint16 chainId = sm.layerZeroChainId[_chainId];
        if (chainId == 0) revert UnknownLayerZeroChain();
        return chainId;
    }

    function toBytes(address _address) private pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            let m := mload(0x40)
            _address := and(
                _address,
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            )
            mstore(
                add(m, 20),
                xor(0x140000000000000000000000000000000000000000, _address)
            )
            mstore(0x40, add(m, 52))
            tempBytes := m
        }

        return tempBytes;
    }
}
