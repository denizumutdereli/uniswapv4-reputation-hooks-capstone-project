// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// solhint-disable
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/SafeMath.sol";
import "./BrevisApp.sol";
import "./interfaces/IReputationOracle.sol";
import "./interfaces/IReputationLogic.sol";
import {IBrevisProof as Brevis} from "./interfaces/IBrevisProof.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "forge-std/console.sol";

contract ReputationOracle is ERC1155, BrevisApp, Ownable, IReputationOracle {
    using SafeMath for uint256;

    uint256 public constant PRO_TOKEN_ID = 0;
    uint256 public constant RO_TOKEN_ID = 1;

    uint256 public feesCollected;
    uint256 public requiredFee = 0.01 ether;
    uint256 public inactivityLimit = 1 days; // Maximum inactivity period for pools
    uint256 public collateralRequirement = 0.1 ether; // Initial collateral requirement for pools
    uint256 public slashPercentage = 10; // 10% slashing for inactivity
    uint256 public decayPeriod = 30 days;
    uint256 public decayPercentage = 5; // 5% decay
    uint256 public adjustmentFrequency = 7 days; // Frequency of collateral adjustments
    uint256 public lastAdjustmentTime; // Last time the collateral was adjusted
    uint256 public totalCollateral; // Total collateral staked by all pools
    uint256 public totalROTokens; // Total `RO` tokens minted
    uint256 public maxROTokenCap = 1000000 * (10 ** 18); // Max cap for `RO` tokens

    bytes32 public vkHash;

    mapping(address => UserInfo) public userInfo;
    mapping(bytes32 => uint256) public override requestToBatchId;
    mapping(bytes32 => uint256) public override requestToNonce;
    mapping(bytes32 => address) public override requestToPool; // Mapping to store pool address for each request
    mapping(address => PoolInfo) public poolInfo; // Pool information
    address[] public registeredPoolAddresses;

    modifier onlyRegisteredPool() {
        require(
            poolInfo[msg.sender].isRegistered,
            "Sender is not a registered pool"
        );
        _;
    }

    constructor(
        address _brevisProof
    ) ERC1155("") BrevisApp(_brevisProof) Ownable(msg.sender) {}

    receive() external payable {}

    fallback() external payable {
        revert("NotPermitted");
    }

    function setVkHash(bytes32 _vkHash) external override onlyOwner {
        vkHash = _vkHash;
    }

    /** fee structure -------------------------------------------------------------- */
    /** for testing purpose...  */
    function withdrawFeesTo(
        address payable recipient
    ) external override onlyOwner {
        uint256 amount = feesCollected;
        feesCollected = 0;
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
        emit FeesWithdrawn(recipient, amount);
    }

    // Registration function for pools
    function registerPool(
        address /*reputationHook*/,
        address reputationLogic
    ) external payable override {
        // Ensure the sender is the reputationLogic or the reputationHook itself.
        require(reputationLogic == msg.sender, "Invalid logic or pool address");

        require(msg.value >= collateralRequirement, "Insufficient collateral");
        require(
            !poolInfo[reputationLogic].isRegistered,
            "Pool already registered"
        );

        // Record the pool information
        poolInfo[reputationLogic] = PoolInfo({
            collateral: msg.value,
            lastActivityTimestamp: block.timestamp,
            isRegistered: true,
            reputationLogic: reputationLogic
        });

        registeredPoolAddresses.push(reputationLogic);

        // Update total collateral and mint RO tokens proportionally
        totalCollateral = totalCollateral.add(msg.value);

        uint256 tokensToMint = msg.value; // Mint 1:1 initially
        require(
            totalROTokens.add(tokensToMint) <= maxROTokenCap,
            "RO token cap exceeded"
        );
        totalROTokens = totalROTokens.add(tokensToMint);

        // Mint RO tokens to the `reputationLogic` contract address
        _mint(reputationLogic, RO_TOKEN_ID, tokensToMint, "");

        emit PoolRegistered(reputationLogic, msg.value, tokensToMint);
    }

    function unregisterPool(address reputationLogic) external override {
        require(
            msg.sender == reputationLogic ||
                poolInfo[msg.sender].reputationLogic == reputationLogic,
            "Unauthorized"
        );
        require(poolInfo[msg.sender].isRegistered, "Pool not registered");

        PoolInfo storage info = poolInfo[msg.sender];

        // Return collateral to the pool
        uint256 collateralToReturn = info.collateral;

        // Burn the pool's RO tokens
        uint256 tokensToBurn = balanceOf(msg.sender, RO_TOKEN_ID);
        _burn(msg.sender, RO_TOKEN_ID, tokensToBurn);
        totalROTokens = totalROTokens.sub(tokensToBurn);

        // Update total collateral
        totalCollateral = totalCollateral.sub(collateralToReturn);

        info.collateral = 0;
        info.isRegistered = false;
        info.reputationLogic = address(0);

        // Remove from registeredPoolAddresses
        for (uint256 i = 0; i < registeredPoolAddresses.length; i++) {
            if (registeredPoolAddresses[i] == msg.sender) {
                registeredPoolAddresses[i] = registeredPoolAddresses[
                    registeredPoolAddresses.length - 1
                ];
                registeredPoolAddresses.pop();
                break;
            }
        }

        // Return the collateral
        (bool success, ) = msg.sender.call{value: collateralToReturn}("");
        require(success, "Collateral return failed");

        emit PoolUnregistered(msg.sender);
    }

    function depositFeeCollateral(
        address reputationLogic
    ) external payable override {
        require(
            poolInfo[msg.sender].reputationLogic == reputationLogic,
            "Invalid reputation logic"
        );

        require(msg.value > 0, "No collateral provided");
        PoolInfo storage info = poolInfo[msg.sender];

        // Update the collateral
        info.collateral = info.collateral.add(msg.value);
        totalCollateral = totalCollateral.add(msg.value);

        emit CollateralDeposited(msg.sender, msg.value);
    }

    /** mechanics -------------------------------------------------------------------- */
    function initiateReputationUpdateBatch(
        uint256 batchId,
        uint256 nonce,
        uint64 chainId
    ) external payable override onlyRegisteredPool returns (bytes32) {
        require(msg.value == requiredFee, "Insufficient fee"); // exact same fee

        // Collect fees
        feesCollected += msg.value;

        // Create an empty ExtractInfos struct
        Brevis.ExtractInfos memory extractInfos; // Empty as per the agreed flow

        // Initiate proof request
        bytes32 requestId = initiateProofRequest(chainId, extractInfos);

        // Store mappings
        requestToBatchId[requestId] = batchId;
        requestToNonce[requestId] = nonce;
        requestToPool[requestId] = msg.sender;

        // Update last activity timestamp for the pool
        poolInfo[msg.sender].lastActivityTimestamp = block.timestamp;

        // Retrieve the reputationLogic address
        address reputationLogic = poolInfo[msg.sender].reputationLogic;

        // Emit event
        emit ProofRequestInitiated(requestId, chainId, reputationLogic);

        return requestId;
    }

    function initiateProofRequest(
        uint64 _chainId,
        IBrevisProof.ExtractInfos memory _extractInfos
    ) internal override returns (bytes32) {
        bytes32 requestId = keccak256(
            abi.encode(_chainId, _extractInfos, block.timestamp)
        );
        pendingRequests[requestId] = true;
        //emit ProofRequestInitiated(requestId, _chainId);
        return requestId;
    }

    // Automated Slashing Mechanism
    function checkAndSlashInactivePools() external override {
        for (uint256 i = 0; i < registeredPoolAddresses.length; i++) {
            address _reputationLogic = registeredPoolAddresses[i];
            PoolInfo storage info = poolInfo[_reputationLogic];

            if (info.isRegistered && info.collateral > 0) {
                uint256 timeSinceLastActivity = block.timestamp.sub(
                    info.lastActivityTimestamp
                );

                if (timeSinceLastActivity > inactivityLimit) {
                    uint256 slashedAmount = info
                        .collateral
                        .mul(slashPercentage)
                        .div(100);
                    info.collateral = info.collateral.sub(slashedAmount);
                    feesCollected = feesCollected.add(slashedAmount);

                    totalCollateral = totalCollateral.sub(slashedAmount);

                    // Burn corresponding RO tokens
                    uint256 tokensToBurn = (slashedAmount.mul(totalROTokens))
                        .div(totalCollateral.add(slashedAmount));
                    _burn(_reputationLogic, RO_TOKEN_ID, tokensToBurn);
                    totalROTokens = totalROTokens.sub(tokensToBurn);

                    emit CollateralSlashed(_reputationLogic, slashedAmount);
                }
            }
        }
    }

    function getVkHash() public view returns (bytes32) {
        return vkHash;
    }

    // Minting pRO and RO tokens based on user activity
    function handleProofResult(
        bytes32 _requestId,
        bytes32 /*_vkHash*/,
        bytes calldata _proof
    ) internal override {

        (bytes32 proofVkHash, bytes32 proofOutputCommitment, bytes memory proofAppCircuitOutput) = 
            abi.decode(_proof, (bytes32, bytes32, bytes));
    
        console.log("Decoded proofVkHash,proofOutputCommitment,proofAppCircuitOutput");
        console.logBytes32(proofVkHash);
        console.logBytes32(proofOutputCommitment);
        console.logBytes(proofAppCircuitOutput);
    
        console.log("Contract vkHash:");
        console.logBytes32(vkHash);
        require(vkHash == proofVkHash, "Invalid verification key hash");
    
        bytes32 calculatedCommitment = keccak256(proofAppCircuitOutput);
        console.log("Calculated output commitment:");
        console.logBytes32(calculatedCommitment);
        require(calculatedCommitment == proofOutputCommitment, "Invalid output commitment");

        console.log("checking if vkhash is correct");
        require(vkHash == proofVkHash, "Invalid verification key hash");
        console.log("comparing proofAppCircuitOutput proofOutputCommitment");
        require(
            keccak256(proofAppCircuitOutput) == proofOutputCommitment,
            "Invalid output commitment"
        );

        console.log("decoding proofAppCircuitOutput");
        (
            address[] memory users,
            int256[] memory scores,
            bytes32[] memory identityHashes,
            uint256 processedBatchId,
            uint256 processedNonce,
            uint256 updatesProcessed
        ) = abi.decode(
                proofAppCircuitOutput,
                (address[], int256[], bytes32[], uint256, uint256, uint256)
            );

        uint256 batchId = requestToBatchId[_requestId];
        uint256 nonce = requestToNonce[_requestId];
        address _reputationLogic = requestToPool[_requestId];

        require(processedBatchId == batchId, "Batch ID mismatch");
        require(processedNonce == nonce, "Nonce mismatch");
        require(
            users.length == updatesProcessed &&
                scores.length == updatesProcessed &&
                identityHashes.length == updatesProcessed,
            "Length mismatch"
        );

        // Process updates
        for (uint256 i = 0; i < updatesProcessed; i++) {
            address user = users[i];
            int256 score = scores[i];
            bytes32 identityHash = identityHashes[i];

            UserInfo storage info = userInfo[user];

            applyDecay(info);

            if (score > 0) {
                info.pROPoints = info.pROPoints.add(uint256(score));

                // Calculate RO tokens to mint based on the user's contribution to the total collateral pool
                uint256 tokensToMint = (totalCollateral.mul(uint256(score)))
                    .div(totalROTokens);
                require(
                    totalROTokens.add(tokensToMint) <= maxROTokenCap,
                    "RO token cap exceeded"
                );
                info.ROPoints = info.ROPoints.add(tokensToMint);
                totalROTokens = totalROTokens.add(tokensToMint);

                _mint(user, PRO_TOKEN_ID, uint256(score), "");
                _mint(user, RO_TOKEN_ID, tokensToMint, "");
            } else if (score < 0) {
                uint256 absScore = uint256(-score);
                info.pROPoints = info.pROPoints > absScore
                    ? info.pROPoints.sub(absScore)
                    : 0;
            }

            info.identityHash = identityHash;
            info.lastUpdateTimestamp = block.timestamp;

            emit UserPointsUpdated(
                user,
                info.pROPoints,
                info.ROPoints,
                info.identityHash
            );
        }

        emit ReputationUpdateBatchProcessed(
            _requestId,
            batchId,
            nonce,
            updatesProcessed
        );

        // Update last activity timestamp for the pool
        poolInfo[_reputationLogic].lastActivityTimestamp = block.timestamp;

        // Clean up mappings
        delete requestToBatchId[_requestId];
        delete requestToNonce[_requestId];
        delete requestToPool[_requestId];

        // Call clearProcessedBatch on the associated ReputationLogic contract
        address reputationLogic = poolInfo[_reputationLogic].reputationLogic;

        console.log("Clearing proccessed batch queue...");
        try IReputationLogic(reputationLogic).clearProcessedBatch(batchId) {
            // Successfully cleared the batch
        } catch {
            // Handle failure gracefully
            // Optionally emit an event
        }
    }

    function applyDecay(UserInfo storage info) internal {
        uint256 timePassed = block.timestamp.sub(info.lastUpdateTimestamp);
        uint256 decayIterations = timePassed.div(decayPeriod);

        if (decayIterations > 0) {
            for (uint256 i = 0; i < decayIterations; i++) {
                info.pROPoints = info.pROPoints.mul(100 - decayPercentage).div(
                    100
                );
            }
            info.lastUpdateTimestamp = block.timestamp;
        }
    }

    // Adjust the required collateral based on NAV and risk exposure
    function adjustRequiredCollateral() external override onlyOwner {
        require(
            block.timestamp >= lastAdjustmentTime + adjustmentFrequency,
            "Adjustment not due yet"
        );

        uint256 NAV = totalCollateral.add(feesCollected);
        uint256 activeHooksCount = getActiveHooksCount();
        uint256 basePercentage = 5; // Base collateral requirement is 5% of NAV
        uint256 riskAdjustmentFactor = activeHooksCount.mul(2); // Increase by 2% per active pool

        uint256 newCollateralRequirement = (
            NAV.mul(basePercentage + riskAdjustmentFactor)
        ).div(100);
        uint256 minCollateralRequirement = 1 ether; // Minimum to avoid too low collateral

        collateralRequirement = newCollateralRequirement >
            minCollateralRequirement
            ? newCollateralRequirement
            : minCollateralRequirement;
        lastAdjustmentTime = block.timestamp;

        emit CollateralAdjusted(collateralRequirement);
    }

    function getActiveHooksCount() internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < registeredPoolAddresses.length; i++) {
            if (poolInfo[registeredPoolAddresses[i]].isRegistered) {
                count++;
            }
        }
        return count;
    }

    function getRegisteredPools()
        external
        view
        override
        returns (address[] memory)
    {
        return registeredPoolAddresses;
    }

    function getUserInfo(
        address user
    )
        external
        view
        override
        returns (
            uint256 pROPoints,
            uint256 ROPoints,
            uint256 lastUpdateTimestamp,
            bytes32 identityHash
        )
    {
        UserInfo storage info = userInfo[user];
        return (
            info.pROPoints,
            info.ROPoints,
            info.lastUpdateTimestamp,
            info.identityHash
        );
    }

    function getUserPoints(
        address /*user*/
    ) external pure override returns (uint256) {
        return 10000;
        //return userInfo[user].pROPoints;
    }

    function getPoolInfo(
        address _reputationLogic
    )
        external
        view
        override
        returns (
            uint256 collateral,
            uint256 lastActivityTimestamp,
            bool isRegistered,
            address reputationLogic
        )
    {
        PoolInfo storage info = poolInfo[_reputationLogic];
        return (
            info.collateral,
            info.lastActivityTimestamp,
            info.isRegistered,
            info.reputationLogic
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        require(id != PRO_TOKEN_ID, "pRO tokens are not transferable");
        super.safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] != PRO_TOKEN_ID, "pRO tokens are not transferable");
        }
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function submitProof(
        bytes32 _requestId,
        bytes calldata _proof
    ) external override(BrevisApp, IReputationOracle) {
        require(pendingRequests[_requestId], "Request not pending");
        brevisProof.verifyProof(_requestId, _proof);
        _handleCallback(_requestId, _proof);
    }

    function getRequiredFee() external view override returns (uint256) {
        return requiredFee;
    }

    function getRequiredCollateral() external view override returns (uint256) {
        return collateralRequirement;
    }
}
