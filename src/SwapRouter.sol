// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

contract RisedleSwapRouter {
  /// ███ Libraries ████████████████████████████████████████████████████████████

  using SafeERC20 for IERC20;
  using Math for uint256;

  /// @notice Error is raised if contract all to aggregator is failed
  error SwapViaAggregatorFailed(address aggregator);

  /// @notice Error is raised if allowance is not spend 100%
  error AllowanceInvalid(address aggregator);

  /// @notice Error is raised if ETH is not received by contract
  error ETHAmountInvalid();

  /// @notice Swap token to ETH
  /// @param tokenIn The input token address
  /// @param tokenInAmount The amount of input token
  /// @param aggregator The contract address of aggregator
  /// @param data The aggregator's call data
  /// @param fee Fee in basis points (e.g. 100 is 0.1%)
  function swapTokenToETH(
    address tokenIn,
    address payable aggregator,
    bytes calldata data,
    uint256 tokenInAmount,
    uint256 fee
  ) public {
    _swapTokenToETH(tokenIn, tokenInAmount, aggregator, data, fee);
  }

  /**
   * @dev Implementation of SwapTokenToETH via specified aggregator.
   *
   * Here is step by step:
   * 0. Make sure user have approved this contract to spend their token
   * 1. Transfer the tokenIn to the contract
   * 2. Approve aggregator to spend the token
   * 3. Call the aggregator contract with specified call data
   * 4. Perform double check such as allowance and eth
   * 5. Deduct fee (if any)
   * 6. Send ETH to the user
   */
  function _swapTokenToETH(
    address tokenIn,
    uint256 tokenInAmount,
    address payable aggregator,
    bytes calldata data,
    uint256 fee
  ) internal {
    // Swap
    uint256 balanceBeforeSwap = address(this).balance - msg.value;
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    IERC20(tokenIn).safeApprove(aggregator, tokenInAmount);
    (bool success,) = aggregator.call{ value: msg.value }(data);
    if (!success) revert SwapViaAggregatorFailed(aggregator);

    // Double check
    uint256 allowance = IERC20(tokenIn).allowance(address(this), aggregator);
    if (allowance > 0) revert AllowanceInvalid(aggregator);
    uint256 balanceAfterSwap = address(this).balance;
    uint256 amountOut = balanceAfterSwap - balanceBeforeSwap;
    if (amountOut == 0) revert ETHAmountInvalid();

    // Send ETH to the user
    if (fee > 0) {
      uint256 amountFee = fee.mulDiv(amountOut, 1e18, Math.Rounding.Down);
      (success,) = address(msg.sender).call{ value: amountOut - amountFee }("");
    } else {
      (success,) = address(msg.sender).call{ value: amountOut }("");
    }
    if (!success) revert SwapViaAggregatorFailed(aggregator);
  }
}
