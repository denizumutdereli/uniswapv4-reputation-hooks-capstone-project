// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// solhint-disable

import "../lib/chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {ReputationTypes} from "./libs/ReputationTypes.sol";
import {IReputationLogic} from "./interfaces/IReputationLogic.sol";
import {IReputationOracle} from "./interfaces/IReputationOracle.sol";
import {CustomReentrancyGuard} from "./libs/CustomReentrancyGuard.sol";
import {CustomAccessControl,AccessControl} from "./libs/CustomAccessControl.sol";
import {ERC165,IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "forge-std/console.sol";

contract ReputationLogic is
    ERC165,
    CustomAccessControl,
    AutomationCompatibleInterface,
    CustomReentrancyGuard,
    IERC1155Receiver,
    IReputationLogic
{
    IReputationOracle public reputationOracle;

    bytes32 public constant HOOK_ROLE = keccak256("HOOK_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint256 private batchSize;
    uint256 private cooldownPeriod;
    uint256 private lastAutomatedUpdate;
    uint256 private automationInterval;
    uint256 private nonce; // Nonce for unique batch IDs

    address private admin;

    uint256 private queueStart;
    uint256 private queueEnd;

    mapping(address => uint256) public userPoints;
    mapping(address => UserAction[]) public userActions;
    mapping(address => uint256) public lastReputationUpdateTimeSwap;
    mapping(address => uint256) public lastReputationUpdateTimeLiquidity;

    ReputationTypes.ReputationUpdate[] public updateQueue;

    mapping(uint256 => BatchData) private batches; // Store batch data
    mapping(address => uint256) private roBalances;

    address public reputationHook;
    bool public oracleRegistered;

    bool private initialized; // Flag to prevent re-initialization

    modifier onlyAdminOrHook() {
        if (_msgSender() != admin && _msgSender() != reputationHook) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyOnce() {
        require(!initialized, "Already initialized");
        _;
    }

    function initialize(
        address _admin,
        address _reputationOracle,
        uint24 _automationInterval
    ) external onlyOnce {
        initialized = true;

        // Initialize CustomReentrancyGuard
        _initializeReentrancyGuard();

        // Initialize CustomAccessControl
        _initializeAccessControl((_admin == address(0)) ? _msgSender() : _admin);

        // Grant roles
        _grantRole(HOOK_ROLE, _msgSender());
        _grantRole(ORACLE_ROLE, _reputationOracle);

        reputationHook = _msgSender();
        reputationOracle = IReputationOracle(_reputationOracle);

        batchSize = 20;
        cooldownPeriod = 10 minutes;
        nonce = 0;

        automationInterval = _automationInterval;
        lastAutomatedUpdate = block.timestamp;

        admin = _admin;
        queueStart = 0;
        queueEnd = 0;

        IERC1155(address(reputationOracle)).setApprovalForAll(
            address(this),
            true
        );
        IERC1155(address(reputationOracle)).setApprovalForAll(_admin, true);
        IERC1155(address(reputationOracle)).setApprovalForAll(
            address(reputationOracle),
            true
        );

        emit ReputationLogicConfigSettled(
            admin,
            _reputationOracle,
            _automationInterval
        );
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(IERC165, ERC165, AccessControl) returns (bool) {
        return
            interfaceId == type(IReputationLogic).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /* administration ------------------------------------------------------------------------ */

    function registerToOracle()
        public
        payable
        override
        nonReentrant
        onlyAdminOrHook
    {
        require(!oracleRegistered, "Oracle already registered");

        uint256 collateral = reputationOracle.getRequiredCollateral();

        if (msg.value < collateral) {
            // allowing more than required
            revert InsufficientFeeCollateral();
        }

        reputationOracle.registerPool{value: collateral}(
            reputationHook,
            address(this)
        );
        oracleRegistered = true;
    }

    function unregisterFromOracle() public nonReentrant onlyAdminOrHook {
        require(oracleRegistered, "Oracle not registered");

        reputationOracle.unregisterPool(address(this));
        oracleRegistered = false;
    }

    function setReputationOracle(
        address _reputationOracle
    ) external override nonReentrant onlyAdminOrHook {
        unregisterFromOracle();
        reputationOracle = IReputationOracle(_reputationOracle);
        registerToOracle();
    }

    function withdrawFeesTo(
        address payable recipient
    ) external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        recipient.transfer(address(this).balance);
    }

    function grantRole(
        bytes32 role,
        address account
    ) public override(AccessControl) onlyRole(DEFAULT_ADMIN_ROLE) {
        if (role == DEFAULT_ADMIN_ROLE) {
            admin = account;
        }
        super.grantRole(role, account);
    }

    /* mechanics ---------------------------------------------------------------------------- */

    function queueReputationUpdate(
        ReputationTypes.ReputationUpdate calldata update
    ) external override onlyRole(HOOK_ROLE) returns (bool) {
        require(oracleRegistered, "Oracle not registered");
        uint256 currentTime = block.timestamp;
        address user = update.user;

        uint256 lastUpdateTime = update.swapInfo.zeroForOne
            ? lastReputationUpdateTimeSwap[user]
            : lastReputationUpdateTimeLiquidity[user];

        if (currentTime >= lastUpdateTime + cooldownPeriod) {
            updateQueue.push(update);
            queueEnd++;

            // Hash each struct
            bytes32 swapInfoHash = ReputationTypes._hashSwapInfo(
                update.swapInfo
            );
            bytes32 tickInfoHash = ReputationTypes._hashTickInfo(
                update.tickInfo
            );
            bytes32 tokenInfoHash = ReputationTypes._hashTokenInfo(
                update.tokenInfo
            );
            bytes32 metricsInfoHash = ReputationTypes._hashMetricsInfo(
                update.metricsInfo
            );

            // Emit the event with the hashed data
            emit ReputationUpdateQueued(
                user,
                updateQueue.length,
                swapInfoHash,
                tickInfoHash,
                tokenInfoHash,
                metricsInfoHash
            );

            // Record the user action
            userActions[user].push(
                UserAction({
                    amount: update.swapInfo.amount0 + update.swapInfo.amount1,
                    zeroForOne: update.swapInfo.zeroForOne,
                    specifiedAmount: update.swapInfo.amountSpecified,
                    timestamp: currentTime
                })
            );

            emit UserActionRecorded(
                user,
                update.swapInfo.amount0 + update.swapInfo.amount1,
                update.swapInfo.zeroForOne,
                update.swapInfo.amountSpecified,
                currentTime
            );

            if (update.swapInfo.zeroForOne) {
                lastReputationUpdateTimeSwap[user] = currentTime;
            } else {
                lastReputationUpdateTimeLiquidity[user] = currentTime;
            }

            return true;
        } else {
            return false;
        }
    }

    function getUpdateQueue()
        external
        view
        override
        returns (ReputationTypes.ReputationUpdate[] memory)
    {
        return updateQueue;
    }

    function getUpdateQueueLength() external view override returns (uint256) {
        return queueEnd - queueStart;
    }

    function clearProcessedBatch(
        uint256 batchId
    ) external override onlyRole(ORACLE_ROLE) {
        delete batches[batchId];
    }

    /* automation ------------------------------------------------------------------------ */

    function setCooldownPeriod(
        uint256 _cooldown
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_cooldown < 1 minutes || _cooldown > 1 days)
            revert InvalidCooldDownPeriod();
        cooldownPeriod = _cooldown;
        emit UpdateCoolDownPeriod(_cooldown);
    }

    function setBatchSize(
        uint256 _batchSize
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_batchSize == 0 || _batchSize > 50) {
            revert InvalidBatchSize();
        }
        batchSize = _batchSize;
        emit UpdateBatchSize(_batchSize);
    }

    function setAutomationInterval(
        uint256 _newInterval
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newInterval == 0 || _newInterval > 1 days) {
            revert InvalidAutomationInterval();
        }
        automationInterval = _newInterval;
        emit UpdateAutomationInterval(_newInterval);
    }

    /** automation ---------------------------------------------------------- */

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        require(oracleRegistered, "Oracle not registered");
        upkeepNeeded =
            (block.timestamp - lastAutomatedUpdate >= automationInterval) &&
            (queueEnd > queueStart);
        return (upkeepNeeded, "");
    }

    function performUpkeep(
        bytes calldata /* performData */
    )
        external
        override(AutomationCompatibleInterface, IReputationLogic)
        nonReentrant
    {
        require(oracleRegistered, "Oracle not registered");
        uint256 queueLength = queueEnd - queueStart;
        uint256 updatesToProcess = queueLength > batchSize
            ? batchSize
            : queueLength;

        if (updatesToProcess == 0) {
            //revert NoQueue(); No revert for unblocking but we can emit
            emit NoQueueEvent();
        }

        // Copy batch for processing
        ReputationTypes.ReputationUpdate[]
            memory batch = new ReputationTypes.ReputationUpdate[](
                updatesToProcess
            );

        for (uint256 i = 0; i < updatesToProcess; i++) {
            batch[i] = updateQueue[queueStart + i];
        }

        // Process the batch
        address[] memory users = new address[](updatesToProcess);
        bytes32[] memory swapInfoHashes = new bytes32[](updatesToProcess);
        bytes32[] memory tickInfoHashes = new bytes32[](updatesToProcess);
        bytes32[] memory tokenInfoHashes = new bytes32[](updatesToProcess);
        bytes32[] memory metricsInfoHashes = new bytes32[](updatesToProcess);

        // Arrays to hold the actual data
        ReputationTypes.SwapInfo[]
            memory swapInfos = new ReputationTypes.SwapInfo[](updatesToProcess);
        ReputationTypes.TickInfo[]
            memory tickInfos = new ReputationTypes.TickInfo[](updatesToProcess);
        ReputationTypes.TokenInfo[]
            memory tokenInfos = new ReputationTypes.TokenInfo[](
                updatesToProcess
            );
        ReputationTypes.MetricsInfo[]
            memory metricsInfos = new ReputationTypes.MetricsInfo[](
                updatesToProcess
            );

        uint256 batchId = uint256(
            keccak256(abi.encodePacked(address(this), nonce))
        );
        uint256 nonceValue = lastAutomatedUpdate + block.number; // Nonce for front-running protection
        nonce++;

        for (uint256 i = 0; i < updatesToProcess; i++) {
            ReputationTypes.ReputationUpdate memory update = batch[i];

            users[i] = update.user;
            swapInfoHashes[i] = ReputationTypes._hashSwapInfo(update.swapInfo);
            tickInfoHashes[i] = ReputationTypes._hashTickInfo(update.tickInfo);
            tokenInfoHashes[i] = ReputationTypes._hashTokenInfo(
                update.tokenInfo
            );
            metricsInfoHashes[i] = ReputationTypes._hashMetricsInfo(
                update.metricsInfo
            );

            // Store the actual data
            swapInfos[i] = update.swapInfo;
            tickInfos[i] = update.tickInfo;
            tokenInfos[i] = update.tokenInfo;
            metricsInfos[i] = update.metricsInfo;
        }

        // Store batch data
        batches[batchId] = BatchData({
            users: users,
            swapInfos: swapInfos,
            tickInfos: tickInfos,
            tokenInfos: tokenInfos,
            metricsInfos: metricsInfos
        });

        // Emit a single event for the batch (keep emitting hashes)
        emit ReputationUpdateBatchEmitted(
            batchId,
            nonceValue,
            users,
            updatesToProcess,
            swapInfoHashes,
            tickInfoHashes,
            tokenInfoHashes,
            metricsInfoHashes,
            reputationHook
        );

        // Initiate proof request in the ReputationOracle
        initiateProofRequest(batchId, nonceValue);

        // Move the queueStart pointer forward to remove the processed updates
        queueStart += updatesToProcess;

        // Optionally reset the queue to save gas if queueStart is large
        if (queueStart >= 2 * batchSize) {
            delete updateQueue;
            queueStart = 0;
            queueEnd = 0;
        }

        lastAutomatedUpdate = block.timestamp;
    }

    function initiateProofRequest(
        uint256 batchId,
        uint256 nonceValue
    ) internal {
        uint256 fee = reputationOracle.getRequiredFee();
        uint64 chainId = uint64(block.chainid);

        if (address(this).balance < fee) {
            revert InsufficientBalanceForOperation();
        }

        // Call initiateReputationUpdateBatch on the ReputationOracle without ExtractInfos
        try reputationOracle.initiateReputationUpdateBatch{value: fee}(
            batchId,
            nonceValue,
            chainId
        ) {} catch {
            revert FailedInitiateProofRequest();
        }
    }

    function getBatchData(
        uint256 batchId
    )
        external
        view
        override
        returns (
            address[] memory users,
            ReputationTypes.SwapInfo[] memory swapInfos,
            ReputationTypes.TickInfo[] memory tickInfos,
            ReputationTypes.TokenInfo[] memory tokenInfos,
            ReputationTypes.MetricsInfo[] memory metricsInfos
        )
    {
        BatchData storage batch = batches[batchId];
        return (
            batch.users,
            batch.swapInfos,
            batch.tickInfos,
            batch.tokenInfos,
            batch.metricsInfos
        );
    }

    /* Testing purpose functions -------------------------------------------------------- */

    function getAdmin() external view override returns (address) {
        return admin;
    }

    function getReputationOracle() external view override returns (address) {
        return address(reputationOracle);
    }

    function getBatchSize() external view override returns (uint256) {
        return batchSize;
    }

    function getAutomationInterval() external view override returns (uint256) {
        return automationInterval;
    }

    function getCoolDownPeriod() external view override returns (uint256) {
        return cooldownPeriod;
    }

    function getHookHasPermitted(
        address _hookAddress
    ) external view override returns (bool) {
        return hasRole(HOOK_ROLE, _hookAddress);
    }

    /* ERC1155Receiver ------------------------------------------------------------------------ */

    function onERC1155Received(
        address /*operator*/,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        require(
            msg.sender == address(reputationOracle),
            "Tokens must come from the ReputationOracle"
        );

        // Only handle RO tokens (ID = 1 for RO tokens)
        if (id == 1) {
            roBalances[from] += value; // Track the RO tokens deposited
            console.log("Received RO tokens:", value);
        }

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        require(
            msg.sender == address(reputationOracle),
            "Tokens must come from the ReputationOracle"
        );

        // Iterate over the token IDs and handle RO tokens
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == 1) {
                // Handle only RO tokens (ID = 1)
                roBalances[from] += values[i];
                console.log("Received RO token batch, amount:", values[i]);
            }
        }

        return this.onERC1155BatchReceived.selector;
    }

    /* ERC1155 ------------------------------------------------------------------------ */

    function depositRoTokens(
        uint256 amount
    ) external onlyAdminOrHook nonReentrant {
        // Check if approval is already granted
        require(
            IERC1155(address(reputationOracle)).isApprovedForAll(
                msg.sender,
                address(this)
            ),
            "Contract not approved to transfer tokens"
        );

        // Admin can deposit RO tokens into the contract
        IERC1155(address(reputationOracle)).safeTransferFrom(
            msg.sender,
            address(this),
            1, // Token ID for RO tokens
            amount,
            ""
        );

        roBalances[msg.sender] += amount;
        emit RoTokensDeposited(msg.sender, amount);
        console.log("Admin deposited RO tokens, Amount:", amount);
    }

    function withdrawRoTokens(uint256 amount) external nonReentrant {
        require(roBalances[msg.sender] >= amount, "Insufficient RO balance");

        // Decrease the balance
        roBalances[msg.sender] -= amount;

        // Transfer the tokens back to the user
        IERC1155(address(reputationOracle)).safeTransferFrom(
            address(this),
            msg.sender,
            1, // Token ID for RO tokens
            amount,
            ""
        );

        emit RoTokensWithdrawn(msg.sender, amount);
        console.log("Withdrawn RO tokens, Amount:", amount);
    }

    function balanceOf(address user) external view returns (uint256) {
        return roBalances[user];
    }

    /* admin ------------------------------------------------------------------------ */

    receive() external payable {}

    fallback() external {
        revert Unauthorized();
    }
}
