// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

interface IMetaPool {
    function updateMetaPoolMetrics(
        IPoolManager poolManager,
        PoolId poolId,
        address user,
        int256 liquidityDelta,
        int256 volumeTraded,
        int24 tickLower,
        int24 tickUpper
    ) external;

    function getMetaPoolStats()
        external
        view
        returns (
            uint256 totalValueLocked,
            uint256 totalVolumeTraded,
            uint256 activePoolCount,
            uint256 totalUniqueUsers
        );

    function getPoolStats(
        IPoolManager poolManager,
        PoolId poolId
    )
        external
        view
        returns (
            uint256 totalLiquidity,
            int24 currentTick,
            uint256 volumeTraded,
            uint256 apr,
            uint256 apy,
            uint256 healthScore,
            uint256 volatility,
            uint256 zapInOutCount,
            uint256 liquidityChangeCount,
            int256 tickMoveSpeed,
            int256 priceChangeAcceleration
        );

    function getUserStats(
        PoolId poolId,
        address user
    )
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 totalVolume,
            uint256 actionCount
        );

    function isNewUser(address user) external view returns (bool);

    function getLiquidityUtilization(
        IPoolManager poolManager,
        PoolId poolId,
        address user
    ) external view returns (uint256);

    function getActivityScore(
        PoolId poolId,
        address user
    ) external view returns (uint256);

    function deactivatePool(PoolId poolId) external;
}
