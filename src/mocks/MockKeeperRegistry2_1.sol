// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@chainlink/contracts/src/v0.8/mocks/../interfaces/IAutomationRegistryConsumer.sol";

/**
 * @title MockKeeperRegistry2_1
 * @dev A mock implementation of the KeeperRegistry contract.
 */
contract MockKeeperRegistry2_1 is IAutomationRegistryConsumer {
  uint96 balance;
  uint96 minBalance;

  constructor() {}

  /**
   * @dev Retrieves the balance of a keeper.
   * param id The ID of the keeper.
   * @return The balance of the keeper.
   */
  function getBalance(uint256 /*id*/) external view override returns (uint96) {
    return balance;
  }

  /**
   * @dev Retrieves the minimum balance required for a keeper.
   * param id The ID of the keeper.
   * @return The minimum balance required for the keeper.
   */
  function getMinBalance(uint256 /*id*/) external view override returns (uint96) {
    return minBalance;
  }

  /**
   * @dev Cancels an upkeep for a keeper.
   * @param id The ID of the upkeep.
   */
  function cancelUpkeep(uint256 id) external override {}

  /**
   * @dev Pauses an upkeep for a keeper.
   * @param id The ID of the upkeep.
   */
  function pauseUpkeep(uint256 id) external override {}

  /**
   * @dev Unpauses an upkeep for a keeper.
   * @param id The ID of the upkeep.
   */
  function unpauseUpkeep(uint256 id) external override {}

  /**
   * @dev Updates the check data for an upkeep.
   * @param id The ID of the upkeep.
   * @param newCheckData The new check data.
   */
  function updateCheckData(uint256 id, bytes calldata newCheckData) external {}

  /**
   * @dev Adds funds to a keeper.
   * @param id The ID of the keeper.
   * @param amount The amount of funds to add.
   */
  function addFunds(uint256 id, uint96 amount) external override {}

  /**
   * @dev Withdraws funds from a keeper.
   * @param id The ID of the keeper.
   * @param to The address to withdraw the funds to.
   */
  function withdrawFunds(uint256 id, address to) external override {}
}
