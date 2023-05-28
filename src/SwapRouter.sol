// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract RisedleSwapRouter {
  /// @dev Whitelisted aggregators
  mapping(address aggregator => bool isWhitelisted) public aggregators;

  /// @notice Error is raised if aggregator is not whitelisted
  error InvalidAggregator();

  /// @dev Make sure only whitelisted aggregator can do the swap
  modifier onlyWhitelistedAggregator(address aggregator) {
    if (!aggregators[aggregator]) revert InvalidAggregator();
    _;
  }

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
    // Implement swap token to ETH
  }

  function _swapTokenToETH(
    address tokenIn,
    uint256 tokenInAmount,
    address payable aggregator,
    bytes calldata data,
    uint256 fee
  ) internal {
    // Get the contract balance
    // Move token to this contract
  }
}
