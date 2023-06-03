// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ISwapper {
  /// @notice Error is raised if contract all to aggregator is failed
  error SwapViaAggregatorFailed(address aggregator);

  /// @notice Error is raised if allowance is not spend 100%
  error AllowanceInvalid(address aggregator);

  /// @notice Error is raised if ETH is not received by contract
  error ETHAmountInvalid();
}
