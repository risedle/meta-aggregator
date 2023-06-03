// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { Ownable } from "openzeppelin/access/Ownable.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract FeeCollector is Ownable {
  using SafeERC20 for IERC20;

  /// @dev Fee per swap
  uint256 FEE = 0.001 ether; // 0.1%

  /// @dev Error raised if the fee recipient is invalid
  error FeeRecipientInvalid();

  /// @dev Error raised if ETH transfer is fee collection is failed
  error CollectFeeFailed();

  /// @dev Event emitted if ETH fees is collected
  event ETHCollected(address indexed to, uint256 amount);

  /// @dev Event emitted if token fees is collected
  event TokenCollected(
    address indexed to, address indexed token, uint256 amount
  );

  /**
   * @notice Collect fees to specified address
   * @param to The fee recipient
   * @param amount The ETH amount
   */
  function collectETH(address to, uint256 amount) external onlyOwner {
    if (to == address(0)) revert FeeRecipientInvalid();
    (bool success,) = to.call{ value: amount }("");
    if (!success) revert CollectFeeFailed();
    emit ETHCollected(to, amount);
  }

  /**
   * @notice Collect fees to specified address
   * @param to The fee recipient
   * @param token The token address
   * @param amount The token amount
   */
  function collectToken(address to, address token, uint256 amount)
    external
    onlyOwner
  {
    if (to == address(0)) revert FeeRecipientInvalid();
    IERC20(token).safeTransfer(to, amount);
    emit TokenCollected(to, token, amount);
  }
}
