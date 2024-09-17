// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IReputationOracle} from "./IReputationOracle.sol";
import {IReputationLogic} from "./IReputationLogic.sol";

interface IReputationHook {
    struct Pools {
        bytes32 configData;
        bool isActive;
        address admin;
        IReputationOracle reputationOracle;
        IReputationLogic reputationLogic;
    }

    struct Stats {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        int256 volumeTraded;
    }

    struct Context {
        PoolKey key;
        address user;
        Stats stats;
    }

    event LiquidityModified(
        address indexed user,
        PoolId indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    );

    event PoolConfigUpdated(
        PoolId indexed poolId,
        uint24 newBaseFee,
        uint24 newAutomationInterval,
        bool newIsDynamicFee
    );

    
    event PoolCreated(PoolId indexed poolId);
    event PoolDeleted(PoolId indexed poolId);
    event PoolActivated(PoolId indexed poolId);
    event PoolDeactivated(PoolId indexed poolId);
    event AutomationIntervalUpdated(PoolId indexed poolId, uint24 newInterval);

    event CollateralDeposited(
        address indexed user,
        uint256 amount,
        PoolId poolId
    );
    event OracleRegistered(address indexed user, PoolId poolId, uint256 value);
    event OracleUnregistered(address indexed user, PoolId poolId);
    event HookAdminUpdated(address indexed newHookAdmin);
  
    event CustomPoolHookSet(PoolId indexed poolId, address hookAddress);
    error Unauthorized();
    error PoolNotInitialized();
    error PoolNotActive();
    error PoolNotExist();

    error MustUseDynamicFee();
    error InsufficientRegistrationFee();
    error ReputationLogicDeploymentFailed();
    error CollateralAmountTooLow();
    function depositFeeCollateral(PoolKey calldata key) external payable;

    function registerToOracle(PoolKey calldata key) external payable;

    function unregisterFromOracle(PoolKey calldata key) external;
}
