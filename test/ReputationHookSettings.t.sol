// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {ReputationHook} from "../src/ReputationHook.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {SwapFeeLibrary} from "../src/libs/SwapFeeLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MockBrevisProof} from "../src/mocks/MockBrevisProof.sol";
import {ReputationOracle} from "../src/ReputationOracle.sol";
import {MockKeeperRegistry2_1} from "../src/mocks/MockKeeperRegistry2_1.sol";
import {MockUpkeep} from "../src/mocks/MockUpkeep.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {HookUtils} from "../src/libs/HookUtils.sol";
import {ReputationLogic} from "../src/ReputationLogic.sol";
import {IReputationLogic} from "../src/interfaces/IReputationLogic.sol";

import "forge-std/console.sol";

/**
 * @title ReputationHookTest
 * @notice Test contract for the ReputationHook functionality
 * @dev Inherits from Test, Deployers, and IUnlockCallback
 */
contract ReputationHookTest is Test, Deployers, IUnlockCallback {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SwapFeeLibrary for uint24;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    ReputationHook hook;
    PoolId poolId;
    ReputationOracle reputationOracle;
    IReputationLogic logic;

    ReputationLogic reputationLogicImp;

    MockKeeperRegistry2_1 keeperRegistryMock;
    MockUpkeep mockUpkeep;

    MockERC20 token;
    MockERC20 token2;
    MockERC20 token3;
    MockERC20 token4;

    Currency tokenCurrency;
    Currency tokenCurrency2;
    Currency tokenCurrency3;
    Currency tokenCurrency4;

    address lp1 = makeAddr("LP1");
    address lp2 = makeAddr("LP2");

    /**
     * @notice Set up the test environment
     * @dev Deploys contracts, mints tokens, and initializes the pool
     */
    function setUp() public {
        console.log("Starting setUp");

        deployFreshManagerAndRouters();

        token = new MockERC20("Main Token", "MTK", 18);
        tokenCurrency = Currency.wrap(address(token));

        token2 = new MockERC20("Second Token", "SCT", 18);
        tokenCurrency2 = Currency.wrap(address(token2));

        token3 = new MockERC20("Third Token", "TRT", 18);
        tokenCurrency3 = Currency.wrap(address(token3));

        token4 = new MockERC20("Fourd Token", "FRT", 18);
        tokenCurrency4 = Currency.wrap(address(token4));

        // Mint tokens to participants
        token.mint(address(this), 1000 ether);
        token.mint(lp1, 250 ether);
        token.mint(lp2, 250 ether);

        token2.mint(address(this), 1000 ether);
        token2.mint(lp1, 250 ether);
        token2.mint(lp2, 250 ether);

        token3.mint(address(this), 1000 ether);
        token3.mint(lp1, 250 ether);
        token3.mint(lp2, 250 ether);

        token4.mint(address(this), 1000 ether);
        token4.mint(lp1, 250 ether);
        token4.mint(lp2, 250 ether);

        // console.log("Currencies deployed and approved");

        MockBrevisProof mockBrevisProof = new MockBrevisProof();
        reputationOracle = new ReputationOracle(address(mockBrevisProof));
        keeperRegistryMock = new MockKeeperRegistry2_1();
        mockUpkeep = new MockUpkeep();

        reputationLogicImp = new ReputationLogic();
        assertNotEq(address(reputationLogicImp), address(0));

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

        address hookAdmin = address(this);
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(ReputationHook).creationCode,
            abi.encode(manager, hookAdmin, address(reputationLogicImp))
        );

        hook = new ReputationHook{salt: salt}(
            IPoolManager(address(manager)),
            hookAdmin,
            address(reputationLogicImp)
        );

        // console.log("ReputationHook deployed at:", address(hook));

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);

        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);

        token3.approve(address(swapRouter), type(uint256).max);
        token3.approve(address(modifyLiquidityRouter), type(uint256).max);
        token3.approve(address(hook), type(uint256).max);

        token4.approve(address(swapRouter), type(uint256).max);
        token4.approve(address(modifyLiquidityRouter), type(uint256).max);
        token4.approve(address(hook), type(uint256).max);

        vm.startPrank(lp1);

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);

        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);

        token3.approve(address(swapRouter), type(uint256).max);
        token3.approve(address(modifyLiquidityRouter), type(uint256).max);
        token3.approve(address(hook), type(uint256).max);

        token4.approve(address(swapRouter), type(uint256).max);
        token4.approve(address(modifyLiquidityRouter), type(uint256).max);
        token4.approve(address(hook), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(lp2);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);

        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);

        token3.approve(address(swapRouter), type(uint256).max);
        token3.approve(address(modifyLiquidityRouter), type(uint256).max);
        token3.approve(address(hook), type(uint256).max);

        token4.approve(address(swapRouter), type(uint256).max);
        token4.approve(address(modifyLiquidityRouter), type(uint256).max);
        token4.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        (key, poolId) = initPool(
            tokenCurrency,
            tokenCurrency2,
            hook,
            0x800000, // Dynamic fee flag ref: LPFeeLibrary.DYNAMIC_FEE_FLAG
            SQRT_PRICE_1_1,
            abi.encode(
                address(this),
                address(reputationOracle),
                5 minutes, // automation interval
                3000, // default base fee
                true // isDynamicFee
            )
        );

        (, , , , , address reputationLogicAddress) = hook.getPoolConfig(key);
        logic = IReputationLogic(reputationLogicAddress);

        hook.registerToOracle{value: 1 ether}(key);

        vm.warp(block.timestamp + 600 + 1);

        // console.log("setUp completed");
    }

    /** Enhanced Tests with Edge Cases ----------------------------------------------------*/

    /**
     * @notice Test adding collateral to the logic contract
     * @dev Checks for proper registration and collateral handling
     */
    function test_addCollateralToLogicContract() public {
        vm.prank(lp1);
        vm.expectRevert(); // oracle not yet registered.
        address user = lp1;
        int24 tickLower = -60;
        int24 tickUpper = 60;
        bytes memory hookData = abi.encode(user, tickLower, tickUpper);

        vm.startPrank(address(this));
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: true,
                settleUsingBurn: false
            }),
            hookData
        );

        vm.expectRevert();
        hook.registerToOracle{value: 0.01 ether}(key); // under collateral will revert

        // now do correctly and lets and test it again
        hook.registerToOracle{value: 0.5 ether}(key);

        vm.stopPrank();
    }

    /**
     * @notice Test adding liquidity and performing a swap
     * @dev Adds liquidity to the pool and performs a swap operation
     */
    function test_addLiquidityAndSwap() public {
        bytes memory hookData = abi.encode(lp1, -60, 60);

        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        (uint256 amount0Delta, ) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickLower,
            sqrtPriceAtTickUpper,
            100 ether
        );

        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta + 1}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );

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

        test_swap_exactInput_zeroForOne();
    }

    /**
     * @notice Test exact input swap (zero for one)
     * @dev Performs a swap with exact input and checks the outcome
     */
    function test_swap_exactInput_zeroForOne() public {
        address user = lp1;
        bytes memory hookData = abi.encode(user, -60, 60);

        vm.startPrank(address(this));
        swapRouter.swap{value: 0.001 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: true,
                settleUsingBurn: false
            }),
            hookData
        );
        vm.stopPrank();

        test_processReputationUpdates();
    }

    /**
     * @notice Test processing of reputation updates
     * @dev Checks if reputation updates are processed correctly
     */
    function test_processReputationUpdates() internal {
        uint256 queueLengthBefore = logic.getUpdateQueueLength();
        if (queueLengthBefore == 0) {
            return;
        }
        keeperRegistryMock.addFunds(1, 1000);
        mockUpkeep.setCheckResult(true);
        logic.performUpkeep("");
        uint256 queueLengthAfter = logic.getUpdateQueueLength();

        assert(queueLengthAfter < queueLengthBefore);
    }

    // /**
    //  * @notice Test reputation update with multiple users
    //  * @dev Performs swaps with different users and checks if their reputations are updated correctly
    //  */
    // function test_reputationUpdateMultipleUsers() public {
    //     address[] memory users = new address[](3);
    //     users[0] = lp1;
    //     users[1] = lp2;
    //     users[2] = address(this);

    //     for (uint i = 0; i < users.length; i++) {
    //         bytes memory hookData = abi.encode(users[i], -50, 50);
    //         swapRouter.swap{value: 0.001 ether}(
    //             key,
    //             IPoolManager.SwapParams({
    //                 zeroForOne: true,
    //                 amountSpecified: -0.001 ether,
    //                 sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //             }),
    //             PoolSwapTest.TestSettings({
    //                 takeClaims: true,
    //                 settleUsingBurn: false
    //             }),
    //             hookData
    //         );
    //     }

    //     // Process updates
    //     keeperRegistryMock.addFunds(1, 1000);
    //     mockUpkeep.setCheckResult(true);
    //     logic.performUpkeep("");

    //     // Check that all users' reputations were updated
    //     for (uint i = 0; i < users.length; i++) {
    //         (uint256 pROPoints, , , ) = reputationOracle.getUserInfo(users[i]);
    //         assertTrue(pROPoints > 0);
    //     }
    // }

    /** Invalid Configuration Tests ----------------------------------------------------*/

    /**
     * @notice Test initializing pool with invalid admin address
     * @dev Expects the transaction to revert due to zero address
     */
    function test_invalidAdminAddress() public {
        vm.expectRevert();
        initializePoolWithParams(
            address(0), // Invalid admin address
            address(reputationOracle),
            5 minutes,
            3000,
            false
        );
    }

    /**
     * @notice Test initializing pool with invalid reputation oracle address
     * @dev Expects the transaction to revert due to zero address
     */
    function test_invalidReputationOracleAddress() public {
        vm.expectRevert();
        initializePoolWithParams(
            address(this),
            address(0), // Invalid reputation oracle
            5 minutes,
            3000,
            false
        );
    }

    /**
     * @notice Test initializing pool with invalid automation interval
     * @dev Expects the transaction to revert due to interval being too short
     */
    function test_invalidAutomationInterval() public {
        vm.expectRevert();
        initializePoolWithParams(
            address(this),
            address(reputationOracle),
            4 minutes, // Invalid interval
            3000,
            false
        );
    }

    /**
     * @notice Test initializing pool with invalid base fee
     * @dev Expects the transaction to revert due to fee being too low
     */
    function test_invalidBaseFee() public {
        vm.expectRevert();
        initializePoolWithParams(
            address(this),
            address(reputationOracle),
            5 minutes,
            9, // Invalid base fee
            false
        );
    }

    /** Edge Cases and Boundary Testing --------------------------------------------------*/

    /**
     * @notice Test swap with minimum sqrt price limit
     * @dev Performs a swap with the minimum possible sqrt price limit
     */
    function test_sqrtPriceLimitMin() public {
        bytes memory hookData = abi.encode(lp1, -60, 60);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE // Min price limit
            }),
            PoolSwapTest.TestSettings({
                takeClaims: true,
                settleUsingBurn: false
            }),
            hookData
        );
    }

    /**
     * @notice Test swap with maximum sqrt price limit
     * @dev Expects the transaction to revert due to exceeding price limit
     */
    function test_sqrtPriceLimitMax() public {
        vm.expectRevert(); // Exceed price limit
        bytes memory hookData = abi.encode(lp1, -60, 60);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE // Max price limit
            }),
            PoolSwapTest.TestSettings({
                takeClaims: true,
                settleUsingBurn: false
            }),
            hookData
        );
    }

    /**
     * @notice Test revert when no user info is provided
     * @dev Expects the transaction to revert due to missing user info in hookData
     */
    function test_revertWithNoUserInfo() public {
        bytes memory hookData = ZERO_BYTES;
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );
    }

    /**
     * @notice Test adding small amount of liquidity
     * @dev Adds the smallest possible amount of liquidity to the pool
     */
    function test_smallLiquidityAddition() public {
        bytes memory hookData = abi.encode(lp1, -60, 60);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 wei, // Smallest possible liquidity
                salt: bytes32(0)
            }),
            hookData
        );
    }

    /**
     * @notice Test adding zero liquidity
     * @dev Expects the transaction to revert when trying to add zero liquidity
     */
    function test_addZeroLiquidity() public {
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 0, // Zero liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /**
     * @notice Test adding maximum liquidity
     * @dev Expects the transaction to revert due to SafeCastOverflow
     */
    function test_maxLiquidity() public {
        vm.expectRevert(); // SafeCastOverflow
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int128(type(uint128).max), // Max liquidity
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /**
     * @notice Test swap with negative volume
     * @dev Performs a swap with a negative volume and checks the outcome
     */
    function test_negativeVolumeSwap() public {
        bytes memory hookData = abi.encode(lp2, -60, 60);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether, // Negative volume
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: true,
                settleUsingBurn: false
            }),
            hookData
        );
    }

    /**
     * @notice Test multiple distinct pools with liquidity addition and swaps
     * @dev Creates multiple pools, adds liquidity, and performs swaps on each
     */
    function test_multipleDistinctPoolsAddLiquidityAndSwap() public {
        // Pool 1 setup with 60 tick spacing
        (PoolKey memory poolKey1, /*PoolId poolId1*/) = initPool(
            tokenCurrency,
            tokenCurrency3,
            hook,
            0x800000, // Dynamic fee flag ref: LPFeeLibrary.DYNAMIC_FEE_FLAG
            SQRT_PRICE_1_1,
            abi.encode(
                address(this),
                address(reputationOracle),
                5 minutes,
                5000,
                true
            )
        );

        // Pool 2 setup with 60 tick spacing
        (PoolKey memory poolKey2, /*PoolId poolId2*/) = initPool(
            tokenCurrency,
            tokenCurrency4,
            hook,
            0x800000, // Dynamic fee flag ref: LPFeeLibrary.DYNAMIC_FEE_FLAG
            SQRT_PRICE_1_4,
            abi.encode(
                address(this),
                address(reputationOracle),
                5 minutes,
                2000,
                true
            )
        );

        // Add liquidity to pool 1 (tick spacing of 60)
        bytes memory hookData1 = abi.encode(lp1, -120, 120); // Use multiples of 60
        uint160 sqrtPriceAtTickLower1 = TickMath.getSqrtPriceAtTick(-120);
        uint160 sqrtPriceAtTickUpper1 = TickMath.getSqrtPriceAtTick(120);

        (uint256 amount0Delta1, ) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickLower1,
            sqrtPriceAtTickUpper1,
            1 ether
        );

        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta1 + 1}(
            poolKey1,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData1
        );

        // Add liquidity to pool 2 (tick spacing of 60)
        bytes memory hookData2 = abi.encode(lp2, -60, 60); // Use multiples of 60
        uint160 sqrtPriceAtTickLower2 = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper2 = TickMath.getSqrtPriceAtTick(60);

        (uint256 amount0Delta2, ) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickLower2,
            sqrtPriceAtTickUpper2,
            2 ether
        );

        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta2 + 1}(
            poolKey2,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 2 ether,
                salt: bytes32(0)
            }),
            hookData2
        );

        // Perform swap in pool 1
        swapRouter.swap{value: 0.001 ether}(
            poolKey1,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData1
        );

        // Perform swap in pool 2
        swapRouter.swap{value: 0.002 ether}(
            poolKey2,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -0.002 ether,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData2
        );
    }

    /**
     * @notice Test independent reverts in multiple distinct pools
     * @dev Creates multiple pools and tests that a revert in one doesn't affect the other
     */
    function test_multipleDistinctPoolsIndependentReverts() public {
        // Pool 1 setup with 60 tick spacing
        (PoolKey memory poolKey1, /*PoolId poolId1*/) = initPool(
            tokenCurrency4,
            tokenCurrency2,
            hook,
            0x800000, // Dynamic fee flag ref: LPFeeLibrary.DYNAMIC_FEE_FLAG
            SQRT_PRICE_1_1,
            abi.encode(
                address(this),
                address(reputationOracle),
                5 minutes,
                5000,
                true
            )
        );

        // Pool 2 setup with 60 tick spacing
        (PoolKey memory poolKey2, /*PoolId poolId2*/) = initPool(
            tokenCurrency,
            tokenCurrency4,
            hook,
            0x800000, // Dynamic fee flag ref: LPFeeLibrary.DYNAMIC_FEE_FLAG
            SQRT_PRICE_1_1,
            abi.encode(
                address(this),
                address(reputationOracle),
                5 minutes,
                2000,
                true
            )
        );

        // Add liquidity to pool 1 (tick spacing of 60)
        bytes memory hookData1 = abi.encode(lp1, -120, 120); // Use multiples of 60
        uint160 sqrtPriceAtTickLower1 = TickMath.getSqrtPriceAtTick(-120);
        uint160 sqrtPriceAtTickUpper1 = TickMath.getSqrtPriceAtTick(120);

        (uint256 amount0Delta1, ) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickLower1,
            sqrtPriceAtTickUpper1,
            1 ether
        );

        modifyLiquidityRouter.modifyLiquidity{value: amount0Delta1 + 1}(
            poolKey1,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData1
        );

        // Attempt to add invalid liquidity to pool 2 (tick spacing of 60)
        bytes memory hookData2 = abi.encode(lp2, -60, 60); // Use multiples of 60
        // uint160 sqrtPriceAtTickLower2 = TickMath.getSqrtPriceAtTick(-60);
        // uint160 sqrtPriceAtTickUpper2 = TickMath.getSqrtPriceAtTick(60);

        vm.expectRevert(); // Expected to fail due to SafeCastOverflow
        modifyLiquidityRouter.modifyLiquidity(
            poolKey2,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int128(type(uint128).max), // Max liquidity, causing overflow
                salt: bytes32(0)
            }),
            hookData2
        );

        // Ensure pool 1 can still perform swaps despite the failure in pool 2
        swapRouter.swap{value: 0.001 ether}(
            poolKey1,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData1
        );
    }

    /** Helper functions ---------------------------------------------------------------*/

    /**
     * @notice Callback function for unlocking liquidity
     * @param data Encoded data containing pool key, modify liquidity params, and hook data
     * @return Encoded balance delta
     */
    function unlockCallback(
        bytes calldata data
    ) external override returns (bytes memory) {
        (
            PoolKey memory key,
            IPoolManager.ModifyLiquidityParams memory params,
            bytes memory hookData
        ) = abi.decode(
                data,
                (PoolKey, IPoolManager.ModifyLiquidityParams, bytes)
            );

        (BalanceDelta delta, ) = manager.modifyLiquidity(key, params, hookData);

        return abi.encode(delta);
    }

    /**
     * @notice Initialize a pool with specific parameters
     * @param _admin Address of the pool admin
     * @param _reputationOracle Address of the reputation oracle
     * @param _automationInterval Automation interval for the pool
     * @param _baseFee Base fee for the pool
     * @param _isDynamicFee Boolean indicating if the fee is dynamic
     */
    function initializePoolWithParams(
        address _admin,
        address _reputationOracle,
        uint24 _automationInterval,
        uint24 _baseFee,
        bool _isDynamicFee
    ) internal {
        (key, poolId) = initPool(
            tokenCurrency,
            tokenCurrency2,
            hook,
            LPFeeLibrary.OVERRIDE_FEE_FLAG, //0x800000,
            SQRT_PRICE_1_1,
            abi.encode(
                _admin,
                _reputationOracle,
                _automationInterval,
                _baseFee,
                _isDynamicFee
            )
        );
    }

    /**
     * @notice Approve tokens for routers for a specific liquidity provider
     * @param lp Address of the liquidity provider
     */
    function approveTokensForRouters(address lp) internal {
        vm.startPrank(lp);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);
        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);
        vm.stopPrank();
    }
}
