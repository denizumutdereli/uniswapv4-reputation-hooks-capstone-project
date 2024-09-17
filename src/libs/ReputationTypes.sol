// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library ReputationTypes {
    struct SwapInfo {
        int256 amount0;
        int256 amount1;
        bool zeroForOne;
        int256 amountSpecified;
    }

    struct TickInfo {
        int24 currentTick;
        int24 lastTick;
    }

    struct TokenInfo {
        address token0;
        address token1;
    }

    struct MetricsInfo {
        uint256 liquidityUtilization;
        uint24 tickRange;
        uint256 activityScore;
    }

    struct ReputationUpdate {
        address user;
        SwapInfo swapInfo;
        TickInfo tickInfo;
        TokenInfo tokenInfo;
        MetricsInfo metricsInfo;
    }

    function _hashSwapInfo(SwapInfo memory swapInfo) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            swapInfo.amount0,
            swapInfo.amount1,
            swapInfo.zeroForOne,
            swapInfo.amountSpecified
        ));
    }

    function _hashTickInfo(TickInfo memory tickInfo) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            tickInfo.currentTick,
            tickInfo.lastTick
        ));
    }

    function _hashTokenInfo(TokenInfo memory tokenInfo) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            tokenInfo.token0,
            tokenInfo.token1
        ));
    }

    function _hashMetricsInfo(MetricsInfo memory metricsInfo) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            metricsInfo.liquidityUtilization,
            metricsInfo.tickRange,
            metricsInfo.activityScore
        ));
    }
}
