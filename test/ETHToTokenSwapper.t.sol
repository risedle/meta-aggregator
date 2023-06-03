// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { IERC20Permit } from
  "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { ETHToTokenSwapper } from "src/ETHToTokenSwapper.sol";
import { AggregatorManager } from "src/AggregatorManager.sol";
import { ISwapper } from "src/ISwapper.sol";
import { SigUtils } from "./SigUtils.sol";

/// @dev Mock aggregator that receive ETH and transfer specified amount of
/// token to the msg.sender
contract Aggregator {
  using SafeERC20 for IERC20;

  function swap(address tokenOut, uint256 minAmountOut, uint256 refundAmount)
    external
    payable
  {
    IERC20(tokenOut).transfer(msg.sender, minAmountOut);
    (bool success,) = msg.sender.call{ value: refundAmount }("");
    require(success, "SWAP_FAILED");
  }

  receive() external payable { }
}

contract ETHToTokenSwapperTest is Test {
  using SafeERC20 for IERC20;

  function setUp() public {
    // Fork Mainnet
    vm.createSelectFork(vm.envString("ETH_RPC_URL"));
  }

  /// @dev Make sure it revert if aggregator is unregistered
  function testSwapETHToTokenWithUnregisteredAggregator() public {
    // Deploy contract
    ETHToTokenSwapper swapper = new ETHToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Set input
    address alice = address(101);
    address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 amountIn = 1e18;
    uint256 amountOut = 1e6;
    bytes memory data =
      abi.encodeWithSelector(Aggregator.swap.selector, tokenOut, amountOut); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice eth balance to swap
    vm.deal(alice, amountIn);

    // Do the swap
    vm.expectRevert(
      abi.encodeWithSelector(
        AggregatorManager.AggregatorInvalid.selector, aggregator
      )
    );
    swapper.swapETHToToken{ value: amountIn }(
      tokenOut, payable(address(aggregator)), data, amountOut
    );
  }

  /// @dev Make sure the accounting is correct
  function testSwapETHToTokenWithRegisteredAggregator() public {
    // Deploy contract
    ETHToTokenSwapper swapper = new ETHToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Register aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = address(101);
    address tokenOut = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 amountIn = 1e18;
    uint256 amountOut = 1e6;
    uint256 refundAmount = 100;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector, tokenOut, amountOut, refundAmount
    ); // call data

    // Top-up aggregator
    vm.store(
      tokenOut,
      keccak256(abi.encode(address(aggregator), 9)),
      bytes32(uint256(1e18))
    );

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice eth balance to swap
    vm.deal(alice, amountIn);
    assertEq(alice.balance, amountIn, "alice initial balance");

    // Do the swap
    swapper.swapETHToToken{ value: amountIn }(
      tokenOut, payable(address(aggregator)), data, amountOut
    );

    // Make sure alice receive USDC
    assertEq(IERC20(tokenOut).balanceOf(alice), 1e6, "alice not receive USDC");

    // Make sure ETH is refunded
    assertEq(alice.balance, 100, "alice eth is not refunded");

    // Make sure swapper deduct fee
    assertEq(address(swapper).balance, 1e15);
  }
}
