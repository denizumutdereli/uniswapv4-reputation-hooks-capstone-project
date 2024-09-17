// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MetaPoolLibrary} from "./libs/MetaPoolLibrary.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IHookOracle} from "./interfaces/IHookOracle.sol";

/**
 * @title HookOracle - Experimental
 * @dev A contract that acts as a hook for retrieving user statistics from a reputation hook contract.
 */
contract HookOracle is IHookOracle {
    IHookOracle public reputationHook;

    address public admin;
    /**
     * @dev Emitted when the HookOracle fails to retrieve user statistics.
     */
    error HookOracleFailed();

    /**
     * @dev Initializes the HookOracle contract.
     * @param _reputationHook The address of the reputation hook contract.
     * @param _admin The address of the admin.
     */
    constructor(address _reputationHook, address _admin) {
        reputationHook = IHookOracle(_reputationHook);
        admin = _admin;
    }

    /**
     * @dev Retrieves the user statistics for a specific pool and user.
     * @param poolId The ID of the pool.
     * @param user The address of the user.
     * @return totalLiquidity The total liquidity of the user in the pool.
     * @return totalVolume The total volume of the user in the pool.
     * @return actionCount The total number of actions performed by the user in the pool.
     */
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
        )
    {
        try reputationHook.getUserStats(poolId, user) returns (
            uint256 _totalLiquidity,
            uint256 _totalVolume,
            uint256 _actionCount
        ) {
            totalLiquidity = _totalLiquidity;
            totalVolume = _totalVolume;
            actionCount = _actionCount;
        } catch {
            revert HookOracleFailed();
        }
    }
}
