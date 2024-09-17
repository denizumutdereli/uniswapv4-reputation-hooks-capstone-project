// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library APYLibrary {
    /**
     * @dev Computes the natural logarithm approximation of (1 + x) using a series expansion.
     * Assumes x is a small value, scaled by 1e18.
     * @param x Scaled input representing APR with 18 decimal places.
     * @return The natural logarithm of (1 + x) scaled by 1e18.
     */
    function log1p(uint256 x) internal pure returns (uint256) {
        uint256 result = x; // First term in the series: x
        uint256 term = x;
        uint256 scaleFactor = 1e18;

        // Series expansion: x - x^2/2 + x^3/3 - x^4/4 + ...
        for (uint256 i = 2; i <= 10; i++) {
            term = (term * x) / scaleFactor; // Calculate x^i
            uint256 nextTerm = term / i;
            
            // Alternate adding and subtracting terms
            if (i % 2 == 0) {
                result -= nextTerm; // Subtract when i is even
            } else {
                result += nextTerm; // Add when i is odd
            }

            // Break early if the term becomes too small to matter
            if (nextTerm == 0) {
                break;
            }
        }

        return result;
    }

    /**
     * @dev Calculates the APY given an APR using logarithmic approximation.
     * @param apr The APR, scaled by 1e18.
     * @return The APY, scaled by 1e18.
     */
    function calculateAPY(uint256 apr) internal pure returns (uint256) {
        if (apr == 0) {
            return 0; // Return 0 if APR is zero to avoid unnecessary computation
        }

        // Approximate APY using log1p(apr)
        return log1p(apr);
    }

    /**
     * @dev Calculates the APR based on liquidity and volume traded.
     * @param totalLiquidity The total liquidity in the pool.
     * @param volumeTraded The total volume traded in the pool.
     * @return The APR, scaled by 1e18.
     */
    function calculateAPR(uint256 totalLiquidity, uint256 volumeTraded) internal pure returns (uint256) {
        if (totalLiquidity == 0) {
            return 0; // Return 0 to prevent division by zero
        }

        uint256 averageFee = 3; // Default fee in basis points (0.3%)
        return (volumeTraded * averageFee * 365 * 1e18) / (totalLiquidity * 1000);
    }

    /**
     * @dev Calculates the volatility based on tick movement speed and time delta.
     * @param tickMoveSpeed The speed at which the tick changes.
     * @param timeDelta The time difference over which the tick change is measured.
     * @return The volatility, scaled by 1e18.
     */
    function calculateVolatility(uint256 tickMoveSpeed, uint256 timeDelta) internal pure returns (uint256) {
        if (timeDelta == 0) {
            return 0; // Avoid division by zero
        }
        return (tickMoveSpeed * 1e18) / timeDelta;
    }
}
