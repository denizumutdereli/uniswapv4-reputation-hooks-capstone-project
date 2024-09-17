// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IBrevisProof as Brevis} from "./IBrevisProof.sol";

interface IReputationOracle {
    // Events
    event UserPointsUpdated(
        address indexed user,
        uint256 pROPoints,
        uint256 ROPoints,
        bytes32 identityHash
    );
    event ReputationUpdateBatchProcessed(
        bytes32 indexed requestId,
        uint256 batchId,
        uint256 nonce,
        uint256 updatesProcessed
    );
    event ProofRequestInitiated(
        bytes32 indexed requestId,
        uint64 chainId,
        address reputationLogic
    );
    event PoolRegistered(
        address indexed poolAddress,
        uint256 collateral,
        uint256 mintedTokens
    );
    event PoolUnregistered(address indexed poolAddress);
    event CollateralSlashed(address indexed poolAddress, uint256 slashedAmount);
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    event CollateralAdjusted(uint256 newRequiredFee);
    event CollateralDeposited(address indexed poolAddress, uint256 amount);
    // Structs
    struct UserInfo {
        uint256 pROPoints;
        uint256 ROPoints;
        uint256 lastUpdateTimestamp;
        bytes32 identityHash;
    }

    struct PoolInfo {
        uint256 collateral; // Amount of staked collateral
        uint256 lastActivityTimestamp; // Timestamp of the last activity
        bool isRegistered; // Registration status
        address reputationLogic; // Associated reputation logic contract
    }

    // Functions
    function getUserPoints(address user) external view returns (uint256);

    function getUserInfo(
        address user
    )
        external
        view
        returns (
            uint256 pROPoints,
            uint256 ROPoints,
            uint256 lastUpdateTimestamp,
            bytes32 identityHash
        );

    function getPoolInfo(
        address poolAddress
    )
        external
        view
        returns (
            uint256 collateral,
            uint256 lastActivityTimestamp,
            bool isRegistered,
            address reputationLogic
        );

    function registerPool(
        address reputationHook,
        address reputationLogic
    ) external payable;

    function depositFeeCollateral(address reputationLogic) external payable;

    function unregisterPool(address reputationLogic) external;

    function initiateReputationUpdateBatch(
        uint256 batchId,
        uint256 nonce,
        uint64 chainId
    ) external payable returns (bytes32);

    function submitProof(bytes32 _requestId, bytes calldata _proof) external;

    function adjustRequiredCollateral() external;

    function checkAndSlashInactivePools() external;

    function getRegisteredPools() external view returns (address[] memory);

    function setVkHash(bytes32 _vkHash) external;

    function withdrawFeesTo(address payable recipient) external;

    function requestToBatchId(
        bytes32 requestId
    ) external view returns (uint256);

    function requestToNonce(bytes32 requestId) external view returns (uint256);

    function requestToPool(bytes32 requestId) external view returns (address);

    function getRequiredFee() external view returns (uint256);

    function getRequiredCollateral() external view returns (uint256);

    function getVkHash() external view returns (bytes32);
}
