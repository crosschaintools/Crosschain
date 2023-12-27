// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import { DSTest } from "ds-test/test.sol";
import { console } from "../utils/Console.sol";
import { Vm } from "forge-std/Vm.sol";
import { FeeCollector } from "app/Periphery/FeeCollector.sol";
import { TestToken as ERC20 } from "../utils/TestToken.sol";

contract FeeCollectorTest is DSTest {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);
    FeeCollector private feeCollector;
    ERC20 private feeToken;

    function setUp() public {
        feeCollector = new FeeCollector(address(this));
        feeToken = new ERC20("TestToken", "TST", 18);
        feeToken.mint(address(this), 100_000 ether);
        vm.deal(address(0xb33f), 100 ether);
        vm.deal(address(0xb0b), 100 ether);
    }

    // Needed to receive ETH
    receive() external payable {}

    function testCanCollectTokenFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;

        // Act
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );

        // Assert
        assert(
            feeToken.balanceOf(address(feeCollector)) ==
                integratorFee + fee
        );
        assert(
            feeCollector.getTokenBalance(address(0xb33f), address(feeToken)) ==
                integratorFee
        );
        assert(feeCollector.getPlatformTokenBalance(address(feeToken)) == fee);
    }

    function testCanCollectNativeFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;

        // Act
        feeCollector.collectNativeFees{ value: integratorFee + fee }(
            bytes32(0),
            integratorFee,
            address(0xb33f)
        );

        // Assert
        assert(address(feeCollector).balance == integratorFee + fee);
        assert(
            feeCollector.getTokenBalance(address(0xb33f), address(0)) ==
                integratorFee
        );
        assert(feeCollector.getPlatformTokenBalance(address(0)) == fee);
    }

    function testCanWithdrawIntegratorFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );

        // Act
        vm.prank(address(0xb0b));
        feeCollector.withdrawIntegratorFees(address(feeToken),address(0),0);
        vm.prank(address(0xb33f));
        feeCollector.withdrawIntegratorFees(address(feeToken),address(0),0);

        // Assert
        assert(feeToken.balanceOf(address(0xb33f)) == 1 ether);
        assert(feeToken.balanceOf(address(0xb0b)) == 0 ether);
        assert(feeToken.balanceOf(address(feeCollector)) == 0.015 ether);
    }

    function testCanWithdrawPlatformFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );
        uint256 startingBalance = feeToken.balanceOf(address(this));

        // Act
        feeCollector.withdrawPlatformFees(address(feeToken),address(0),0);

        // Assert
        assert(
            feeToken.balanceOf(address(this)) == 0.015 ether + startingBalance
        );
        assert(feeToken.balanceOf(address(feeCollector)) == 1 ether);
    }

    function testCanBatchWithdrawIntegratorFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );
        feeCollector.collectNativeFees{ value: integratorFee + fee }(
            bytes32(0),
            integratorFee,
            address(0xb33f)
        );

        // Act
        address[] memory tokens = new address[](2);
        tokens[0] = address(feeToken);
        tokens[1] = address(0);
        address[] memory toAddrs = new address[](2);
        toAddrs[0] = address(0);
        toAddrs[1] = address(0);
        uint256[] memory amounts= new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        uint256 preBalanceB33f = address(0xb33f).balance;
        vm.prank(address(0xb33f));
        feeCollector.batchWithdrawIntegratorFees(tokens,toAddrs,amounts);

        // Assert
        assert(feeToken.balanceOf(address(0xb33f)) == 1 ether);
        assert(feeToken.balanceOf(address(feeCollector)) == 0.015 ether);
        assert(address(0xb33f).balance == 1 ether + preBalanceB33f);
        assert(address(feeCollector).balance == 0.015 ether);
    }

    function testCanBatchWithdrawPlatformFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );
        feeCollector.collectNativeFees{ value: integratorFee + fee }(
            bytes32(0),
            integratorFee,
            address(0xb33f)
        );
        uint256 startingTokenBalance = feeToken.balanceOf(address(this));
        uint256 startingETHBalance = address(this).balance;

        // Act
        address[] memory tokens = new address[](2);
        tokens[0] = address(feeToken);
        tokens[1] = address(0);
        address[] memory toAddrs = new address[](2);
        toAddrs[0] = address(0);
        toAddrs[1] = address(0);
        uint256[] memory amounts= new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        feeCollector.batchWithdrawPlatformFees(tokens,toAddrs,amounts);

        // Assert
        assert(
            feeToken.balanceOf(address(this)) ==
                0.015 ether + startingTokenBalance
        );
        assert(address(this).balance == 0.015 ether + startingETHBalance);
        assert(address(feeCollector).balance == 1 ether);
        assert(feeToken.balanceOf(address(feeCollector)) == 1 ether);
    }

    function testFailWhenNonOwnerAttemptsToWithdrawPlatformFees() public {
        // Arrange
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );

        // Act
        vm.prank(address(0xb33f));
        feeCollector.withdrawPlatformFees(address(feeToken),address(0),0);
    }

    function testFailWhenNonOwnerAttemptsToBatchWithdrawPlatformFees() public {
        // Arranges.newOwner
        uint256 integratorFee = 1 ether;
        uint256 fee = 0.015 ether;
        feeToken.approve(address(feeCollector), integratorFee + fee);
        feeCollector.collectTokenFees(
            bytes32(0),
            address(feeToken),
            integratorFee,
            fee,
            address(0xb33f)
        );
        feeCollector.collectNativeFees{ value: integratorFee + fee }(
            bytes32(0),
            integratorFee,
            address(0xb33f)
        );

        // Act
        address[] memory tokens = new address[](2);
        tokens[0] = address(feeToken);
        tokens[1] = address(0);
        address[] memory toAddrs = new address[](2);
        toAddrs[0] = address(0);
        toAddrs[1] = address(0);
        uint256[] memory amounts= new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        vm.prank(address(0xb33f));
        feeCollector.batchWithdrawPlatformFees(tokens,toAddrs,amounts);
    }

    function testOwnerCanTransferOwnership() public {
        address newOwner = address(0x1234567890123456789012345678901234567890);
        feeCollector.transferOwnership(newOwner);
        assert(feeCollector.owner() != newOwner);
        vm.startPrank(newOwner);
        feeCollector.confirmOwnershipTransfer();
        assert(feeCollector.owner() == newOwner);
        vm.stopPrank();
    }

    function testFailNonOwnerCanTransferOwnership() public {
        address newOwner = address(0x1234567890123456789012345678901234567890);
        assert(feeCollector.owner() != newOwner);
        vm.prank(newOwner);
        feeCollector.transferOwnership(newOwner);
    }

    function testFailOnwershipTransferToNullAddr() public {
        address newOwner = address(0x0);
        feeCollector.transferOwnership(newOwner);
    }

    function testFailOwnerCanConfirmPendingOwnershipTransfer() public {
        address newOwner = address(0x1234567890123456789012345678901234567890);
        feeCollector.transferOwnership(newOwner);
        feeCollector.confirmOwnershipTransfer();
    }

    function testFailOwnershipTransferToSelf() public {
        address newOwner = address(this);
        feeCollector.transferOwnership(newOwner);
    }
}
