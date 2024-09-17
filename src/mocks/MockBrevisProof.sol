// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IBrevisProof} from "../interfaces/IBrevisProof.sol";

/// @title MockBrevisProof
/// @dev A mock implementation of the IBrevisProof interface for testing purposes.
contract MockBrevisProof is IBrevisProof {
    /// @notice Submits a proof to the contract.
    /// @param _chainId The chain ID.
    /// @param _proofWithPubInputs The proof data with public inputs.
    /// @param _withAppProof A flag indicating whether the proof includes application-specific data.
    /// @return The hash of the submitted proof.
    function submitProof(
        uint64 _chainId,
        bytes calldata _proofWithPubInputs,
        bool _withAppProof
    ) external pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(_chainId, _proofWithPubInputs, _withAppProof)
            );
    }

    /// @notice Checks if a proof exists.
    /// param _proofId The ID of the proof.
    /// @return A boolean indicating whether the proof exists.
    function hasProof(bytes32 /*_proofId*/) external pure override returns (bool) {
        return true;
    }

    /// @notice Validates a request.
    /// @param _proofId The ID of the proof.
    /// @param _chainId The chain ID.
    /// @param _extractInfos The extraction information.
    function validateRequest(
        bytes32 _proofId,
        uint64 _chainId,
        IBrevisProof.ExtractInfos memory _extractInfos
    ) external pure override {}

    /// @notice Retrieves proof data.
    /// param _proofId The ID of the proof.
    /// @return The proof data.
    function getProofData(bytes32 /*_proofId*/) external pure override returns (IBrevisProof.ProofData memory) {
        return
            IBrevisProof.ProofData({
                commitHash: bytes32(0),
                length: 0,
                vkHash: bytes32(0),
                appCommitHash: bytes32(0),
                appVkHash: bytes32(0),
                smtRoot: bytes32(0)
            });
    }

    function getProofAppData(bytes32) external pure returns (bytes32, bytes32) {
        return (bytes32(0), bytes32(0));
    }

    function verifyProof(
        bytes32 _requestId,
        bytes calldata _proof
    ) external virtual {}
}
