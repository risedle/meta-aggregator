// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { IERC20Permit } from
  "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

import { ISwapper } from "./ISwapper.sol";
import { AggregatorManager } from "./AggregatorManager.sol";
import { FeeCollector } from "./FeeCollector.sol";

contract ETHToTokenSwapper is ISwapper, AggregatorManager, FeeCollector {
  using SafeERC20 for IERC20;
  using Math for uint256;

  /**
   * @notice Swap ETH to token
   * @param tokenOut The output token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenOutMinAmount The min amount of output token
   */
  function swapETHToToken(
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenOutMinAmount
  ) external payable onlyRegisteredAggregator(aggregator) {
    _swapETHToToken(tokenOut, aggregator, data, tokenOutMinAmount);
  }

  /**
   * @dev Implementation of swapETHToToken via specified aggregator.
   *
   * Here is step by step:
   * 1. Transfer the tokenIn to the contract
   * 2. Approve aggregator to spend the tokenIn
   * 3. Call the aggregator contract with specified call data. Call data should
   *    take account that only amountIn - fee is send to the aggregrator.
   * 4. Perform double check such as allowance
   * 5. Send tokenOut and ETH refund to the user, if any
   *
   */
  function _swapETHToToken(
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenOutMinAmount
  ) internal {
    if (msg.value == 0) revert AmountInInvalid();
    uint256 tokenBalanceBeforeSwap = IERC20(tokenOut).balanceOf(address(this));
    uint256 ethBalanceBeforeSwap = address(this).balance - msg.value;

    uint256 feeAmount = FEE.mulDiv(msg.value, 1e18, Math.Rounding.Down);
    (bool success,) = aggregator.call{ value: msg.value - feeAmount }(data);
    if (!success) revert SwapViaAggregatorFailed(aggregator);

    // Double check
    uint256 tokenBalanceAfterSwap = IERC20(tokenOut).balanceOf(address(this));
    if (tokenBalanceAfterSwap < tokenBalanceBeforeSwap) {
      revert AmountOutInvalid();
    }
    uint256 ethBalanceAfterSwap = address(this).balance;
    uint256 amountOut = tokenBalanceAfterSwap - tokenBalanceBeforeSwap;
    if (amountOut == 0 || amountOut < tokenOutMinAmount) {
      revert AmountOutInvalid();
    }

    // Send Token to the user
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

    // Send refund if any
    if (ethBalanceAfterSwap > (ethBalanceBeforeSwap + feeAmount)) {
      uint256 refund = ethBalanceAfterSwap - (ethBalanceBeforeSwap + feeAmount);
      (success,) = msg.sender.call{ value: refund }("");
      if (!success) revert SwapViaAggregatorFailed(aggregator);
    }

    emit Swap(msg.sender, address(0), tokenOut, msg.value, amountOut);
  }

  receive() external payable { }
}
