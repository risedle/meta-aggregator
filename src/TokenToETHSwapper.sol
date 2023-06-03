// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { IERC20Permit } from
  "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

import { AggregatorManager } from "./AggregatorManager.sol";

contract TokenToETHSwapper is AggregatorManager {
  using SafeERC20 for IERC20;
  using Math for uint256;

  /// @notice Error is raised if contract all to aggregator is failed
  error SwapViaAggregatorFailed(address aggregator);

  /// @notice Error is raised if allowance is not spend 100%
  error AllowanceInvalid(address aggregator);

  /// @notice Error is raised if ETH is not received by contract
  error ETHAmountInvalid();

  /**
   * @notice Swap token to ETH
   * @param tokenIn The input token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenInAmount The amount of input token
   * @param tokenOutMinAmount The min amount of output token
   * @param fee Fee in ether (e.g. 0.1% is 0.001 ether or 1000000000000000)
   */
  function swapTokenToETH(
    address tokenIn,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount,
    uint256 fee
  ) external payable onlyRegisteredAggregator(aggregator) {
    _swapTokenToETH(
      tokenIn, aggregator, data, tokenInAmount, tokenOutMinAmount, fee
    );
  }

  /**
   * @notice Swap token to ETH with permit
   * @param tokenIn The input token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenInAmount The amount of input token
   * @param tokenOutMinAmount The min amount of output token
   * @param fee Fee in ether (e.g. 0.1% is 0.001 ether or 1000000000000000)
   */
  function swapTokenToETHWithPermit(
    address tokenIn,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount,
    uint256 fee,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable onlyRegisteredAggregator(aggregator) {
    IERC20Permit(tokenIn).permit(
      msg.sender, address(this), tokenInAmount, deadline, v, r, s
    );
    _swapTokenToETH(
      tokenIn, aggregator, data, tokenInAmount, tokenOutMinAmount, fee
    );
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
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount,
    uint256 fee
  ) internal {
    // Swap
    if (address(this).balance < msg.value) revert ETHAmountInvalid();
    uint256 balanceBeforeSwap = address(this).balance - msg.value;
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    IERC20(tokenIn).safeApprove(aggregator, tokenInAmount);
    (bool success,) = aggregator.call{ value: msg.value }(data);
    if (!success) revert SwapViaAggregatorFailed(aggregator);

    // Double check
    uint256 allowance = IERC20(tokenIn).allowance(address(this), aggregator);
    if (allowance > 0) revert AllowanceInvalid(aggregator);
    uint256 balanceAfterSwap = address(this).balance;
    if (balanceAfterSwap < balanceBeforeSwap) revert ETHAmountInvalid();
    uint256 amountOut = balanceAfterSwap - balanceBeforeSwap;
    if (amountOut == 0 || amountOut < tokenOutMinAmount) {
      revert ETHAmountInvalid();
    }

    // Send ETH to the user
    if (fee > 0) {
      uint256 amountFee = fee.mulDiv(amountOut, 1e18, Math.Rounding.Down);
      (success,) = address(msg.sender).call{ value: amountOut - amountFee }("");
    } else {
      (success,) = address(msg.sender).call{ value: amountOut }("");
    }
    if (!success) revert SwapViaAggregatorFailed(aggregator);
  }

  receive() external payable { }
}
