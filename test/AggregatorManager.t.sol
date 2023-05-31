// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { AggregatorManager } from "src/AggregatorManager.sol";

contract AggregatorManagerTest is Test {
  AggregatorManager public manager;
  address constant alice = address(1);

  function setUp() public {
    manager = new AggregatorManager();
  }

  /// @notice Make sure the owner can register new aggregator
  function testRegisterAsOwner() public {
    address aggregator = address(2);
    manager.register(aggregator);
    assertTrue(manager.aggregators(aggregator));
  }

  /// @notice Make sure the owner can register new aggregator
  function testRegisterAsNonOwner() public {
    address aggregator = address(3);
    vm.prank(alice);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    manager.register(aggregator);
    assertFalse(manager.aggregators(aggregator));
  }

  /// @notice Make sure the owner can unregister existing aggregator
  function testUnregisterAsOwner() public {
    address aggregator = address(4);
    manager.register(aggregator);
    assertTrue(manager.aggregators(aggregator));
    manager.unregister(aggregator);
    assertFalse(manager.aggregators(aggregator));
  }

  /// @notice Make sure non owner canot unregister existing aggregator
  function testUnregisterAsNonOwner() public {
    address aggregator = address(5);
    manager.register(aggregator);
    assertTrue(manager.aggregators(aggregator));

    vm.prank(alice);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    manager.unregister(aggregator);

    assertTrue(manager.aggregators(aggregator));
  }

  /// @notice Make sure it revert when we try to unregister non-existent aggregator
  function testUnregisterNonExistentAggregator() public {
    address aggregator = address(6);
    vm.expectRevert(
      abi.encodeWithSelector(
        AggregatorManager.AggregatorInvalid.selector, aggregator
      )
    );
    manager.unregister(aggregator);
  }
}
