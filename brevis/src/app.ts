// app.ts

import { Field, ReceiptData } from "brevis-sdk-typescript";
import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import {
  generateProof,
  MetricsInfo,
  SwapInfo,
  TickInfo,
  TokenInfo,
} from "./circuit";
import { MockBrevis } from "./mockBrevis";
import { MockProver } from "./prover";

async function generateAndSubmitProof(
  requestId: string,
  batchId: ethers.BigNumber,
  nonce: ethers.BigNumber,
  users: string[],
  swapInfosRaw: any[],
  tickInfosRaw: any[],
  tokenInfosRaw: any[],
  metricsInfosRaw: any[],
  reputationLogicAddress: string,
  event: ethers.Event,
  reputationOracleContract: ethers.Contract
) {
  // Construct the ReceiptData object using event details
  const receiptData = new ReceiptData({
    block_num: event.blockNumber,
    tx_hash: event.transactionHash,
    fields: [
      new Field({
        contract: reputationLogicAddress,
        log_index: event.logIndex,
        event_id: ethers.utils.id(
          "ReputationUpdateBatchEmitted(uint256,uint256,address[],uint256,bytes32[],bytes32[],bytes32[],bytes32[],address)"
        ),
        is_topic: true,
        field_index: 0,
        value: ethers.utils.hexZeroPad(batchId.toHexString(), 32),
      }),
      new Field({
        contract: reputationLogicAddress,
        log_index: event.logIndex,
        event_id: ethers.utils.id(
          "ReputationUpdateBatchEmitted(uint256,uint256,address[],uint256,bytes32[],bytes32[],bytes32[],bytes32[],address)"
        ),
        is_topic: true,
        field_index: 1,
        value: ethers.utils.hexZeroPad(nonce.toHexString(), 32),
      }),
    ],
  });

  // Map raw data to typed objects
  const swapInfos: SwapInfo[] = swapInfosRaw.map((swapInfo: any) => ({
    amount0: swapInfo.amount0.toString(),
    amount1: swapInfo.amount1.toString(),
    zeroForOne: swapInfo.zeroForOne,
    amountSpecified: swapInfo.amountSpecified.toString(),
  }));

  const tickInfos: TickInfo[] = tickInfosRaw.map((tickInfo: any) => ({
    currentTick: tickInfo.currentTick,
    lastTick: tickInfo.lastTick,
  }));

  const tokenInfos: TokenInfo[] = tokenInfosRaw.map((tokenInfo: any) => ({
    token0: tokenInfo.token0,
    token1: tokenInfo.token1,
  }));

  const metricsInfos: MetricsInfo[] = metricsInfosRaw.map(
    (metricsInfo: any) => ({
      liquidityUtilization: metricsInfo.liquidityUtilization.toString(),
      tickRange: metricsInfo.tickRange,
      activityScore: metricsInfo.activityScore.toString(),
    })
  );

  // Generate the proof request and get points and identity hashes
  const { proofReq, customInput, points, identityHashes } = await generateProof(
    batchId,
    nonce,
    users,
    swapInfos,
    tickInfos,
    tokenInfos,
    metricsInfos
  );

  // Add the receipt data to the proof request
  proofReq.addReceipt(receiptData);

  const prover = new MockProver("localhost:33247");
  const proofRes = await prover.prove(proofReq, customInput);

  if (proofRes.err) {
    console.error("Error generating proof:", proofRes.err.msg);
    throw new Error(`Error generating proof: ${proofRes.err.msg}`);
  }

  const brevis = new MockBrevis();
  const option = 0; // QueryOption.ZK_MODE in real implementation
  const apiKey = "MYKEY"; // Dummy value in mock mode
  const callbackAddress = "0x5081a39b8A5f0E35a8D959395a630b68B74Dd30f";

  const brevisRes = await brevis.submit(
    proofReq,
    proofRes,
    31337, // Source chain ID (e.g., local hardhat network)
    31337, // Destination chain ID
    option,
    apiKey,
    callbackAddress
  );

  console.log(`Proof submitted to Brevis. Query Key:`, brevisRes.queryKey);
  console.log(`Fee: ${brevisRes.fee}`);

  const finalResult = await brevis.wait(brevisRes.queryKey, 31337);
  console.log("Proof processing completed:", finalResult);

  // Submit the proof to the ReputationOracle contract
  console.log(`Submitting proof to ReputationOracle contract...`);
  console.log("Proof to be submitted:", finalResult.proof);
  const tx = await reputationOracleContract.submitProof(
    requestId,
    finalResult.proof
  );

  await tx.wait();
  console.log(`Proof submitted. Transaction hash: ${tx.hash}`);

  // Fetch and display updated user info
  for (const user of users) {
    const [pROPoints, ROPoints, lastUpdateTimestamp, identityHash] =
      await reputationOracleContract.getUserInfo(user);
    console.log(`Updated info for user ${user}:`);
    console.log(`  pRO Points: ${pROPoints.toString()}`);
    console.log(`  RO Points: ${ROPoints.toString()}`);
    console.log(
      `  Last Update: ${new Date(
        lastUpdateTimestamp.toNumber() * 1000
      ).toISOString()}`
    );
    console.log(`  Identity Hash: ${identityHash}`);
  }

  return { finalResult, proof: proofRes.proof };
}

async function handleProofRequestInitiated(
  requestId: string,
  chainId: ethers.BigNumber,
  reputationLogicAddress: string,
  event: ethers.Event,
  reputationOracleContract: ethers.Contract,
  reputationLogicABI: any[],
  provider: ethers.providers.JsonRpcProvider,
  signer: ethers.Signer
) {
  console.log(`Received ProofRequestInitiated:`, {
    requestId,
    chainId: chainId.toString(),
    reputationLogicAddress,
  });

  try {
    const batchIdBN = await reputationOracleContract.requestToBatchId(
      requestId
    );
    const nonceBN = await reputationOracleContract.requestToNonce(requestId);

    const batchId = batchIdBN;
    const nonce = nonceBN;

    const reputationLogicContract = new ethers.Contract(
      reputationLogicAddress,
      reputationLogicABI,
      provider
    );

    const [users, swapInfosRaw, tickInfosRaw, tokenInfosRaw, metricsInfosRaw] =
      await reputationLogicContract.getBatchData(batchId);

    const { finalResult, proof } = await generateAndSubmitProof(
      requestId,
      batchId,
      nonce,
      users,
      swapInfosRaw,
      tickInfosRaw,
      tokenInfosRaw,
      metricsInfosRaw,
      reputationLogicAddress,
      event,
      reputationOracleContract
    );
  } catch (error) {
    console.error("Error in processing event:", error);
  }
}

async function getReputationOracleAddress(
  deployedContractsPath: string
): Promise<string | undefined> {
  if (fs.existsSync(deployedContractsPath)) {
    try {
      const deployedContracts = JSON.parse(
        fs.readFileSync(deployedContractsPath, "utf8")
      );
      const reputationOracleAddress = deployedContracts.reputationOracle;
      if (reputationOracleAddress) {
        return reputationOracleAddress;
      } else {
        console.warn(`ReputationOracle address not found in data.json.`);
      }
    } catch (error: any) {
      console.error(`Error reading data.json: ${error.message}.`);
    }
  } else {
    console.warn(`data.json not found at path: ${deployedContractsPath}`);
  }
  return undefined;
}

async function main() {
  const deployedContractsPath = path.resolve(
    __dirname,
    "../../post_deployments/data.json"
  );

  let reputationOracleAddress = await getReputationOracleAddress(
    deployedContractsPath
  );

  if (!reputationOracleAddress) {
    console.error("ReputationOracle address not found. Exiting.");
    process.exit(1);
  }

  console.log(`Found ReputationOracle address: ${reputationOracleAddress}`);

  const provider = new ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );

  try {
    const network = await provider.getNetwork();
    console.log("Connected to network:", network);
  } catch (error) {
    console.error("Error detecting network:", error);
    process.exit(1);
  }

  const signer = new ethers.Wallet(
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    provider
  );

  const reputationOracleABI = [
    "function getRegisteredPools() external view returns (address[])",
    "function submitProof(bytes32 _requestId, bytes calldata _proof) external",
    "function getUserInfo(address user) external view returns (uint256 pROPoints, uint256 ROPoints, uint256 lastUpdateTimestamp, bytes32 identityHash)",
    "function getPoolInfo(address reputationLogic) external view returns (uint256 collateral, uint256 lastActivityTimestamp, bool isRegistered, address reputationLogic)",
    "function requestToBatchId(bytes32 requestId) external view returns (uint256)",
    "function requestToNonce(bytes32 requestId) external view returns (uint256)",
    "event ProofRequestInitiated(bytes32 indexed requestId, uint64 chainId, address reputationLogic)",
  ];

  const reputationLogicABI = [
    "function getBatchData(uint256 batchId) external view returns (address[] users, (int256 amount0, int256 amount1, bool zeroForOne, int256 amountSpecified)[] swapInfos, (int24 currentTick, int24 lastTick)[] tickInfos, (address token0, address token1)[] tokenInfos, (uint256 liquidityUtilization, uint24 tickRange, uint256 activityScore)[] metricsInfos)",
    "event ReputationUpdateBatchEmitted(uint256 indexed batchId, uint256 indexed nonce, address[] users, uint256 updatesToProcess, bytes32[] swapInfoHashes, bytes32[] tickInfoHashes, bytes32[] tokenInfoHashes, bytes32[] metricsInfoHashes, address indexed hookAddress)",
  ];

  let reputationOracleContract: ethers.Contract;
  let currentReputationOracleAddress = reputationOracleAddress;

  const setupContract = async () => {
    reputationOracleContract = new ethers.Contract(
      currentReputationOracleAddress,
      reputationOracleABI,
      signer
    );

    console.log(
      `Fetching past ProofRequestInitiated events from ReputationOracle at ${currentReputationOracleAddress}...`
    );

    const filter = reputationOracleContract.filters.ProofRequestInitiated();
    const events = await reputationOracleContract.queryFilter(filter);

    console.log(`Found ${events.length} past ProofRequestInitiated events.`);

    for (const event of events) {
      await handleProofRequestInitiated(
        event.args!.requestId,
        event.args!.chainId,
        event.args!.reputationLogic,
        event,
        reputationOracleContract,
        reputationLogicABI,
        provider,
        signer
      );
    }

    console.log(
      `Setting up listener for future ProofRequestInitiated events...`
    );

    reputationOracleContract.removeAllListeners("ProofRequestInitiated");

    reputationOracleContract.on(
      "ProofRequestInitiated",
      async (
        requestId: string,
        chainId: ethers.BigNumber,
        reputationLogicAddress: string,
        event: ethers.Event
      ) => {
        await handleProofRequestInitiated(
          requestId,
          chainId,
          reputationLogicAddress,
          event,
          reputationOracleContract,
          reputationLogicABI,
          provider,
          signer
        );
      }
    );
  };

  await setupContract();

  setInterval(async () => {
    const newReputationOracleAddress = await getReputationOracleAddress(
      deployedContractsPath
    );

    if (!newReputationOracleAddress) {
      console.warn("ReputationOracle address not found in data.json.");
      return;
    }

    if (newReputationOracleAddress !== currentReputationOracleAddress) {
      console.log(
        `ReputationOracle address has changed to ${newReputationOracleAddress}. Updating...`
      );

      currentReputationOracleAddress = newReputationOracleAddress;
      await setupContract();
    }
  }, 10000);

  await new Promise(() => {});
}

main().catch(console.error);
