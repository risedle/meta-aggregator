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
import { ETHReceiver } from "./ETHReceiver.sol";

contract TokenToTokenSwapper is
  ISwapper,
  AggregatorManager,
  FeeCollector,
  ETHReceiver
{
  using SafeERC20 for IERC20;
  using Math for uint256;

  /**
   * @notice Swap token to token
   * @param tokenIn The input token address
   * @param tokenOut The output token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenInAmount The amount of input token
   * @param tokenOutMinAmount The min amount of output token
   */
  function swapTokenToToken(
    address tokenIn,
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount
  ) external payable onlyRegisteredAggregator(aggregator) {
    _swapTokenToToken(
      tokenIn, tokenOut, aggregator, data, tokenInAmount, tokenOutMinAmount
    );
  }

  /**
   * @notice Swap token to ETH with permit
   * @param tokenIn The input token address
   * @param tokenOut The output token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenInAmount The amount of input token
   * @param tokenOutMinAmount The min amount of output token
   */
  function swapTokenToTokenWithPermit(
    address tokenIn,
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable onlyRegisteredAggregator(aggregator) {
    IERC20Permit(tokenIn).permit(
      msg.sender, address(this), tokenInAmount, deadline, v, r, s
    );
    _swapTokenToToken(
      tokenIn, tokenOut, aggregator, data, tokenInAmount, tokenOutMinAmount
    );
  }

  /**
   * @dev Implementation of swapTokenToToken via specified aggregator.
   *
   * Here is step by step:
   * 0. Make sure user have approved this contract to spend their token
   * 1. Transfer the tokenIn to the contract
   * 2. Approve aggregator to spend the tokenIn
   * 3. Call the aggregator contract with specified call data. Call data should
   *    take account that only tokenInAmount - fee is approved to swap.
   * 4. Perform double check such as allowance
   * 5. Send tokenOut to the user
   *
   */
  function _swapTokenToToken(
    address tokenIn,
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount
  ) internal {
    uint256 balanceBeforeSwap = IERC20(tokenOut).balanceOf(address(this));
    uint256 feeAmount = FEE.mulDiv(tokenInAmount, 1e18, Math.Rounding.Down);
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    IERC20(tokenIn).safeApprove(aggregator, tokenInAmount - feeAmount);
    (bool success,) = aggregator.call{ value: msg.value }(data);
    if (!success) revert SwapViaAggregatorFailed(aggregator);

    // Double check
    uint256 allowance = IERC20(tokenIn).allowance(address(this), aggregator);
    if (allowance > 0) revert AllowanceInvalid(aggregator);
    uint256 balanceAfterSwap = IERC20(tokenOut).balanceOf(address(this));
    if (balanceAfterSwap < balanceBeforeSwap) revert AmountOutInvalid();
    uint256 amountOut = balanceAfterSwap - balanceBeforeSwap;
    if (amountOut == 0 || amountOut < tokenOutMinAmount) {
      revert AmountOutInvalid();
    }

    // Send Token to the user
    IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

    emit Swap(msg.sender, tokenIn, tokenOut, tokenInAmount, amountOut);
  }
}
