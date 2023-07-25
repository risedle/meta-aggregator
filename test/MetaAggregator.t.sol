// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {RisedleMetaAggregator} from "src/MetaAggregator.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Permit} from
  "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {SigUtils} from "./SigUtils.sol";

/**
 * @title MockAggregator
 * @author sepyke.eth
 * @notice Mock aggregator
 */
contract MockAggregator {
  using SafeERC20 for IERC20;

  function swapEthToToken(address tokenOut, uint256 minAmountOut)
    external
    payable
  {
    IERC20(tokenOut).transfer(msg.sender, minAmountOut);
  }

  function swapTokenToEth(address tokenIn, uint256 amountIn, uint256 amountOut)
    external
  {
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    (bool success,) = msg.sender.call{value: amountOut}("");
    require(success, "SWAP_FAILED");
  }

  function swapTokenToToken(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOut
  ) external {
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    IERC20(tokenOut).transfer(msg.sender, amountOut);
  }

  receive() external payable {}
}

/**
 * @title MetaAggregatorTest
 * @author sepyke.eth
 * @notice Unit tests for MetaAggregator
 */
contract MetaAggregatorTest is Test {
  using SafeERC20 for IERC20;

  RisedleMetaAggregator metaAgg;
  address feeRecipient = 0x56b4a9675c52144C99F676835e83d5625CB47202;
  uint256 feePercentage = 0.001 ether;
  address[] aggregators = [
    0x1111111254EEB25477B68fb85Ed929f73A960582, // 1inch
    0xDef1C0ded9bec7F1a1670819833240f027b25EfF, // 0x / Matcha
    0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57, // ParaSwap
    0x6131B5fae19EA4f9D964eAc0408E4408b66337b5, // KyberSwap
    0x6352a56caadC4F1E25CD6c75970Fa768A3304e64 // OpenOcean
  ];

  address alice = vm.addr(0xA11CE);
  address usdcAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
  address usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
  MockAggregator mockUnregisteredAgg;
  MockAggregator mockRegisteredAgg;

  function setUp() public {
    mockUnregisteredAgg = new MockAggregator();
    mockRegisteredAgg = new MockAggregator();

    aggregators.push(address(mockRegisteredAgg));
    metaAgg =
      new RisedleMetaAggregator(feeRecipient, aggregators, feePercentage);
  }

  /// @notice Make sure ETH fees can be collected
  function testCollectETH() public {
    vm.deal(address(metaAgg), 2 ether);

    uint256 prevBalance = feeRecipient.balance;
    metaAgg.collectEth(2 ether);
    uint256 afterBalance = feeRecipient.balance;

    assertEq(
      afterBalance - prevBalance, 2 ether, "invalid feeRecipient balance"
    );
  }

  /// @notice Make sure Token fees can be collected
  function testCollectToken() public {
    deal(usdcAddress, address(metaAgg), 2 ether);

    uint256 prevBalance = IERC20(usdcAddress).balanceOf(feeRecipient);
    metaAgg.collectToken(usdcAddress, 2 ether);
    uint256 afterBalance = IERC20(usdcAddress).balanceOf(feeRecipient);

    assertEq(
      afterBalance - prevBalance, 2 ether, "invalid feeRecipient balance"
    );
  }

  // ====== Swap ETH to Token =================================================

  /// @dev Make sure it revert if aggregator is unregistered
  function testSwapEthToTokenWithUnregisteredAggregator() public {
    // Set input
    address tokenOut = usdcAddress; // USDC
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1e6;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapEthToToken.selector, tokenOut, amountOut
    ); // call

    deal(alice, amountIn);
    vm.startPrank(alice);

    vm.expectRevert(
      abi.encodeWithSelector(
        RisedleMetaAggregator.AggregatorInvalid.selector,
        address(mockUnregisteredAgg)
      )
    );
    metaAgg.swapEthToToken{value: amountIn}(
      tokenOut, payable(address(mockUnregisteredAgg)), data, amountOut
    );
  }

  /// @dev Make sure the swap is executed successfully
  function testSwapEthToTokenWithRegisteredAggregator() public {
    // Set input
    address tokenOut = usdcAddress; // USDC
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1e6;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapEthToToken.selector, tokenOut, amountOut
    );

    deal(alice, amountIn);
    deal(tokenOut, address(mockRegisteredAgg), amountOut);

    vm.startPrank(alice);
    metaAgg.swapEthToToken{value: amountIn}(
      tokenOut, payable(address(mockRegisteredAgg)), data, amountOut
    );

    uint256 aliceBalance = IERC20(tokenOut).balanceOf(alice);
    assertEq(aliceBalance, amountOut); // output token
    assertEq(address(metaAgg).balance, 0.001 ether); // fee
  }

  // ====== Swap Token to ETH =================================================

  /// @dev Make sure it revert if aggregator is unregistered
  function testSwapTokenToEthWithUnregisteredAggregator() public {
    // Set input
    address tokenIn = usdcAddress; // USDC
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapTokenToEth.selector, tokenIn, amountIn, amountOut
    ); // call

    deal(tokenIn, alice, amountIn);
    vm.startPrank(alice);

    IERC20(tokenIn).approve(address(metaAgg), amountIn);

    vm.expectRevert(
      abi.encodeWithSelector(
        RisedleMetaAggregator.AggregatorInvalid.selector,
        address(mockUnregisteredAgg)
      )
    );
    metaAgg.swapTokenToEth(
      tokenIn, payable(address(mockUnregisteredAgg)), data, amountIn, amountOut
    );
  }

  /// @dev Make sure the swap is executed successfully
  function testSwapTokenToEthWithRegisteredAggregator() public {
    // Set input
    address tokenIn = usdcAddress; // USDC
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapTokenToEth.selector, tokenIn, amountIn, amountOut
    ); // call

    deal(tokenIn, alice, amountIn);
    deal(address(mockRegisteredAgg), amountOut);
    vm.startPrank(alice);

    IERC20(tokenIn).approve(address(metaAgg), amountIn);
    metaAgg.swapTokenToEth(
      tokenIn, payable(address(mockRegisteredAgg)), data, amountIn, amountOut
    );

    assertEq(address(metaAgg).balance, 0.001 ether); // fee
    assertEq(alice.balance, 1 ether - 0.001 ether);
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToEthWithPermit() public {
    // Set input
    address tokenIn = usdcAddress; // USDC
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapTokenToEth.selector, tokenIn, amountIn, amountOut
    ); // call data

    // Create permit values
    SigUtils.Permit memory permit = SigUtils.Permit({
      owner: alice,
      spender: address(metaAgg),
      value: amountIn,
      nonce: 0,
      deadline: block.timestamp + 1 days
    });

    SigUtils sigUtils = new SigUtils(IERC20Permit(tokenIn).DOMAIN_SEPARATOR());
    bytes32 digest = sigUtils.getTypedDataHash(permit);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);

    deal(tokenIn, alice, amountIn);
    deal(address(mockRegisteredAgg), amountOut);
    vm.startPrank(alice);

    // Do the swap
    metaAgg.swapTokenToEthWithPermit(
      tokenIn,
      payable(address(mockRegisteredAgg)),
      data,
      amountIn,
      amountOut,
      block.timestamp + 1 days,
      v,
      r,
      s
    );

    assertEq(address(metaAgg).balance, 0.001 ether); // fee
    assertEq(alice.balance, 1 ether - 0.001 ether);
  }

  // ====== Swap Token to Token ===============================================

  /// @dev Make sure it revert if aggregator is unregistered
  function testSwapTokenToTokenWithUnregisteredAggregator() public {
    // Set input
    address tokenIn = usdcAddress; // USDC
    address tokenOut = usdtAddress; // USDT
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapTokenToToken.selector,
      tokenIn,
      amountIn - 0.001 ether, // include fees
      tokenOut,
      amountOut
    ); // call

    deal(tokenIn, alice, amountIn);
    deal(tokenOut, address(mockUnregisteredAgg), amountOut);
    vm.startPrank(alice);

    IERC20(tokenIn).approve(address(metaAgg), amountIn);

    vm.expectRevert(
      abi.encodeWithSelector(
        RisedleMetaAggregator.AggregatorInvalid.selector,
        address(mockUnregisteredAgg)
      )
    );
    metaAgg.swapTokenToToken(
      tokenIn,
      tokenOut,
      payable(address(mockUnregisteredAgg)),
      data,
      amountIn,
      amountOut
    );
  }

  /// @dev Make sure the swap is executed successfully
  function testSwapTokenToTokenWithRegisteredAggregator() public {
    // Set input
    address tokenIn = usdcAddress; // USDC
    address tokenOut = usdtAddress; // USDT
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapTokenToToken.selector,
      tokenIn,
      amountIn - 0.001 ether, // include fees
      tokenOut,
      amountOut
    ); // call

    deal(tokenIn, alice, amountIn);
    deal(tokenOut, address(mockRegisteredAgg), amountOut);
    vm.startPrank(alice);

    IERC20(tokenIn).approve(address(metaAgg), amountIn);
    metaAgg.swapTokenToToken(
      tokenIn,
      tokenOut,
      payable(address(mockRegisteredAgg)),
      data,
      amountIn,
      amountOut
    );

    assertEq(IERC20(tokenIn).balanceOf(address(metaAgg)), 0.001 ether); // fee
    assertEq(IERC20(tokenOut).balanceOf(alice), 1 ether);
  }

  /// @dev Make sure the accounting is correct
  function testSwapTokenToTokenWithPermit() public {
    // Set input
    address tokenIn = usdcAddress; // USDC
    address tokenOut = usdtAddress; // USDT
    uint256 amountIn = 1 ether;
    uint256 amountOut = 1 ether;
    bytes memory data = abi.encodeWithSelector(
      MockAggregator.swapTokenToToken.selector,
      tokenIn,
      amountIn - 0.001 ether, // include fees
      tokenOut,
      amountOut
    ); // call data

    // Create permit values
    SigUtils.Permit memory permit = SigUtils.Permit({
      owner: alice,
      spender: address(metaAgg),
      value: amountIn,
      nonce: 0,
      deadline: block.timestamp + 1 days
    });

    SigUtils sigUtils = new SigUtils(IERC20Permit(tokenIn).DOMAIN_SEPARATOR());
    bytes32 digest = sigUtils.getTypedDataHash(permit);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);

    deal(tokenIn, alice, amountIn);
    deal(tokenOut, address(mockRegisteredAgg), amountOut);
    vm.startPrank(alice);

    // Do the swap
    metaAgg.swapTokenToTokenWithPermit(
      tokenIn,
      tokenOut,
      payable(address(mockRegisteredAgg)),
      data,
      amountIn,
      amountOut,
      block.timestamp + 1 days,
      v,
      r,
      s
    );

    assertEq(IERC20(tokenIn).balanceOf(address(metaAgg)), 0.001 ether); // fee
    assertEq(IERC20(tokenOut).balanceOf(alice), 1 ether);
  }
}
