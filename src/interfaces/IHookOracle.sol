// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

interface IHookOracle {
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
}
