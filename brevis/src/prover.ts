import { ProofRequest, ProveResponse } from 'brevis-sdk-typescript';
import { ethers } from 'ethers';

export class MockProver {
  constructor(private endpoint: string) {}

  async prove(proofReq: ProofRequest, customInput: any): Promise<ProveResponse> {
    // Extract bytes data
    const usersBytes = customInput.Users.map((user: any) => ethers.utils.arrayify(user.data));
    const pointsBytes = customInput.Points.map((point: any) => ethers.utils.arrayify(point.data));
    const identityHashesBytes = customInput.IdentityHashes.map((hash: any) => ethers.utils.arrayify(hash.data));
    const batchIdBytes = ethers.utils.arrayify(customInput.BatchId.data);
    const nonceBytes = ethers.utils.arrayify(customInput.Nonce.data);
    const updatesProcessedBytes = ethers.utils.arrayify(customInput.UpdatesToProcess.data);

    // Convert bytes back to usable formats
    const users = usersBytes.map((userBytes: Uint8Array) =>
      ethers.utils.getAddress(ethers.utils.hexlify(userBytes.slice(-20)))
    );
    const scores = pointsBytes.map((pointBytes: Uint8Array) =>
      ethers.BigNumber.from(pointBytes)
    );
    const identityHashes = identityHashesBytes.map(
      (hashBytes: Uint8Array) => ethers.utils.hexlify(hashBytes)
    );
    const batchId = ethers.BigNumber.from(batchIdBytes);
    const nonce = ethers.BigNumber.from(nonceBytes);
    const updatesProcessed = ethers.BigNumber.from(updatesProcessedBytes);

    // Create the app circuit output expected by the ReputationOracle
    const appCircuitOutput = ethers.utils.defaultAbiCoder.encode(
      ['address[]', 'int256[]', 'bytes32[]', 'uint256', 'uint256', 'uint256'],
      [users, scores, identityHashes, batchId, nonce, updatesProcessed]
    );

    const outputCommitment = ethers.utils.keccak256(appCircuitOutput);

    const vkHash = "0xe313ceeabee26a597fa5a8cc1989df938ca202b392a5741222d1ddd1d90b985f";

    // Create the structured proof
    const proof = ethers.utils.defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes'],
      [vkHash, outputCommitment, appCircuitOutput]
    );

    console.log('Generated Proof:');
    console.log('vkHash:', vkHash);
    console.log('outputCommitment:', outputCommitment);
    console.log('appCircuitOutput:', appCircuitOutput);
    console.log('Encoded Proof:', proof);

    // Create the ProveResponse
    const response: ProveResponse = {
      err: null,
      proof: proof,
      circuit_info: {
        output_commitment: outputCommitment,
        vk: vkHash,
        input_commitments: [ethers.utils.keccak256(ethers.utils.toUtf8Bytes("input"))],
        toggles_commitment: ethers.utils.keccak256(ethers.utils.toUtf8Bytes("toggles")),
        toggles: [true, false],
        use_callback: false,
        output: appCircuitOutput,
        vk_hash: vkHash,
      },
    };

    console.log('Proof:', response.proof);
    console.log('Offchain vkHash:', response.circuit_info.vk_hash);
    console.log('Output Commitment:', response.circuit_info.output_commitment);
    console.log('Encoded App Circuit Output:', response.circuit_info.output);
    
    return response;
  }
}