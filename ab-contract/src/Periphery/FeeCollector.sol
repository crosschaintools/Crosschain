// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { LibAsset } from "../Libraries/LibAsset.sol";
import { TransferrableOwnership } from "../Helpers/TransferrableOwnership.sol";

/// @title Fee Collector
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for collecting integrator fees
contract FeeCollector is TransferrableOwnership {
    /// State ///

    // Integrator -> TokenAddress -> Balance
    mapping(address => mapping(address => uint256)) private _balances;
    // TokenAddress -> Balance
    mapping(address => uint256) private _platformBalances;
    uint256 private _platformFee = 0;

    /// Errors ///
    error TransferFailure();
    error NotEnoughNativeForFees();

    /// Events ///
    event FeesCollected(
        bytes32 indexed transactionId,
        address indexed _token,
        uint256 indexed _platformFee,
        address _integratorAddress,
        uint256 _integratorFee
    );
    event IntegratorFeesWithdrawn(
        address indexed _token,
        address indexed _to,
        uint256 _amount
    );
    event PlatformFeesWithdrawn(
        address indexed _token,
        address indexed _to,
        uint256 _amount
    );

    event PlatformFeeChanged(
        uint256 _fromValue,
        uint256 _toValue
    );

    /// Constructor ///

    constructor(address _owner) TransferrableOwnership(_owner) {}

    /// External Methods ///


    function setPlatformFee(uint256 _fee) external onlyOwner{
        require(_fee < 10000,"Invalid fee!");
        emit PlatformFeeChanged(_platformFee, _fee);
        _platformFee = _fee;
    }

    function getPlatformFee() public view returns(uint256){
        return _platformFee;
    }

    /// @notice Collects fees for the integrator
    /// @param tokenAddress address of the token to collect fees for
    /// @param orderAmount transaction amount of the order
    /// @param integratorFee ratio of fees to collect going to the integrator
    /// @param integratorAddress address of the integrator
    function collectTokenFees(
        bytes32 transactionId,
        address tokenAddress,
        uint256 orderAmount,
        uint256 integratorFee,
        address integratorAddress
    ) external returns (uint256) {
        if(integratorFee == 0 && _platformFee == 0){
            emit FeesCollected(
                transactionId,
                tokenAddress,
                0,
                integratorAddress,
                0
            );
            return orderAmount;
        }
        uint256 integratorFeeAmount = integratorFee * orderAmount / 10000;
        uint256 platformFeeAmount = _platformFee * orderAmount / 10000;
        require((integratorFeeAmount+platformFeeAmount) < orderAmount, "Fee overflow!");
        LibAsset.depositAsset(transactionId, tokenAddress, integratorFeeAmount+platformFeeAmount, false, 0, LibAsset.NULL_ADDRESS);
        _balances[integratorAddress][tokenAddress] += integratorFeeAmount;
        _platformBalances[tokenAddress] += platformFeeAmount;
        emit FeesCollected(
            transactionId,
            tokenAddress,
            platformFeeAmount,
            integratorAddress,
            integratorFeeAmount
        );
        return orderAmount - (integratorFeeAmount+platformFeeAmount);
    }

    /// @notice Collects fees for the integrator in native token
    /// @param integratorFee ratio of fees to collect going to the integrator
    /// @param integratorAddress address of the integrator
    function collectNativeFees(
        bytes32 transactionId,
        uint256 integratorFee,
        address integratorAddress
    ) external payable returns (uint256) {
        if(integratorFee == 0 && _platformFee == 0){
            emit FeesCollected(
                transactionId,
                LibAsset.NULL_ADDRESS,
                0,
                integratorAddress,
                0
            );
            (bool success, ) = payable(msg.sender).call{ value: msg.value}(
                ""
            );
            if (!success) {
                revert TransferFailure();
            }
            return msg.value;
        }
        uint256 integratorFeeAmount = integratorFee * msg.value / 10000;
        uint256 platformFeeAmount = _platformFee * msg.value / 10000;
        if (msg.value <= integratorFeeAmount + platformFeeAmount)
            revert NotEnoughNativeForFees();
        _balances[integratorAddress][LibAsset.NULL_ADDRESS] += integratorFeeAmount;
        _platformBalances[LibAsset.NULL_ADDRESS] += platformFeeAmount;
        uint256 remaining = msg.value - (integratorFeeAmount + platformFeeAmount);
        // Prevent extra native token from being locked in the contract
        if (remaining > 0) {
            (bool success, ) = payable(msg.sender).call{ value: remaining }(
                ""
            );
            if (!success) {
                revert TransferFailure();
            }
        }
        emit FeesCollected(
            transactionId,
            LibAsset.NULL_ADDRESS,
            platformFeeAmount,
            integratorAddress,
            integratorFeeAmount
        );
        return remaining;
    }

    /// @notice Withdraw fees and sends to the integrator
    /// @param tokenAddress address of the token to withdraw fees for
    function withdrawIntegratorFees(address tokenAddress, address toAddress, uint256 amount) external {
        uint256 balance = _balances[msg.sender][tokenAddress];
        require(amount <= balance, "Amount Exceeded!");
        if(LibAsset.NULL_ADDRESS == toAddress){
            toAddress = msg.sender;
        }
        if(0 == amount){
            amount = balance;
        }
        _balances[msg.sender][tokenAddress] -= amount;
        LibAsset.transferAsset(tokenAddress, payable(toAddress), amount);
        emit IntegratorFeesWithdrawn(tokenAddress, toAddress, amount);
    }

    /// @notice Batch withdraw fees and sends to the integrator
    /// @param tokenAddresses addresses of the tokens to withdraw fees for
    function batchWithdrawIntegratorFees(address[] memory tokenAddresses, address[] memory toAddresses, uint256[] memory amounts)
        external
    {
        uint256 length = tokenAddresses.length;
        uint256 balance;
        for (uint256 i = 0; i < length; ) {
            balance = _balances[msg.sender][tokenAddresses[i]];
            require(amounts[i] <= balance, "Amount Exceeded!");
            if(LibAsset.NULL_ADDRESS == toAddresses[i]){
                toAddresses[i] = msg.sender;
            }
            if(0 == amounts[i]){
                amounts[i] = balance;
            }
            _balances[msg.sender][tokenAddresses[i]] -= amounts[i];
            LibAsset.transferAsset(
                tokenAddresses[i],
                payable(toAddresses[i]),
                amounts[i]
            );
            emit IntegratorFeesWithdrawn(tokenAddresses[i], toAddresses[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Withdraws fees and sends to platform
    /// @param tokenAddress address of the token to withdraw fees for
    function withdrawPlatformFees(address tokenAddress, address toAddress, uint256 amount) external onlyOwner {
        uint256 balance = _platformBalances[tokenAddress];
        require(amount <= balance, "Amount Exceeded!");
        if(LibAsset.NULL_ADDRESS == toAddress){
            toAddress = msg.sender;
        }
        if(0 == amount){
            amount = balance;
        }
        _platformBalances[tokenAddress] -= amount;
        LibAsset.transferAsset(tokenAddress, payable(toAddress), amount);
        emit PlatformFeesWithdrawn(tokenAddress, toAddress, amount);
    }

    /// @notice Batch withdraws fees and sends to plaform
    /// @param tokenAddresses addresses of the tokens to withdraw fees for
    function batchWithdrawPlatformFees(address[] memory tokenAddresses, address[] memory toAddresses, uint256[] memory amounts)
        external
        onlyOwner
    {
        uint256 length = tokenAddresses.length;
        uint256 balance;
        for (uint256 i = 0; i < length; ) {
            balance = _platformBalances[tokenAddresses[i]];
            require(amounts[i] <= balance, "Amount Exceeded!");
            if(LibAsset.NULL_ADDRESS == toAddresses[i]){
                toAddresses[i] = msg.sender;
            }
            if(0 == amounts[i]){
                amounts[i] = balance;
            }
            _platformBalances[tokenAddresses[i]] -= amounts[i];
            LibAsset.transferAsset(
                tokenAddresses[i],
                payable(toAddresses[i]),
                amounts[i]
            );
            emit PlatformFeesWithdrawn(tokenAddresses[i], toAddresses[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the balance of the integrator
    /// @param integratorAddress address of the integrator
    /// @param tokenAddress address of the token to get the balance of
    function getTokenBalance(address integratorAddress, address tokenAddress)
        external
        view
        returns (uint256)
    {
        return _balances[integratorAddress][tokenAddress];
    }

    /// @notice Returns the balance of platform
    /// @param tokenAddress address of the token to get the balance of
    function getPlatformTokenBalance(address tokenAddress)
        external
        view
        returns (uint256)
    {
        return _platformBalances[tokenAddress];
    }

    /// @notice Returns the balance of the integrator
    /// @param integratorAddress address of the integrator
    /// @param tokenAddress address of the token to get the balance of
    function batchGetTokenBalance(address integratorAddress, address[] memory tokenAddress)
        external
        view
        returns (uint256[] memory amounts)
    {
        uint256 cnt = tokenAddress.length;
        amounts = new uint256[](cnt);
        for(uint256 i = 0; i < cnt; i++){
            amounts[i] = _balances[integratorAddress][tokenAddress[i]];
        }
    }

    /// @notice Returns the balance of platform
    /// @param tokenAddress address of the token to get the balance of
    function batchGetPlatformTokenBalance(address[] memory tokenAddress)
        external
        view
        returns (uint256[] memory amounts)
    {
        uint256 cnt = tokenAddress.length;
        amounts = new uint256[](cnt);
        for(uint256 i = 0; i < cnt; i++){
            amounts[i] = _platformBalances[tokenAddress[i]];
        }
    }
}
