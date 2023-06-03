// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ISwapper {
  /// @notice Error raised if contract all to aggregator is failed
  error SwapViaAggregatorFailed(address aggregator);

  /// @notice Error raised if allowance is not spend 100%
  error AllowanceInvalid(address aggregator);

  /// @notice Error raised if amount out is invalid
  error AmountOutInvalid();

  /// @notice Event emitted if swap happen
  event Swap(
    address indexed user,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 tokenInAmount,
    uint256 tokenOutAmount
  );
}
