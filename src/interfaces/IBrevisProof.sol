// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBrevisProof {
    struct ExtractInfos {
        ReceiptInfo[] receipts;
        StorageInfo[] stores;
        TransactionInfo[] txs;
        bytes32 smtRoot;
    }

    struct ReceiptInfo {
        uint64 blkNum;
        uint64 receiptIndex;
        LogInfo[] logs;
    }

    struct StorageInfo {
        bytes32 blockHash;
        address account;
        bytes32 slot;
        bytes32 slotValue;
        uint64 blockNumber;
    }

    struct TransactionInfo {
        bytes32 leafHash;
        bytes32 blockHash;
        uint64 blockNumber;
        uint64 blockTime;
        bytes leafRlpPrefix;
    }

    struct LogInfo {
        LogExtraInfo logExtraInfo;
        uint64 logIndex;
        bytes32 value;
    }

    struct LogExtraInfo {
        uint8 valueFromTopic;
        uint64 valueIndex;
        address contractAddress;
        bytes32 logTopic0;
    }

    struct ProofData {
        bytes32 commitHash;
        uint256 length;
        bytes32 vkHash;
        bytes32 appCommitHash;
        bytes32 appVkHash;
        bytes32 smtRoot;
    }

    function submitProof(
        uint64 _chainId,
        bytes calldata _proofWithPubInputs,
        bool _withAppProof
    ) external returns (bytes32 _requestId);

    function hasProof(bytes32 _requestId) external view returns (bool);

    function validateRequest(
        bytes32 _requestId,
        uint64 _chainId,
        ExtractInfos memory _extractInfos
    ) external view;

    function verifyProof(bytes32 _requestId, bytes calldata _proof) external;

    function getProofAppData(bytes32 _requestId) external view returns (bytes32 appCommitHash, bytes32 appVkHash);

    function getProofData(bytes32 _requestId) external view returns (ProofData memory);
}