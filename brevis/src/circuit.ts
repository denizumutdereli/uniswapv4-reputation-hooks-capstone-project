import { ProofRequest, asBytes32 } from 'brevis-sdk-typescript';
import { ethers } from 'ethers';

export interface SwapInfo {
  amount0: string;
  amount1: string;
  zeroForOne: boolean;
  amountSpecified: string;
}

export interface TickInfo {
  currentTick: number;
  lastTick: number;
}

export interface TokenInfo {
  token0: string;
  token1: string;
}

export interface MetricsInfo {
  liquidityUtilization: string;
  tickRange: number;
  activityScore: string;
}

// Function to ensure the value is properly converted to bytes32
function toBytes32(value: ethers.BigNumber | string): Uint8Array {
  let hexValue: string;
  if (ethers.BigNumber.isBigNumber(value)) {
    hexValue = value.toHexString();
  } else {
    hexValue = value;
  }
  hexValue = ethers.utils.hexlify(ethers.utils.arrayify(hexValue));
  const result = ethers.utils.zeroPad(ethers.utils.arrayify(hexValue), 32);
  console.log(`toBytes32 - Value: ${hexValue}, Result: ${result}`);
  return result;
}

export async function generateProof(
  batchId: ethers.BigNumber,
  nonce: ethers.BigNumber,
  users: string[],
  swapInfos: SwapInfo[],
  tickInfos: TickInfo[],
  tokenInfos: TokenInfo[],
  metricsInfos: MetricsInfo[]
): Promise<{
  proofReq: ProofRequest;
  customInput: any;
  points: ethers.BigNumber[];
  identityHashes: string[];
}> {
  const proofReq = new ProofRequest();

  // Perform simple calculations (e.g., sum of metrics)
  const points = metricsInfos.map((info) => {
    const liquidityScore = ethers.BigNumber.from(info.liquidityUtilization);
    const activityScore = ethers.BigNumber.from(info.activityScore);
    const totalScore = liquidityScore.add(activityScore);
    console.log(`Points Calculation - Liquidity: ${liquidityScore}, Activity: ${activityScore}, Total: ${totalScore}`);
    return totalScore;
  });

  // Generate identity hashes (for PoC)
  const identityHashes = users.map((user) => {
    // Directly use the user string assuming it's a valid hex string
    if (!ethers.utils.isHexString(user)) {
      console.error(`Invalid hex string for user: ${user}`);
      throw new Error(`Invalid hex string: ${user}`);
    }
    const hash = ethers.utils.keccak256(user); // Directly hash the user hex string
    console.log(`Identity Hash - User: ${user}, Hash: ${hash}`);
    return hash;
  });

  try {
    // Prepare custom input
    const customInput = {
      BatchId: asBytes32(ethers.utils.hexlify(toBytes32(batchId))), // Properly convert to bytes32
      Nonce: asBytes32(ethers.utils.hexlify(toBytes32(nonce))), // Properly convert to bytes32
      Users: users.map((user) => {
        // Convert user hex string directly to bytes32
        const userBytes = ethers.utils.arrayify(user); // Ensure the user is treated as a hex string
        const paddedUserArray = ethers.utils.zeroPad(userBytes, 32);
        const hexUser = ethers.utils.hexlify(paddedUserArray);
        console.log(`User Mapping - User: ${user}, Bytes: ${userBytes}, Padded: ${paddedUserArray}, Hex: ${hexUser}`);
        return asBytes32(hexUser);
      }),
      Points: points.map((point) => {
        const bytes32Point = toBytes32(point);
        const hexPoint = ethers.utils.hexlify(bytes32Point);
        console.log(`Points Mapping - Point: ${point}, Bytes32: ${bytes32Point}, Hex: ${hexPoint}`);
        return asBytes32(hexPoint);
      }),
      IdentityHashes: identityHashes.map((hash) => {
        const arrayHash = ethers.utils.arrayify(hash);
        const hexHash = ethers.utils.hexlify(arrayHash);
        console.log(`Identity Hash Mapping - Hash: ${hash}, Array: ${arrayHash}, Hex: ${hexHash}`);
        return asBytes32(hexHash);
      }),
      UpdatesToProcess: asBytes32(
        ethers.utils.hexlify(toBytes32(ethers.BigNumber.from(users.length)))
      ), // Convert the number of users to bytes32
    };

    // Set custom inputs for the proof
    proofReq.setCustomInput(customInput);

    console.log('Generated Proof Request:', proofReq);
    console.log('Custom Input:', customInput);

    return { proofReq, customInput, points, identityHashes };
  } catch (error) {
    console.error('Error in processing event:', error);
    throw error; // Re-throw after logging
  }
}
