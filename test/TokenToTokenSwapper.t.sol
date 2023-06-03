// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { IERC20Permit } from
  "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { TokenToTokenSwapper } from "src/TokenToTokenSwapper.sol";
import { AggregatorManager } from "src/AggregatorManager.sol";
import { ISwapper } from "src/ISwapper.sol";
import { SigUtils } from "./SigUtils.sol";

/// @dev Mock aggregator that spend specified token and transfer specified amount
/// of token to the msg.sender
contract Aggregator {
  using SafeERC20 for IERC20;

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 tokenInAmount,
    uint256 minAmountOut
  ) external {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    IERC20(tokenOut).safeTransfer(msg.sender, minAmountOut);
  }

  /// @dev Spend token without giving back
  function maliciousSwap(address tokenIn, uint256 tokenInAmount) external {
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
  }

  receive() external payable { }
}

contract TokenToTokenSwapperTest is Test {
  using SafeERC20 for IERC20;

  function setUp() public {
    // Fork Mainnet
    vm.createSelectFork(vm.envString("ETH_RPC_URL"));
  }

  /// @dev Make sure it revert if aggregator is unregistered
  function testSwapTokenToTokenWithUnregisteredAggregator() public {
    // Deploy contract
    TokenToTokenSwapper swapper = new TokenToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address tokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 amountOut = 100 * 1e6;

    // NOTE: offchain component should doing this; fee deducted before swap
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector,
      tokenIn,
      tokenInAmount - 100000, // include fee to aggregrator
      amountOut
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
    swapper.swapTokenToToken(
      tokenIn,
      tokenOut,
      payable(address(aggregator)),
      data,
      tokenInAmount,
      amountOut
    );
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToTokenWithRegisteredAggregator() public {
    // Deploy contract
    TokenToTokenSwapper swapper = new TokenToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address tokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 totalFee = 100000;
    uint256 amountOut = 100 * 1e6;

    // NOTE: offchain component should doing this; fee deducted before swap
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector,
      tokenIn,
      tokenOut,
      tokenInAmount - totalFee, // include fee to aggregrator
      amountOut
    ); // call data

    // Fund the aggregator
    vm.store(
      tokenOut,
      keccak256(abi.encode(address(aggregator), 2)),
      bytes32(uint256(2e18))
    );
    assertEq(IERC20(tokenOut).balanceOf(address(aggregator)), 2e18);

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    swapper.swapTokenToToken(
      tokenIn,
      tokenOut,
      payable(address(aggregator)),
      data,
      tokenInAmount,
      amountOut
    );

    // Make sure alice receive correct amount of ETH
    // totalFee = 100000000 * 0.1% = 100000
    assertEq(
      IERC20(tokenOut).balanceOf(alice),
      amountOut,
      "invalid alice tokenOut balance"
    );
    assertEq(
      IERC20(tokenIn).balanceOf(address(swapper)),
      totalFee,
      "invalid swapper tokenIn balance"
    );

    assertEq(IERC20(tokenIn).balanceOf(alice), 0, "invalid alice USDC balance");
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToTokenWithRegisteredMaliciousAggregator() public {
    // Deploy contract
    TokenToTokenSwapper swapper = new TokenToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address tokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 amountOut = 100 * 1e6;
    uint256 totalFee = 100000;
    bytes memory data = abi.encodeWithSelector(
      Aggregator.maliciousSwap.selector, tokenIn, tokenInAmount - totalFee
    ); // call data

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    vm.expectRevert(abi.encodeWithSelector(ISwapper.AmountOutInvalid.selector));
    swapper.swapTokenToToken(
      tokenIn,
      tokenOut,
      payable(address(aggregator)),
      data,
      tokenInAmount,
      amountOut
    );
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToTokenWithRegisteredMaliciousAggregatorLessThanMinAmountOut(
  ) public {
    // Deploy contract
    TokenToTokenSwapper swapper = new TokenToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = address(101);
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address tokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 totalFee = 100000;
    uint256 amountOut = 100 * 1e6;

    // NOTE: offchain component should doing this; fee deducted before swap
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector,
      tokenIn,
      tokenOut,
      tokenInAmount - totalFee, // include fee to aggregrator
      amountOut - 10 * 1e6
    ); // call data

    // Fund the aggregator
    vm.store(
      tokenOut,
      keccak256(abi.encode(address(aggregator), 2)),
      bytes32(uint256(2e18))
    );
    assertEq(IERC20(tokenOut).balanceOf(address(aggregator)), 2e18);

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Approve swapper as token spender
    IERC20(tokenIn).safeApprove(address(swapper), tokenInAmount);

    // Do the swap
    vm.expectRevert(abi.encodeWithSelector(ISwapper.AmountOutInvalid.selector));
    swapper.swapTokenToToken(
      tokenIn,
      tokenOut,
      payable(address(aggregator)),
      data,
      tokenInAmount,
      amountOut
    );
  }

  function getPermit(
    address owner,
    address spender,
    address token,
    uint256 amount
  ) internal returns (uint8 v, bytes32 r, bytes32 s) {
    SigUtils.Permit memory permit = SigUtils.Permit({
      owner: owner,
      spender: spender,
      value: amount,
      nonce: 0,
      deadline: block.timestamp + 1 days
    });

    SigUtils sigUtils = new SigUtils(IERC20Permit(token).DOMAIN_SEPARATOR());
    bytes32 digest = sigUtils.getTypedDataHash(permit);

    (v, r, s) = vm.sign(0xA11CE, digest);
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToTokenWithPermit() public {
    // Deploy contract
    TokenToTokenSwapper swapper = new TokenToTokenSwapper();
    Aggregator aggregator = new Aggregator();

    // Register the aggregator
    swapper.register(address(aggregator));

    // Set input
    address alice = vm.addr(0xA11CE); // Must be exactly the same with getPermit()
    address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address tokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    uint256 tokenInAmount = 100 * 1e6; // 100 USDC
    uint256 totalFee = 100000;
    uint256 amountOut = 100 * 1e6;

    // NOTE: offchain component should doing this; fee deducted before swap
    bytes memory data = abi.encodeWithSelector(
      Aggregator.swap.selector,
      tokenIn,
      tokenOut,
      tokenInAmount - totalFee, // include fee to aggregrator
      amountOut
    ); // call data

    // Fund the aggregator
    vm.store(
      tokenOut,
      keccak256(abi.encode(address(aggregator), 2)),
      bytes32(uint256(2e18))
    );
    assertEq(IERC20(tokenOut).balanceOf(address(aggregator)), 2e18);

    // Start swap as alice
    vm.startPrank(alice);

    // Give alice tokenIn balance to swap
    vm.store(tokenIn, keccak256(abi.encode(alice, 9)), bytes32(tokenInAmount));
    assertEq(IERC20(tokenIn).balanceOf(alice), tokenInAmount);

    // Create permit values
    (uint8 v, bytes32 r, bytes32 s) =
      getPermit(alice, address(swapper), tokenIn, tokenInAmount);

    // Do the swap
    swapper.swapTokenToTokenWithPermit(
      tokenIn,
      tokenOut,
      payable(address(aggregator)),
      data,
      tokenInAmount,
      amountOut,
      block.timestamp + 1 days,
      v,
      r,
      s
    );

    // Check the balance

    assertEq(
      IERC20(tokenOut).balanceOf(alice),
      amountOut,
      "invalid alice tokenOut balance"
    );
    assertEq(
      IERC20(tokenIn).balanceOf(address(swapper)),
      totalFee,
      "invalid swapper tokenIn balance"
    );
  }
}
