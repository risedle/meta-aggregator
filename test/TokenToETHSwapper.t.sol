// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { IERC20Permit } from
  "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { TokenToETHSwapper } from "src/TokenToETHSwapper.sol";
import { AggregatorManager } from "src/AggregatorManager.sol";
import { ISwapper } from "src/ISwapper.sol";
import { SigUtils } from "./SigUtils.sol";

/// @dev Mock aggregator that spend specified token and transfer specified amount
/// of ETH to the msg.sender
contract Aggregator {
  using SafeERC20 for IERC20;

  function swap(address tokenIn, uint256 tokenInAmount, uint256 minAmountOut)
    external
  {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    (bool success,) = msg.sender.call{ value: minAmountOut }("");
    require(success, "SWAP_FAILED");
  }

  /// @dev Spend token without giving back
  function maliciousSwap(address tokenIn, uint256 tokenInAmount) external {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
  }

  receive() external payable { }
}

contract TokenToETHSwapperTest is Test {
  using SafeERC20 for IERC20;

  function setUp() public {
    // Fork Mainnet
    vm.createSelectFork(vm.envString("ETH_RPC_URL"));
  }

  /// @dev Make sure it revert if aggregator is unregistered
  function testSwapTokenToETHWithUnregisteredAggregator() public {
    // Deploy contract
    TokenToETHSwapper swapper = new TokenToETHSwapper();
    Aggregator aggregator = new Aggregator();

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 amountOut = 94986585;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector, tokenIn, tokenInAmount, amountOut
    ); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    vm.expectRevert(
      abi.encodeWithSelector(
        AggregatorManager.AggregatorInvalid.selector, aggregator
      )
    );
    swapper.swapTokenToETH(
      tokenIn, payable(address(aggregator)), data, tokenInAmount, amountOut
    );
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToETHWithRegisteredAggregator() public {
    // Deploy contract
    TokenToETHSwapper swapper = new TokenToETHSwapper();
    Aggregator aggregator = new Aggregator();

    // Fund the aggregator
    vm.deal(address(aggregator), 2e18);

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 amountOut = 94986585;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector, tokenIn, tokenInAmount, amountOut
    ); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    swapper.swapTokenToETH(
      tokenIn, payable(address(aggregator)), data, tokenInAmount, amountOut
    );

    // Make sure alice receive correct amount of ETH
    // totalFee = 94986585 * 0.1% = 94986.585
    uint256 totalFee = 94986;
    uint256 expectedAmount = 94986585 - totalFee;
    assertEq(alice.balance, expectedAmount, "invalid alice ETH balance");
    assertEq(address(swapper).balance, totalFee, "invalid swapper balance");

    assertEq(IERC20(tokenIn).balanceOf(alice), 0, "invalid alice USDC balance");
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToETHWithRegisteredMaliciousAggregator() public {
    // Deploy contract
    TokenToETHSwapper swapper = new TokenToETHSwapper();
    Aggregator aggregator = new Aggregator();

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 amountOut = 94986585;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.maliciousSwap.selector, tokenIn, tokenInAmount
    ); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    vm.expectRevert(abi.encodeWithSelector(ISwapper.ETHAmountInvalid.selector));
    swapper.swapTokenToETH(
      tokenIn, payable(address(aggregator)), data, tokenInAmount, amountOut
    );
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToETHWithRegisteredMaliciousAggregatorLessThanMinAmountOut(
  ) public {
    // Deploy contract
    TokenToETHSwapper swapper = new TokenToETHSwapper();
    Aggregator aggregator = new Aggregator();

    // Register the aggregator
    swapper.register(address(aggregator));

    // Fund the aggregator
    vm.deal(address(aggregator), 2e18);

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 minAmountOut = 94986585;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector, tokenIn, tokenInAmount, 64986585
    ); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    vm.expectRevert(abi.encodeWithSelector(ISwapper.ETHAmountInvalid.selector));
    swapper.swapTokenToETH(
      tokenIn, payable(address(aggregator)), data, tokenInAmount, minAmountOut
    );
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToETHWithPermit() public {
    // Deploy contract
    TokenToETHSwapper swapper = new TokenToETHSwapper();
    Aggregator aggregator = new Aggregator();

    // Fund the aggregator
    vm.deal(address(aggregator), 2e18);

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = vm.addr(0xA11CE);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 amountOut = 94986585;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector, tokenIn, tokenInAmount, amountOut
    ); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    vm.roll(17400012);

    // Create permit values
    SigUtils.Permit memory permit = SigUtils.Permit({
      owner: alice,
      spender: address(swapper),
      value: tokenInAmount,
      nonce: 0,
      deadline: block.timestamp + 1 days
    });

    SigUtils sigUtils = new SigUtils(IERC20Permit(tokenIn).DOMAIN_SEPARATOR());
    bytes32 digest = sigUtils.getTypedDataHash(permit);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);

    // Do the swap
    swapper.swapTokenToETHWithPermit(
      tokenIn,
      payable(address(aggregator)),
      data,
      tokenInAmount,
      amountOut,
      block.timestamp + 1 days,
      v,
      r,
      s
    );

    // Make sure alice receive correct amount of ETH
    // totalFee = 94986585 * 0.1% = 94986.585
    uint256 expectedAmount = 94986585 - 94986;
    assertEq(alice.balance, expectedAmount, "invalid alice ETH balance");
    assertEq(address(swapper).balance, 94986, "invalid swapper balance");

    assertEq(IERC20(tokenIn).balanceOf(alice), 0, "invalid alice USDC balance");
  }
}
