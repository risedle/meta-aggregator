// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { FeeCollector } from "src/FeeCollector.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";

contract FeeCollectorTest is Test {
  function setUp() public {
    // Fork Mainnet
    vm.createSelectFork(vm.envString("ETH_RPC_URL"));
  }

  /// @notice Make sure the owner can collect ETH fees
  function testCollectETHAsOwner() public {
    FeeCollector feeCollector = new FeeCollector();
    vm.deal(address(feeCollector), 2e18);
    address alice = address(101);
    feeCollector.collectETH(alice, 1e18);
    assertEq(
      address(feeCollector).balance, 1e18, "invalid collector ETHbalance"
    );
    assertEq(alice.balance, 1e18, "invalid alice ETH balance");
  }

  /// @notice Make sure the owner can collect token fees
  function testCollectTokenAsOwner() public {
    FeeCollector feeCollector = new FeeCollector();
    address token = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    vm.store(
      token,
      keccak256(abi.encode(address(feeCollector), 9)),
      bytes32(uint256(2e18))
    );

    address alice = address(101);
    feeCollector.collectToken(alice, token, 1e18);
    assertEq(
      IERC20(token).balanceOf(address(feeCollector)),
      1e18,
      "invalid collector Token balance"
    );
    assertEq(
      IERC20(token).balanceOf(alice), 1e18, "invalid alice Token balance"
    );
  }

  /// @notice Make sure non-owner cannot collect fees
  function testCollectAsNonOwner() public {
    FeeCollector feeCollector = new FeeCollector();
    address alice = address(101);
    address token = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    vm.startPrank(alice);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    feeCollector.collectETH(alice, 1e18);

    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    feeCollector.collectToken(alice, token, 1e18);
    vm.stopPrank();
  }
}
