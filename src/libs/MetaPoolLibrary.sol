/* SPDX-License-Identifier: MIT */
pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {WordCodec} from "./WordCodec.sol";
import {APYLibrary} from "./APYLibrary.sol";
import {Abs} from "./AbsLibrary.sol";

/**
 * @title MetaPoolLibrary
 * @notice Library for managing meta pool metrics and operations
 * @dev This library provides functions to update and retrieve various metrics for pools, users, and global statistics
 */
library MetaPoolLibrary {
    using SafeCast for uint256;
    using SafeCast for int256;
    using WordCodec for bytes32;
    using StateLibrary for IPoolManager;
    using Abs for int256;
    using Abs for uint256;

    uint256 private constant USER_LIQUIDITY_OFFSET = 0;
    uint256 private constant LAST_INTERACTION_TIMESTAMP_OFFSET = 128;
    uint256 private constant ACTION_COUNT_OFFSET = 160;
    uint256 private constant TICK_LOWER_OFFSET = 192;
    uint256 private constant TICK_UPPER_OFFSET = 224;
    uint256 private constant MINIMUM_TIME_DELTA = 300 seconds; /* 5 minutes */

    struct MetaPool {
        mapping(PoolId => PoolMetrics) pools;
        mapping(PoolId => uint256) poolIndexMapping;
        PoolId[] activePoolIds;
        mapping(address => UserMetrics) users;
        mapping(address => mapping(PoolId => UserPoolMetrics)) userPoolMetrics;
        GlobalMetrics globalMetrics;
    }

    struct PoolMetrics {
        bytes32 packedData;
        uint256 totalVolumeTraded;
        uint256 zapInOutCount;
        uint256 liquidityChangeCount;
        int256 tickMoveSpeed;
        int256 priceChangeAcceleration;
        uint256 lastUpdateBlock;
        int24 lastTick;
        uint256 apr;
        uint256 apy;
        uint256 healthScore;
        uint256 volatility;
    }

    struct UserMetrics {
        bytes32 packedData;
        uint256 totalVolumeTraded;
        bool isInitialized;
    }

    struct UserPoolMetrics {
        uint256 liquidity;
        uint256 volumeTraded;
        int24 tickLower;
        int24 tickUpper;
    }

    struct GlobalMetrics {
        uint256 totalValueLocked;
        uint256 totalVolumeTraded;
        uint256 activePoolCount;
        uint256 totalUniqueUsers;
        mapping(uint256 => uint256) activePoolsBitmap;
    }

    function updateMetaPoolMetrics(
        MetaPool storage metaPool,
        IPoolManager poolManager,
        PoolId poolId,
        address user,
        int256 liquidityDelta,
        int256 volumeTraded,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        updatePoolMetrics(
            metaPool,
            poolManager,
            poolId,
            liquidityDelta,
            volumeTraded
        );
        updateUserMetrics(
            metaPool,
            user,
            liquidityDelta,
            volumeTraded,
            tickLower,
            tickUpper
        );
        updateUserPoolMetrics(
            metaPool,
            poolId,
            user,
            liquidityDelta,
            volumeTraded,
            tickLower,
            tickUpper
        );
        updateGlobalMetrics(metaPool, poolManager);
    }

    function getOrAssignPoolIndex(
        MetaPool storage metaPool,
        PoolId poolId
    ) internal returns (uint256) {
        if (metaPool.poolIndexMapping[poolId] == 0) {
            uint256 newIndex = metaPool.activePoolIds.length;
            metaPool.poolIndexMapping[poolId] = newIndex + 1;
            metaPool.globalMetrics.activePoolCount++;
            metaPool.activePoolIds.push(poolId);
        }
        return metaPool.poolIndexMapping[poolId] - 1;
    }

    function updatePoolMetrics(
        MetaPool storage metaPool,
        IPoolManager poolManager,
        PoolId poolId,
        int256 liquidityDelta,
        int256 volumeTraded
    ) private {
        uint256 poolIndex = getOrAssignPoolIndex(metaPool, poolId);

        require(poolIndex / 256 < 256, "Pool index exceeds bitmap capacity");

        uint256 wordIndex = poolIndex / 256;
        uint256 bitIndex = poolIndex % 256;

        if (
            (metaPool.globalMetrics.activePoolsBitmap[wordIndex] &
                (1 << bitIndex)) == 0
        ) {
            metaPool.globalMetrics.activePoolsBitmap[wordIndex] |= (1 <<
                bitIndex);
        }

        PoolMetrics storage poolMetrics = metaPool.pools[poolId];

        (
            ,
            int24 currentTick,
            ,
        ) = StateLibrary.getSlot0(poolManager, poolId);

        uint128 newTotalLiquidity = StateLibrary.getLiquidity(
            poolManager,
            poolId
        );

        poolMetrics.packedData = poolMetrics
            .packedData
            .insertUint(uint256(newTotalLiquidity), 0, 128)
            .insertInt(currentTick, 128, 24);

        poolMetrics.totalVolumeTraded += volumeTraded.abs();

        poolMetrics.liquidityChangeCount += (liquidityDelta != 0) ? 1 : 0;

        updateTickMetrics(poolMetrics, currentTick);

        poolMetrics.apr = APYLibrary.calculateAPR(
            uint256(newTotalLiquidity),
            poolMetrics.totalVolumeTraded
        );

        poolMetrics.apy = APYLibrary.calculateAPY(poolMetrics.apr);

        poolMetrics.volatility = calculateVolatility(poolMetrics);

        poolMetrics.healthScore = calculateHealthScore(
            newTotalLiquidity,
            poolMetrics.totalVolumeTraded,
            poolMetrics.volatility
        );

        poolMetrics.lastUpdateBlock = block.timestamp;
    }

    function updateUserMetrics(
        MetaPool storage metaPool,
        address user,
        int256 liquidityDelta,
        int256 volumeTraded,
        int24 tickLower,
        int24 tickUpper
    ) private {
        UserMetrics storage userMetrics = metaPool.users[user];

        uint256 currentLiquidity = userMetrics.packedData.decodeUint(
            USER_LIQUIDITY_OFFSET,
            128
        );

        uint256 newLiquidity = currentLiquidity + liquidityDelta.abs();

        userMetrics.packedData = userMetrics
            .packedData
            .insertUint(newLiquidity, USER_LIQUIDITY_OFFSET, 128)
            .insertUint(
                uint32(block.timestamp),
                LAST_INTERACTION_TIMESTAMP_OFFSET,
                32
            )
            .insertUint(
                uint32(
                    userMetrics.packedData.decodeUint(
                        ACTION_COUNT_OFFSET,
                        32
                    ) + 1
                ),
                ACTION_COUNT_OFFSET,
                32
            )
            .insertInt(tickLower, TICK_LOWER_OFFSET, 32)
            .insertInt(tickUpper, TICK_UPPER_OFFSET, 32);

        userMetrics.totalVolumeTraded += volumeTraded.abs();

        if (!userMetrics.isInitialized) {
            metaPool.globalMetrics.totalUniqueUsers++;
            userMetrics.isInitialized = true;
        }
    }

    function updateUserPoolMetrics(
        MetaPool storage metaPool,
        PoolId poolId,
        address user,
        int256 liquidityDelta,
        int256 volumeTraded,
        int24 tickLower,
        int24 tickUpper
    ) private {
        UserPoolMetrics storage userPoolMetrics = metaPool.userPoolMetrics[
            user
        ][poolId];

        userPoolMetrics.liquidity += liquidityDelta.abs();

        userPoolMetrics.volumeTraded += volumeTraded.abs();

        userPoolMetrics.tickLower = tickLower;
        userPoolMetrics.tickUpper = tickUpper;
    }

    function updateGlobalMetrics(
        MetaPool storage metaPool,
        IPoolManager poolManager
    ) private {
        GlobalMetrics storage globalMetrics = metaPool.globalMetrics;

        globalMetrics.totalValueLocked = calculateTotalValueLocked(
            metaPool,
            poolManager
        );

        globalMetrics.totalVolumeTraded = calculateTotalVolumeTraded(metaPool);
    }

    function updateTickMetrics(
        PoolMetrics storage poolMetrics,
        int24 currentTick
    ) private {
        if (poolMetrics.lastUpdateBlock != 0) {
            uint256 timeDelta = block.timestamp - poolMetrics.lastUpdateBlock;

            if (timeDelta >= MINIMUM_TIME_DELTA) {
                int256 tickDelta = int256(currentTick - poolMetrics.lastTick);

                int256 newTickMoveSpeed = (tickDelta * 1e18) /
                    int256(timeDelta);

                poolMetrics.priceChangeAcceleration =
                    ((newTickMoveSpeed - poolMetrics.tickMoveSpeed) * 1e18) /
                    int256(timeDelta);

                poolMetrics.tickMoveSpeed = newTickMoveSpeed;
            }
        }
        poolMetrics.lastTick = currentTick;
    }

    function calculateHealthScore(
        uint256 totalLiquidity,
        uint256 volumeTraded,
        uint256 volatility
    ) internal pure returns (uint256) {
        if (totalLiquidity == 0 || volatility == 0) {
            return 0;
        }
        return (volumeTraded * 1e36) / (totalLiquidity * volatility);
    }

    function calculateVolatility(
        PoolMetrics storage poolMetrics
    ) private view returns (uint256) {
        if (poolMetrics.lastUpdateBlock == 0) {
            return 0;
        }

        uint256 timeDelta = block.timestamp - poolMetrics.lastUpdateBlock;

        if (timeDelta >= MINIMUM_TIME_DELTA) {
            return
                uint256(
                    poolMetrics.tickMoveSpeed > 0
                        ? poolMetrics.tickMoveSpeed
                        : -poolMetrics.tickMoveSpeed
                ) / timeDelta;
        } else {
            return 0;
        }
    }

    function calculateTotalValueLocked(
        MetaPool storage metaPool,
        IPoolManager poolManager
    ) private view returns (uint256 tvl) {
        for (uint256 i = 0; i < metaPool.activePoolIds.length; i++) {
            PoolId poolId = metaPool.activePoolIds[i];
            uint128 liquidity = StateLibrary.getLiquidity(poolManager, poolId);
            tvl += uint256(liquidity);
        }
    }

    function calculateTotalVolumeTraded(
        MetaPool storage metaPool
    ) private view returns (uint256 totalVolume) {
        for (uint256 i = 0; i < metaPool.activePoolIds.length; i++) {
            totalVolume += metaPool
                .pools[metaPool.activePoolIds[i]]
                .totalVolumeTraded;
        }
    }

    function getMetaPoolStats(
        MetaPool storage metaPool
    )
        internal
        view
        returns (
            uint256 totalValueLocked,
            uint256 totalVolumeTraded,
            uint256 activePoolCount,
            uint256 totalUniqueUsers
        )
    {
        return (
            metaPool.globalMetrics.totalValueLocked,
            metaPool.globalMetrics.totalVolumeTraded,
            metaPool.globalMetrics.activePoolCount,
            metaPool.globalMetrics.totalUniqueUsers
        );
    }

    function getPoolStats(
        MetaPool storage metaPool,
        IPoolManager /*poolManager*/,
        PoolId poolId
    )
        internal
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
        )
    {
        PoolMetrics storage poolMetrics = metaPool.pools[poolId];

        totalLiquidity = poolMetrics.packedData.decodeUint(0, 128);
        currentTick = int24(poolMetrics.packedData.decodeInt(128, 24));
        volumeTraded = poolMetrics.totalVolumeTraded;
        apr = poolMetrics.apr;
        apy = poolMetrics.apy;
        healthScore = poolMetrics.healthScore;
        volatility = poolMetrics.volatility;
        zapInOutCount = poolMetrics.zapInOutCount;
        liquidityChangeCount = poolMetrics.liquidityChangeCount;
        tickMoveSpeed = poolMetrics.tickMoveSpeed;
        priceChangeAcceleration = poolMetrics.priceChangeAcceleration;
    }

    function getUserStats(
        MetaPool storage metaPool,
        PoolId,
        address user
    )
        internal
        view
        returns (
            uint256 totalLiquidity,
            uint256 totalVolume,
            uint256 actionCount
        )
    {
        UserMetrics storage userMetrics = metaPool.users[user];
        totalLiquidity = userMetrics.packedData.decodeUint(
            USER_LIQUIDITY_OFFSET,
            128
        );
        totalVolume = userMetrics.totalVolumeTraded;
        actionCount = userMetrics.packedData.decodeUint(
            ACTION_COUNT_OFFSET,
            32
        );
    }

    function isNewUser(
        MetaPool storage metaPool,
        address user
    ) internal view returns (bool) {
        return !metaPool.users[user].isInitialized;
    }

    function getLiquidityUtilization(
        MetaPool storage metaPool,
        IPoolManager poolManager,
        PoolId poolId,
        address user
    ) internal view returns (uint256) {
        uint128 totalLiquidity = StateLibrary.getLiquidity(poolManager, poolId);
        uint256 userLiquidity = metaPool.users[user].packedData.decodeUint(
            USER_LIQUIDITY_OFFSET,
            128
        );

        if (totalLiquidity == 0) {
            return 0;
        }
        return (userLiquidity * 1e18) / uint256(totalLiquidity);
    }

    function getActivityScore(
        MetaPool storage metaPool,
        PoolId poolId,
        address user
    ) internal view returns (uint256) {
        PoolMetrics storage poolMetric = metaPool.pools[poolId];
        uint32 actionCount = uint32(
            metaPool.users[user].packedData.decodeUint(
                ACTION_COUNT_OFFSET,
                32
            )
        );

        if (block.timestamp <= poolMetric.lastUpdateBlock) return 0;
        return
            (uint256(actionCount) * 1e18) /
            (block.timestamp - poolMetric.lastUpdateBlock);
    }

    function deactivatePool(MetaPool storage metaPool, PoolId poolId) internal {
        uint256 poolIndex = metaPool.poolIndexMapping[poolId] - 1;
        require(
            poolIndex < metaPool.activePoolIds.length,
            "Invalid pool index"
        );

        metaPool.activePoolIds[poolIndex] = metaPool.activePoolIds[
            metaPool.activePoolIds.length - 1
        ];
        metaPool.activePoolIds.pop();

        uint256 wordIndex = poolIndex / 256;
        uint256 bitIndex = poolIndex % 256;
        metaPool.globalMetrics.activePoolsBitmap[wordIndex] &= ~(1 << bitIndex);

        metaPool.globalMetrics.activePoolCount--;
    }
}
