// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { Ownable } from "openzeppelin/access/Ownable.sol";

contract AggregatorManager is Ownable {
  /// @dev Event emitted if new dex aggregator is registered
  event AggregatorRegistered(address indexed aggregator);

  /// @dev Event emitted if existing dex aggregator is unregistered
  event AggregatorUnregistered(address indexed aggregator);

  /// @dev Error is raised if specified aggregator is not valid
  error AggregatorInvalid(address aggregator);

  /// @dev Whitelisted aggregators
  mapping(address aggregator => bool isRegistered) public aggregators;

  /**
   * @notice Register new dex aggregator
   * @param aggregator Dex aggregator contract address (e.g. 1Inch)
   */
  function register(address aggregator) public onlyOwner {
    aggregators[aggregator] = true;
    emit AggregatorRegistered(aggregator);
  }

  /// @dev Modifier to make sure only whitelisted aggregator is called
  modifier onlyRegisteredAggregator(address aggregator) {
    if (!aggregators[aggregator]) revert AggregatorInvalid(aggregator);
    _;
  }

  /**
   * @notice Unregister existing dex aggregator
   * @param aggregator Existing dex aggregator contract address (e.g. 1Inch)
   */
  function unregister(address aggregator)
    public
    onlyOwner
    onlyRegisteredAggregator(aggregator)
  {
    aggregators[aggregator] = false;
    emit AggregatorUnregistered(aggregator);
  }
}
