// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Abs Library
 * @notice Utility library for absolute value and maximum calculations
 */
library Abs {
    /**
     * @notice Calculate the absolute value of an int256
     * @param value The input value
     * @return The absolute value as a uint256
     */
    function abs(int256 value) internal pure returns (uint256) {
        return uint256(value < 0 ? -value : value);
    }

    /**
     * @notice Return the maximum of two uint256 values
     * @param a The first value
     * @param b The second value
     * @return The maximum value
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}
