// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title MockUpkeep
/// @notice A mock contract for testing purposes
contract MockUpkeep {
  bool public shouldCheckRevert;
  bool public shouldPerformRevert;
  bool public checkResult = true;
  bytes public performData;
  uint256 public checkGasToBurn;
  uint256 public performGasToBurn;

  event UpkeepPerformedWith(bytes upkeepData);

  /// @dev Revert error for checkUpkeep function
  error CheckRevert();

  /// @dev Revert error for performUpkeep function
  error PerformRevert();

  /// @notice Sets the value of shouldCheckRevert
  /// @param value The new value for shouldCheckRevert
  function setShouldCheckRevert(bool value) public {
    shouldCheckRevert = value;
  }

  /// @notice Sets the value of shouldPerformRevert
  /// @param value The new value for shouldPerformRevert
  function setShouldPerformRevert(bool value) public {
    shouldPerformRevert = value;
  }

  /// @notice Sets the value of checkResult
  /// @param value The new value for checkResult
  function setCheckResult(bool value) public {
    checkResult = value;
  }

  /// @notice Sets the value of performData
  /// @param data The new value for performData
  function setPerformData(bytes calldata data) public {
    performData = data;
  }

  /// @notice Sets the value of checkGasToBurn
  /// @param value The new value for checkGasToBurn
  function setCheckGasToBurn(uint256 value) public {
    checkGasToBurn = value;
  }

  /// @notice Sets the value of performGasToBurn
  /// @param value The new value for performGasToBurn
  function setPerformGasToBurn(uint256 value) public {
    performGasToBurn = value;
  }

  /// @notice Checks the upkeep status
  /// param data The input data for the upkeep check
  /// @return callable Whether the upkeep is callable
  /// @return executedata The data to be used for performing the upkeep
  function checkUpkeep(bytes calldata /*data*/) external view returns (bool callable, bytes memory executedata) {
    if (shouldCheckRevert) revert CheckRevert();
    uint256 startGas = gasleft();
    while (startGas - gasleft() < checkGasToBurn) {} // burn gas
    return (checkResult, performData);
  }

  /// @notice Performs the upkeep
  /// @param data The input data for performing the upkeep
  function performUpkeep(bytes calldata data) external {
    if (shouldPerformRevert) revert PerformRevert();
    uint256 startGas = gasleft();
    while (startGas - gasleft() < performGasToBurn) {} // burn gas
    emit UpkeepPerformedWith(data);
  }
}
