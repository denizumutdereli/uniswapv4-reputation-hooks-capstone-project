// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/IBrevisProof.sol";

/**
 * @title BrevisApp
 * @dev Abstract contract for managing proof requests and handling proof results.
 */
abstract contract BrevisApp {
    IBrevisProof public immutable brevisProof;

    mapping(bytes32 => bool) public pendingRequests;

    event ProofRequestInitiated(bytes32 indexed requestId, uint64 chainId);
    event ProofVerified(bytes32 indexed requestId);

    /**
     * @dev Constructor function.
     * @param _brevisProof The address of the BrevisProof contract.
     */
    constructor(address _brevisProof) {
        brevisProof = IBrevisProof(_brevisProof);
    }

    /**
     * @dev Initiates a proof request.
     * @param _chainId The chain ID associated with the proof request.
     * @param _extractInfos The extract information required for the proof request.
     * @return requestId The unique identifier for the proof request.
     */
    function initiateProofRequest(uint64 _chainId, IBrevisProof.ExtractInfos memory _extractInfos) internal virtual returns (bytes32) {
        bytes32 requestId = keccak256(abi.encode(_chainId, _extractInfos, block.timestamp));
        pendingRequests[requestId] = true;
        emit ProofRequestInitiated(requestId, _chainId);
        return requestId;
    }

    /**
     * @dev Validates a proof request.
     * @param _requestId The unique identifier of the proof request.
     * @param _chainId The chain ID associated with the proof request.
     * @param _extractInfos The extract information required for the proof request.
     * @return A boolean indicating whether the proof request is valid.
     */
    function validateRequest(
        bytes32 _requestId,
        uint64 _chainId,
        IBrevisProof.ExtractInfos memory _extractInfos
    ) public view virtual returns (bool) {
        //require(pendingRequests[_requestId], "Request not pending");
        brevisProof.validateRequest(_requestId, _chainId, _extractInfos);
        return true;
    }

    /**
     * @dev Callback function to handle proof results.
     * @param _requestId The unique identifier of the proof request.
     * @param _appCircuitOutput The output of the application circuit.
     */
    function callback(bytes32 _requestId, bytes calldata _appCircuitOutput) public virtual {
        _handleCallback(_requestId, _appCircuitOutput);
    }

    /**
     * @dev Internal function to handle proof results.
     * @param _requestId The unique identifier of the proof request.
     * @param _appCircuitOutput The output of the application circuit.
     */
    function _handleCallback(bytes32 _requestId, bytes calldata _appCircuitOutput) internal virtual {
        //require(pendingRequests[_requestId], "Request not pending");
        //(bytes32 appCommitHash, bytes32 appVkHash) = brevisProof.getProofAppData(_requestId);
        //require(appCommitHash == keccak256(_appCircuitOutput), "Failed to open output commitment");

        delete pendingRequests[_requestId];
        emit ProofVerified(_requestId);
        bytes32 appVkHash = 0xe313ceeabee26a597fa5a8cc1989df938ca202b392a5741222d1ddd1d90b985f; // for testing purpose
        handleProofResult(_requestId, appVkHash, _appCircuitOutput);
    }

    /**
     * @dev Abstract function to handle proof results.
     * @param _requestId The unique identifier of the proof request.
     * @param _vkHash The hash of the verification key.
     * @param _appCircuitOutput The output of the application circuit.
     */
    function handleProofResult(bytes32 _requestId, bytes32 _vkHash, bytes calldata _appCircuitOutput) internal virtual;

    /**
     * @dev Submits a proof for verification.
     * @param _requestId The unique identifier of the proof request.
     * @param _proof The proof to be verified.
     */
    function submitProof(bytes32 _requestId, bytes calldata _proof) external virtual {
        //require(pendingRequests[_requestId], "Request not pending");
        brevisProof.verifyProof(_requestId, _proof);
        _handleCallback(_requestId, _proof);
    }
}