// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {IERC20Permit} from "oz/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {Math} from "oz/utils/math/Math.sol";

/**
 * @title RisedleMetaAggregator
 * @author sepyke.eth
 * @notice Main smart contract for Risedle's meta dex aggregator
 */
contract RisedleMetaAggregator {
  using SafeERC20 for IERC20;
  using Math for uint256;

  /// @dev Fee per swap in ether units (e.g. 0.001 ether is 0.1%)
  uint256 feePercentage;

  /// @dev Fee recipient
  address feeRecipient;

  /// @dev Whitelisted aggregators
  mapping(address => bool) public aggregators;

  /// @dev This event is emitted when the ETH fees are collected
  event ETHCollected(address indexed to, uint256 amount);

  /// @dev This event is emitted when the Token fees are collected
  event TokenCollected(
    address indexed to, address indexed token, uint256 amount
  );

  /// @notice This event is emitted when the Swap happen
  event Swap(
    address indexed user,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 tokenInAmount,
    uint256 tokenOutAmount
  );

  /// @dev This error is raised if fee collection is failed
  error CollectFeeFailed();

  /// @dev This error is raised if aggregator is invalid
  error AggregatorInvalid(address aggregator);

  /// @notice This error is raised if swap is failed
  error SwapViaAggregatorFailed(address aggregator);

  /// @notice This error is raised if allowance is not spent 100%
  error AllowanceInvalid(address aggregator);

  /// @notice This error is raised if amountIn is invalid
  error AmountInInvalid();

  /// @notice This error is raised if amountOut is invalid
  error AmountOutInvalid();

  /**
   * @notice RisedleMetaAggregator constructor
   * @param _feeRecipient The fee recipient adress
   * @param _aggregators List of metadex aggregator addresses
   * @param _feePercentage Fee percentage in ether units (e.g. 0.001ether is
   * 0.1%)
   */
  constructor(
    address _feeRecipient,
    address[] memory _aggregators,
    uint256 _feePercentage
  ) {
    feeRecipient = _feeRecipient;
    feePercentage = _feePercentage;
    for (uint256 i = 0; i < _aggregators.length; i++) {
      aggregators[_aggregators[i]] = true;
    }
  }

  /// @dev Modifier to make sure only whitelisted aggregator can call the
  /// contract
  modifier onlyRegisteredAggregator(address aggregator) {
    if (!aggregators[aggregator]) revert AggregatorInvalid(aggregator);
    _;
  }

  /**
   * @notice Collect fees to specified address
   * @param amount The ETH amount
   */
  function collectEth(uint256 amount) external {
    (bool success,) = feeRecipient.call{value: amount}("");
    if (!success) revert CollectFeeFailed();
    emit ETHCollected(feeRecipient, amount);
  }

  /**
   * @notice Collect fees to specified address
   * @param token The token address
   * @param amount The token amount
   */
  function collectToken(address token, uint256 amount) external {
    IERC20(token).safeTransfer(feeRecipient, amount);
    emit TokenCollected(feeRecipient, token, amount);
  }

  /**
   * @notice Swap ETH to token
   * @param tokenOut The output token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenOutMinAmount The min amount of output token
   */
  function swapEthToToken(
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenOutMinAmount
  ) external payable onlyRegisteredAggregator(aggregator) {
    _swapEthToToken(tokenOut, aggregator, data, tokenOutMinAmount);
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
  function _swapEthToToken(
    address tokenOut,
    address payable aggregator,
    bytes memory data,
    uint256 tokenOutMinAmount
  ) internal {
    if (msg.value == 0) revert AmountInInvalid();
    uint256 tokenBalanceBeforeSwap = IERC20(tokenOut).balanceOf(address(this));
    uint256 ethBalanceBeforeSwap = address(this).balance - msg.value;

    uint256 feeAmount =
      feePercentage.mulDiv(msg.value, 1 ether, Math.Rounding.Down);
    (bool success,) = aggregator.call{value: msg.value - feeAmount}(data);
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
      (success,) = msg.sender.call{value: refund}("");
      if (!success) revert SwapViaAggregatorFailed(aggregator);
    }

    emit Swap(msg.sender, address(0), tokenOut, msg.value, amountOut);
  }

  /**
   * @notice Swap token to ETH
   * @param tokenIn The input token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenInAmount The amount of input token
   * @param tokenOutMinAmount The min amount of output token
   */
  function swapTokenToEth(
    address tokenIn,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount
  ) external payable onlyRegisteredAggregator(aggregator) {
    _swapTokenToEth(
      tokenIn, aggregator, data, tokenInAmount, tokenOutMinAmount
    );
  }

  /**
   * @notice Swap token to ETH with permit
   * @param tokenIn The input token address
   * @param aggregator The contract address of aggregator
   * @param data The aggregator's call data
   * @param tokenInAmount The amount of input token
   * @param tokenOutMinAmount The min amount of output token
   */
  function swapTokenToEthWithPermit(
    address tokenIn,
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
    _swapTokenToEth(
      tokenIn, aggregator, data, tokenInAmount, tokenOutMinAmount
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
  function _swapTokenToEth(
    address tokenIn,
    address payable aggregator,
    bytes memory data,
    uint256 tokenInAmount,
    uint256 tokenOutMinAmount
  ) internal {
    // Swap
    uint256 balanceBeforeSwap = address(this).balance - msg.value;
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    IERC20(tokenIn).safeApprove(aggregator, tokenInAmount);
    (bool success,) = aggregator.call{value: msg.value}(data);
    if (!success) revert SwapViaAggregatorFailed(aggregator);

    // Double check
    uint256 allowance = IERC20(tokenIn).allowance(address(this), aggregator);
    if (allowance > 0) revert AllowanceInvalid(aggregator);
    uint256 balanceAfterSwap = address(this).balance;
    if (balanceAfterSwap < balanceBeforeSwap) revert AmountOutInvalid();
    uint256 amountOut = balanceAfterSwap - balanceBeforeSwap;
    if (amountOut == 0 || amountOut < tokenOutMinAmount) {
      revert AmountOutInvalid();
    }

    // Send ETH to the user
    uint256 amountFee =
      feePercentage.mulDiv(amountOut, 1e18, Math.Rounding.Down);
    (success,) = address(msg.sender).call{value: amountOut - amountFee}("");
    if (!success) revert SwapViaAggregatorFailed(aggregator);

    emit Swap(msg.sender, tokenIn, address(0), tokenInAmount, amountOut);
  }

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
    uint256 feeAmount =
      feePercentage.mulDiv(tokenInAmount, 1e18, Math.Rounding.Down);
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);
    IERC20(tokenIn).safeApprove(aggregator, tokenInAmount - feeAmount);
    (bool success,) = aggregator.call{value: msg.value}(data);
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

  receive() external payable {}
}
