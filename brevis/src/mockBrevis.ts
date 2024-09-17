// mockBrevis.ts

import { ProofRequest } from 'brevis-sdk-typescript';
import { ethers } from 'ethers';

export class MockBrevis {
  async submit(
    proofReq: ProofRequest,
    proofRes: any,
    srcChainId: number,
    destChainId: number,
    option: number,
    apiKey: string,
    callbackAddress: string
  ) {
    return {
      queryKey: {
        query_hash: ethers.utils.hexlify(ethers.utils.randomBytes(32)),
      },
      proof: proofRes.proof,
      fee: '0.01',
    };
  }

  async wait(queryKey: any, chainId: number) {
    return {
      success: true,
      queryKey: queryKey,
      proof: ethers.utils.hexlify(ethers.utils.randomBytes(256)),
    };
  }
}
