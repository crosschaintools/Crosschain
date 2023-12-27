// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp } from "../Interfaces/IApp.sol";
import { LibAsset, IERC20 } from "../Libraries/LibAsset.sol";
import { LibDiamond } from "../Libraries/LibDiamond.sol";
import { IMultichainRouter } from "../Interfaces/IMultichainRouter.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { InvalidConfig, AlreadyInitialized, NotInitialized } from "../Errors/GenericErrors.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";

interface IMultichainERC20 {
    function Swapout(uint256 amount, address bindaddr) external returns (bool);
    function proxyToken() external returns (address);
}

/// @title Multichain Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Multichain (Prev. AnySwap)
contract MultichainFacet is IApp, SwapperV2, ReentrancyGuard, Validatable {
    /// Storage ///

    bytes32 internal constant NAMESPACE =
        keccak256("com.aggbridge.facets.multichain");

    /// Types ///

    struct Storage {
        mapping(address => bool) allowedRouters;
        bool initialized; // no longer used but kept here to maintain the same storage layout
        address anyNative;
        mapping(address => address) anyTokenAddresses;
    }

    struct MultichainData {
        address router;
    }

    struct AnyMapping {
        address tokenAddress;
        address anyTokenAddress;
    }

    /// Errors ///

    error InvalidRouter(address router);

    /// Events ///

    event MultichainInitialized();
    event MultichainRoutersUpdated(address[] routers, bool[] allowed);
    event AnyMappingUpdated(AnyMapping[] mappings);

    function tmpFuncForMultichainStruct(AnyMapping memory arg,LibSwap.SwapData calldata _swapData) external {
    }

    /// Init ///

    /// @notice Initialize local variables for the Multichain Facet
    /// @param anyNative The address of the anyNative (e.g. anyETH) token
    /// @param routers Allowed Multichain Routers
    function initMultichain(address anyNative, address[] calldata routers)
        external
    {
        LibDiamond.enforceIsContractOwner();

        Storage storage s = getStorage();

        s.anyNative = anyNative;

        uint256 len = routers.length;
        for (uint256 i = 0; i < len; ) {
            if (routers[i] == address(0)) {
                revert InvalidConfig();
            }
            s.allowedRouters[routers[i]] = true;
            unchecked {
                ++i;
            }
        }

        emit MultichainInitialized();
    }

    /// External Methods ///

    /// @notice Updates the tokenAddress > anyTokenAddress storage
    /// @param mappings A mapping of tokenAddress(es) to anyTokenAddress(es)
    function updateAddressMappings(AnyMapping[] calldata mappings) external {
        LibDiamond.enforceIsContractOwner();

        Storage storage s = getStorage();

        for (uint64 i; i < mappings.length; ) {
            s.anyTokenAddresses[mappings[i].tokenAddress] = mappings[i]
                .anyTokenAddress;
            unchecked {
                ++i;
            }
        }

        emit AnyMappingUpdated(mappings);
    }

    /// @notice (Batch) register routers
    /// @param routers Router addresses
    /// @param allowed Array of whether the addresses are allowed or not
    function registerRouters(
        address[] calldata routers,
        bool[] calldata allowed
    ) external {
        LibDiamond.enforceIsContractOwner();

        Storage storage s = getStorage();

        uint256 len = routers.length;
        for (uint256 i = 0; i < len; ) {
            if (routers[i] == address(0)) {
                revert InvalidConfig();
            }
            s.allowedRouters[routers[i]] = allowed[i];

            unchecked {
                ++i;
            }
        }
        emit MultichainRoutersUpdated(routers, allowed);
    }

    /// @notice Bridges tokens via Multichain
    /// @param _bridgeData the core information needed for bridging
    /// @param _multichainData data specific to Multichain
    function startBridgeTokensViaMultichain(
        IApp.BridgeData memory _bridgeData,
        MultichainData calldata _multichainData
    )
        external
        payable
        nonReentrant
        doesNotContainSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        Storage storage s = getStorage();
        if (!s.allowedRouters[_multichainData.router]) revert InvalidRouter(_multichainData.router);
        if (!LibAsset.isNativeAsset(_bridgeData.sendingAssetId))
            _bridgeData.preBridgeAmount = LibAsset.depositAsset(
                _bridgeData.transactionId,
                _bridgeData.sendingAssetId,
                _bridgeData.preBridgeAmount,
                true,
                _bridgeData.integratorFee,
                _bridgeData.integratorAddress
            );

        _startBridge(_bridgeData, _multichainData);
    }

    /// @notice deposit and swap wrapper
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
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

    /// @notice Performs a swap before bridging via Multichain
    /// @param _bridgeData the core information needed for bridging
    /// @param _swapData an array of swap related data for performing swaps before bridging
    /// @param _multichainData data specific to Multichain
    function swapAndStartBridgeTokensViaMultichain(
        IApp.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        MultichainData memory _multichainData
    )
        external
        payable
        nonReentrant
        containsSourceSwaps(_bridgeData)
        doesNotContainDestinationCalls(_bridgeData)
        validateBridgeData(_bridgeData)
    {
        Storage storage s = getStorage();

        if (!s.allowedRouters[_multichainData.router]) revert InvalidRouter(_multichainData.router);

        _bridgeData.preBridgeAmount = _depositAndSwapWrapper(_bridgeData, _swapData);
        _startBridge(_bridgeData, _multichainData);
    }

    /// Private Methods ///

    /// @dev Contains the business logic for the bridge via Multichain
    /// @param _bridgeData the core information needed for bridging
    /// @param _multichainData data specific to Multichain
    function _startBridge(
        IApp.BridgeData memory _bridgeData,
        MultichainData memory _multichainData
    ) private {
        // check if sendingAsset is a Multichain token that needs to be called directly in order to bridge it
        if (_multichainData.router == _bridgeData.sendingAssetId) {
            IMultichainERC20(_bridgeData.sendingAssetId).Swapout(
                _bridgeData.preBridgeAmount,
                _bridgeData.receiver
            );
        } else {
            Storage storage s = getStorage();
            if (LibAsset.isNativeAsset(_bridgeData.sendingAssetId)) {
                // call native asset bridge function
                IMultichainRouter(_multichainData.router).anySwapOutNative{
                    value: _bridgeData.preBridgeAmount
                }(
                    s.anyNative,
                    _bridgeData.receiver,
                    _bridgeData.destinationChainId
                );
            } else {
                // Give Multichain router approval to pull tokens
                LibAsset.maxApproveERC20(
                    IERC20(_bridgeData.sendingAssetId),
                    _multichainData.router,
                    _bridgeData.preBridgeAmount
                );
                // replace tokenAddress with anyTokenAddress (if mapping found) and call ERC20 asset bridge function
                IMultichainRouter(_multichainData.router).anySwapOutUnderlying(
                        s.anyTokenAddresses[_bridgeData.sendingAssetId] !=
                            address(0)
                            ? s.anyTokenAddresses[_bridgeData.sendingAssetId]
                            : _bridgeData.sendingAssetId,
                        _bridgeData.receiver,
                        _bridgeData.preBridgeAmount,
                        _bridgeData.destinationChainId
                    );
            }
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

    receive() external payable {
    }
}
