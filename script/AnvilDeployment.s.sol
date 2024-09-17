// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {stdJson} from "forge-std/StdJson.sol";

import {Script, console} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/test/PoolClaimsTest.sol";
import {SwapFeeLibrary} from "../src/libs/SwapFeeLibrary.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {ReputationHook} from "../src/ReputationHook.sol";
import {IReputationLogic} from "../src/interfaces/IReputationLogic.sol";
import {ReputationOracle} from "../src/ReputationOracle.sol";
import {MockBrevisProof} from "../src/mocks/MockBrevisProof.sol";
import {MockKeeperRegistry2_1} from "../src/mocks/MockKeeperRegistry2_1.sol"; // Chainlink Keeper Registry Mock
import {MockUpkeep} from "../src/mocks/MockUpkeep.sol"; // MockUpkeep for simulating upkeep
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {ReputationLogic} from "../src/ReputationLogic.sol";

contract ReputationHookDeployer is Script {
    using CurrencyLibrary for Currency;
    using SwapFeeLibrary for uint24;
    using PoolIdLibrary for PoolId;
    using PoolIdLibrary for PoolKey;

    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 public constant SQRT_PRICE_1_2 = 56022770974786139918731938227;
    uint160 public constant SQRT_PRICE_1_4 = 39614081257132168796771975168;
    uint160 public constant SQRT_PRICE_2_1 = 112045541949572279837463876454;
    uint160 public constant SQRT_PRICE_4_1 = 158456325028528675187087900672;
    uint160 public constant SQRT_PRICE_121_100 = 87150978765690771352898345369;

    address constant CREATE2_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;

    address lp1;
    address lp2;

    uint256 private constant LP1_PRIVATE_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 private constant LP2_PRIVATE_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    uint256 constant MAX_UINT256 = type(uint256).max;
    uint128 constant MAX_UINT128 = type(uint128).max;
    uint160 constant MAX_UINT160 = type(uint160).max;

    address constant ADDRESS_ZERO = address(0);

    /// 0011 1111 1111 1111
    address payable constant ALL_HOOKS =
        payable(0x0000000000000000000000000000000000003fFF);

    uint256 constant TICKS_OFFSET = 4;

    uint24 constant FEE_LOW = 500;
    uint24 constant FEE_MEDIUM = 3000;
    uint24 constant FEE_HIGH = 10000;

    bytes constant ZERO_BYTES = new bytes(0);

    PoolId poolId;
    PoolKey key;
    PoolManager manager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolDonateTest donateRouter;
    PoolTakeTest takeRouter;
    PoolClaimsTest claimsRouter;

    // logics
    ReputationOracle reputationOracle;
    ReputationHook hook;
    IReputationLogic reputationLogic;

    ReputationLogic reputationLogicImp;

    // mocks
    MockKeeperRegistry2_1 keeperRegistryMock; // Chainlink Keeper Registry mock
    MockUpkeep mockUpkeep; // Mock Upkeep contract
    MockBrevisProof mockBrevisProof;

    function run() public {
        vm.startBroadcast(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        lp1 = vm.addr(LP1_PRIVATE_KEY);
        lp2 = vm.addr(LP2_PRIVATE_KEY);

        // Deploy core contracts
        manager = new PoolManager(500000);
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        claimsRouter = new PoolClaimsTest(manager);

        // Deploy mock contracts
        mockBrevisProof = new MockBrevisProof();

        // Deploy ReputationOracle
        reputationOracle = new ReputationOracle(address(mockBrevisProof));

        // see file ./brevis/src/vkHash.js
        bytes32 vkHash = 0xe313ceeabee26a597fa5a8cc1989df938ca202b392a5741222d1ddd1d90b985f;
        reputationOracle.setVkHash(vkHash);

        // Deploy Chainlink's KeeperRegistry & Upkeep mocks
        keeperRegistryMock = new MockKeeperRegistry2_1(); // Keeper Registry mock deployed
        console.log(
            "KeeperRegistry Mock deployed at:",
            address(keeperRegistryMock)
        );

        mockUpkeep = new MockUpkeep(); // Mock Upkeep deployed
        console.log("MockUpkeep deployed at:", address(mockUpkeep));

        reputationLogicImp = new ReputationLogic();
        console.log(
            "ReputationLogicImp deployed at: ",
            address(reputationLogicImp)
        );

        // Deploy ReputationHook using HookMiner
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        address hookAdmin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // anvil 1st test user
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(ReputationHook).creationCode,
            abi.encode(
                IPoolManager(address(manager)),
                hookAdmin,
                address(reputationLogicImp)
            )
        );

        // Deploy the hook using CREATE2
        bytes memory creationCode = abi.encodePacked(
            type(ReputationHook).creationCode,
            abi.encode(
                IPoolManager(address(manager)),
                hookAdmin,
                address(reputationLogicImp)
            )
        );
        address payable deployedHookAddress;
        assembly {
            deployedHookAddress := create2(
                0,
                add(creationCode, 0x20),
                mload(creationCode),
                salt
            )
        }
        require(deployedHookAddress == hookAddress, "Hook address mismatch");

        hook = ReputationHook(deployedHookAddress);

        // Deploy mock tokens
        MockERC20 token = new MockERC20("Token A", "TKNA", 18);
        MockERC20 token2 = new MockERC20("Token B", "TKNB", 18);

        // Mint tokens to deployer
        token.mint(msg.sender, 1000 ether);
        token2.mint(msg.sender, 1000 ether);

        // Approvals for the contract and participants
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);

        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);

        // Initialize pool
        (Currency tokenCurrency, Currency token2Currency) = token < token2
            ? (Currency.wrap(address(token)), Currency.wrap(address(token2)))
            : (Currency.wrap(address(token2)), Currency.wrap(address(token)));

        console.log("Deploying pool with token A:", address(token));
        (key, poolId) = initPool(
            tokenCurrency,
            token2Currency,
            hook,
            SwapFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1,
            abi.encode(
                address(this),
                address(reputationOracle),
                5 minutes, // automation interval
                3000, // default base fee
                true // isDynamicFee
            )
        );

        // Get ReputationLogic (create opcode, attached to the hooks)
        (address poolAdmin, , , , , address reputationLogicAddress) = hook
            .getPoolConfig(key);
        reputationLogic = IReputationLogic(reputationLogicAddress);
        console.log("ReputationLogic deployed at:", address(reputationLogic));
        console.log("Pool admin", poolAdmin);
        console.log("Sender", msg.sender);

        hook.registerToOracle{value: 0.5 ether}(key);

        console.log("ReputationHook deployed at:", address(hook));
        console.log("PoolManager deployed at:", address(manager));
        console.log("SwapRouter deployed at:", address(swapRouter));
        console.log(
            "ModifyLiquidityRouter deployed at:",
            address(modifyLiquidityRouter)
        );

        console.log("ReputationOracle deployed at:", address(reputationOracle));
        console.log("Token A deployed at:", address(token));
        console.log("Token B deployed at:", address(token2));

        string memory path = "./post_deployments/data.json";


        // empty current data 
        string memory empty = "{}";
        vm.writeJson(empty, path);

        string memory json = string(
            abi.encodePacked(
                "{",
                '"reputationOracle": "',
                vm.toString(address(reputationOracle)),
                '"',
                "}"
            )
        );

        vm.writeJson(json, path);
 
        console.log("Deployment data written to", path);

        console.log("wait a bit while Brevis sdk captures the written reputation oracle");
        vm.warp(block.timestamp + 20);

        addLiquidityAndSwap();

        test_processReputationUpdates();

        vm.stopBroadcast();
    }

    function addLiquidityAndSwap() internal {
        address user = lp1;
        int24 tickLower = -60;
        int24 tickUpper = 60;

        bytes memory hookData = abi.encode(user, tickLower, tickUpper);

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        (uint256 amount0Delta, ) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickLower,
            sqrtPriceAtTickUpper,
            1 ether
        );

        // modifyLiquidity
        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta + 1}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );

        // swap
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        console.log("Swap completed");
    }

    function test_processReputationUpdates() internal {
        console.log("simulating chainlink automation performing upkeep");
        uint256 queueLengthBefore;
        try reputationLogic.getUpdateQueueLength() returns (uint256 length) {
            queueLengthBefore = length;
        } catch {
            console.log(
                "ReputationLogic does not have getUpdateQueueLength function"
            );
            return;
        }
        keeperRegistryMock.addFunds(1, 1000); // Simulate Keeper Registry adding funds
        mockUpkeep.setCheckResult(true); // Mock the upkeep check result
        reputationLogic.performUpkeep(""); // Simulate Chainlink Automation performing upkeep
        uint256 queueLengthAfter = reputationLogic.getUpdateQueueLength();

        // Check that the queue length decreased after processing
        assert(queueLengthAfter < queueLengthBefore);
    }

    function initPool(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData
    ) internal returns (PoolKey memory _key, PoolId id) {
        _key = PoolKey(
            _currency0,
            _currency1,
            fee,
            fee.isDynamicFee() ? int24(60) : int24((fee / 100) * 2),
            hooks
        );
        id = _key.toId();
        manager.initialize(_key, sqrtPriceX96, initData);
    }
}
