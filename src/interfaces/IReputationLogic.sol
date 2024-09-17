// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReputationTypes} from "../libs/ReputationTypes.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IReputationLogic is IERC165 {
    // Structs
    struct UserAction {
        int256 amount;
        bool zeroForOne;
        int256 specifiedAmount;
        uint256 timestamp;
    }

    struct BatchData {
        address[] users;
        ReputationTypes.SwapInfo[] swapInfos;
        ReputationTypes.TickInfo[] tickInfos;
        ReputationTypes.TokenInfo[] tokenInfos;
        ReputationTypes.MetricsInfo[] metricsInfos;
    }

    // Events
    event ReputationLogicConfigSettled(
        address indexed admin,
        address indexed reputationOracle,
        uint256 automationInterval
    );

    event UserPointsUpdated(address indexed user, uint256 newPoints);

    event UserActionRecorded(
        address indexed user,
        int256 amount,
        bool zeroForOne,
        int256 specifiedAmount,
        uint256 timestamp
    );

    event ReputationUpdateQueued(
        address indexed user,
        uint256 indexed queueIndex,
        bytes32 swapInfoHash,
        bytes32 tickInfoHash,
        bytes32 tokenInfoHash,
        bytes32 metricsInfoHash
    );

    event ReputationUpdateBatchEmitted(
        uint256 indexed batchId,
        uint256 indexed nonce,
        address[] users,
        uint256 updatesToProcess,
        bytes32[] swapInfoHashes,
        bytes32[] tickInfoHashes,
        bytes32[] tokenInfoHashes,
        bytes32[] metricsInfoHashes,
        address indexed hookAddress
    );

    event UpdateReputationOracle(
        address indexed oldOracle,
        address indexed newOracle
    );

    event UpdateAutomationInterval(uint256 indexed newInterval);
    event UpdateBatchSize(uint256 indexed newSize);
    event UpdateCoolDownPeriod(uint256 indexed newPeriod);
    event RoTokensDeposited(address indexed user, uint256 indexed amount);
    event RoTokensWithdrawn(address indexed user, uint256 indexed amount);
    event NoQueueEvent();
    
    // Errors
    error InsufficientBalanceForOperation();
    error InsufficientFeeCollateral();
    error InvalidFeeCollateral();
    error Unauthorized();
    error InvalidAutomationInterval();
    error InvalidBatchSize();
    error InvalidCooldDownPeriod();
    error NoQueue();
    error Processing();
    error FailedInitiateProofRequest();

    // Functions
    function performUpkeep(bytes calldata /* performData */) external;

    function queueReputationUpdate(
        ReputationTypes.ReputationUpdate calldata update
    ) external returns (bool);

    function getUpdateQueue()
        external
        view
        returns (ReputationTypes.ReputationUpdate[] memory);

    function getUpdateQueueLength() external view returns (uint256);

    function clearProcessedBatch(uint256 batchId) external;

    function setAutomationInterval(uint256 _newInterval) external;

    function setBatchSize(uint256 _batchSize) external;

    function setCooldownPeriod(uint256 _cooldown) external;

    function getAdmin() external view returns (address);

    function getReputationOracle() external view returns (address);

    function getBatchSize() external view returns (uint256);

    function getAutomationInterval() external view returns (uint256);

    function getHookHasPermitted(
        address _hookAddress
    ) external view returns (bool);

    function getCoolDownPeriod() external view returns (uint256);

    function getBatchData(
        uint256 batchId
    )
        external
        view
        returns (
            address[] memory users,
            ReputationTypes.SwapInfo[] memory swapInfos,
            ReputationTypes.TickInfo[] memory tickInfos,
            ReputationTypes.TokenInfo[] memory tokenInfos,
            ReputationTypes.MetricsInfo[] memory metricsInfos
        );

    function registerToOracle() external payable;

    function unregisterFromOracle() external;

    function withdrawFeesTo(address payable recipient) external;
    function setReputationOracle(address _reputationOracle) external;
}
