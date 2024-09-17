// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "Solidity-RLP/RLPReader.sol";

library Brevis {
    uint256 constant NumField = 5; // supports at most 5 fields per receipt log

    struct ReceiptInfo {
        uint64 blkNum;
        uint64 receiptIndex; // ReceiptIndex in the block
        LogInfo[NumField] logs;
    }

    struct LogInfo {
        LogExtraInfo logExtraInfo;
        uint64 logIndex; // LogIndex of the field
        bytes32 value;
    }

    struct LogExtraInfo {
        uint8 valueFromTopic;
        uint64 valueIndex; // index of the fields in topic or data
        address contractAddress;
        bytes32 logTopic0;
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

    struct ExtractInfos {
        bytes32 smtRoot;
        ReceiptInfo[] receipts;
        StorageInfo[] stores;
        TransactionInfo[] txs;
    }

    // retrieved from proofData, to align the logs with circuit...
    struct ProofData {
        bytes32 commitHash;
        uint256 length; // for contract computing proof only
        bytes32 vkHash;
        bytes32 appCommitHash; // zk-program computing circuit commit hash
        bytes32 appVkHash; // zk-program computing circuit Verify Key hash
        bytes32 smtRoot; // for zk-program computing proof only
    }
}

library Tx {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    struct TxInfo {
        uint64 chainId;
        uint64 nonce;
        uint256 gasTipCap;
        uint256 gasFeeCap;
        uint256 gas;
        address to;
        uint256 value;
        bytes data;
        address from; // calculate from V R S
    }

    // support DynamicFeeTxType for now
    function decodeTx(bytes memory txRaw) public pure returns (TxInfo memory info) {
        uint8 txType = uint8(txRaw[0]);
        require(txType == 2, "not a DynamicFeeTxType");

        bytes memory rlpData = new bytes(txRaw.length - 1);
        for (uint i = 1; i < txRaw.length; i++) {
            rlpData[i-1] = txRaw[i];
        }

        RLPReader.RLPItem[] memory values = rlpData.toRlpItem().toList();
        
        info.chainId = uint64(values[0].toUint());
        info.nonce = uint64(values[1].toUint());
        info.gasTipCap = values[2].toUint();
        info.gasFeeCap = values[3].toUint();
        info.gas = values[4].toUint();
        info.to = values[5].toAddress();
        info.value = values[6].toUint();
        info.data = values[7].toBytes();

        uint8 v = uint8(values[9].toUint());
        bytes32 r = bytes32(values[10].toUint());
        bytes32 s = bytes32(values[11].toUint());

        bytes memory unsignedTxRaw = removeSignature(txRaw);
        info.from = recover(keccak256(unsignedTxRaw), r, s, v);
    }

    function removeSignature(bytes memory txRaw) internal pure returns (bytes memory) {
        uint256 unsignedLength = txRaw.length - 65;
        bytes memory unsignedTxRaw = new bytes(unsignedLength);
        
        for (uint i = 0; i < unsignedLength; i++) {
            unsignedTxRaw[i] = txRaw[i];
        }
        
        // Adjust the length field
        uint8 lengthByte = uint8(unsignedTxRaw[1]);
        if (lengthByte > 0xf7) {
            uint8 lenBytes = lengthByte - 0xf7;
            uint256 length = 0;
            for (uint8 i = 0; i < lenBytes; i++) {
                length = (length << 8) | uint8(unsignedTxRaw[2 + i]);
            }
            length -= 3; // Subtract 3 for r, s, v
            for (uint8 i = 0; i < lenBytes; i++) {
                unsignedTxRaw[1 + lenBytes - i] = bytes1(uint8(length));
                length >>= 8;
            }
        } else {
            unsignedTxRaw[1] = bytes1(lengthByte - 3);
        }

        return unsignedTxRaw;
    }

    function recover(bytes32 message, bytes32 r, bytes32 s, uint8 v) internal pure returns (address) {
        if (v < 27) {
            v += 27;
        }
        return ecrecover(message, v, r, s);
    }
}