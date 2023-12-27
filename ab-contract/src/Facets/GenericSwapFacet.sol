// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IApp } from "../Interfaces/IApp.sol";
import { LibAsset,IERC20 } from "../Libraries/LibAsset.sol";
import { ReentrancyGuard } from "../Helpers/ReentrancyGuard.sol";
import { SwapperV2, LibSwap } from "../Helpers/SwapperV2.sol";
import { Validatable } from "../Helpers/Validatable.sol";
import { LibUtil } from "../Libraries/LibUtil.sol";
import { InvalidReceiver } from "../Errors/GenericErrors.sol";

/// @title Generic Swap Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for swapping through ANY APPROVED DEX
/// @dev Uses calldata to execute APPROVED arbitrary methods on DEXs
contract GenericSwapFacet is IApp, ReentrancyGuard, SwapperV2, Validatable {

    struct TmpVariables {
        uint256 postSwapBalance;
        address receivingAssetId;
    }

    /// Storage ///
    
    /// External Methods ///

    /// @notice Performs multiple swaps in one transaction
    /// @param _transactionId the transaction id associated with the operation
    /// @param _integrator the name of the integrator
    /// @param _referrer the address of the referrer
    /// @param _receiver the address to receive the swapped tokens into (also excess tokens)
    /// @param _minAmount the minimum amount of the final asset to receive
    /// @param _integratorFee ratio of fees to collect going to the integrator
    /// @param _integratorAddress address of the integrator
    /// @param _swapData an object containing swap related data to perform swaps before bridging
    function swapTokensGeneric(
        bytes32 _transactionId,
        string calldata _integrator,
        string calldata _referrer,
        address payable _receiver,
        uint256 _minAmount,
        uint256 _integratorFee,
        address _integratorAddress,
        LibSwap.SwapData[] calldata _swapData
    ) external payable nonReentrant {
        if (LibUtil.isZeroAddress(_receiver)) {
            revert InvalidReceiver();
        }

        TmpVariables memory tmpVars;

        tmpVars.postSwapBalance = _depositAndSwap(
            _transactionId,
            _minAmount,
            _swapData,
            _receiver,
            true,
            _integratorFee,
            _integratorAddress
        );
        tmpVars.receivingAssetId = _swapData[_swapData.length - 1]
            .receivingAssetId;

        LibAsset.transferAsset(tmpVars.receivingAssetId, _receiver, tmpVars.postSwapBalance);

        emit GenericSwapCompleted(
            _transactionId,
            _integrator,
            _referrer,
            _receiver,
            _swapData[0].sendingAssetId,
            tmpVars.receivingAssetId,
            _swapData[0].fromAmount,
            tmpVars.postSwapBalance 
        );
    }
}
