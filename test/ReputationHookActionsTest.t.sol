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
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {MockBrevisProof} from "../src/mocks/MockBrevisProof.sol";
import {ReputationOracle} from "../src/ReputationOracle.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {HookUtils} from "../src/libs/HookUtils.sol";
import {MockKeeperRegistry2_1} from "../src/mocks/MockKeeperRegistry2_1.sol";
import {MockUpkeep} from "../src/mocks/MockUpkeep.sol";
import {ReputationLogic} from "../src/ReputationLogic.sol";
import {IReputationLogic} from "../src/interfaces/IReputationLogic.sol";
import {HookOracle} from "../src/HookOracle.sol";
import {IHookOracle} from "../src/interfaces/IHookOracle.sol";

import "forge-std/console.sol";

/**
 * @title ReputationHookTest
 * @notice Test contract for ReputationHook functionality
 * @dev Inherits from Test, Deployers, and IUnlockCallback
 */
contract ReputationHookTest is Test, Deployers, IUnlockCallback {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SwapFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    ReputationHook hook;
    PoolId poolId;
    ReputationOracle reputationOracle;
    IReputationLogic logic;
    IHookOracle hookOracle;

    ReputationLogic reputationLogicImp;

    MockKeeperRegistry2_1 keeperRegistryMock;
    MockUpkeep mockUpkeep;

    MockERC20 token;
    MockERC20 token2;

    Currency tokenCurrency;
    Currency tokenCurrency2;

    address lp1 = makeAddr("LP1");
    address lp2 = makeAddr("LP2");

    /**
     * @notice Sets up the test environment
     * @dev Deploys necessary contracts and initializes test state
     */
    function setUp() public {
        // console.log("Starting setUp");
  
        deployFreshManagerAndRouters();

        token = new MockERC20("Main Token", "MTK", 18);
        tokenCurrency = Currency.wrap(address(token));

        token2 = new MockERC20("Second Token", "SCT", 18);
        tokenCurrency2 = Currency.wrap(address(token2));

        // Mint tokens to participants
        token.mint(address(this), 1000 ether);
        token.mint(lp1, 250 ether);
        token.mint(lp2, 250 ether);

        token2.mint(address(this), 1000 ether);
        token2.mint(lp1, 250 ether);
        token2.mint(lp2, 250 ether);

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

        // optional: create a hook oracle on top of the hook's meta-pool
        hookOracle = new HookOracle(address(hook), hookAdmin);

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);
        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);

        vm.startPrank(lp1);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);
        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lp2);
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(hook), type(uint256).max);
        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(hook), type(uint256).max);
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
                5 minutes,
                3000,
                false // isDynamicFee - switch whether use base 3000 or dynamic fee
            )
        );

        (address _admin, , , , , address reputationLogicAddress) = hook.getPoolConfig(key);
        logic = IReputationLogic(reputationLogicAddress);

        // console.log("Checking pool credentials");
        assertEq(_admin, address(this));

        hook.registerToOracle{value: 1 ether}(key);
  
        vm.warp(block.timestamp + 600 + 1);
    }

    /**
     * @notice Tests adding liquidity and performing a swap
     */
    function test_addLiquidityAndSwap() public {
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

        vm.warp(block.timestamp + 150);

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
     * @notice Tests exact input swap (zero for one)
     */
    function test_swap_exactInput_zeroForOne() internal {
        vm.warp(block.timestamp + 150);

        address user = lp1;
        int24 tickLower = -80;
        int24 tickUpper = 80;
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
        vm.stopPrank();
 
        test_processReputationUpdates();
    }

    /**
     * @notice Tests processing of reputation updates
     */
    function test_processReputationUpdates() internal {
        uint256 queueLengthBefore = logic.getUpdateQueueLength();
        keeperRegistryMock.addFunds(1, 1000);
        mockUpkeep.setCheckResult(true);
        logic.performUpkeep("");
        uint256 queueLengthAfter = logic.getUpdateQueueLength();

        assert(queueLengthAfter < queueLengthBefore);
    }

    /**
     * @notice Tests ReputationLogic ownership
     */
    function test_ReputationLogicOwnerShip() public view {
        address logicAdmin = logic.getAdmin();
        assertEq(logicAdmin, address(this));
    }

    /**
     * @notice Tests if hook has the required permissions
     */
    function test_HookHasPermitted() public view {
        bool permitted = logic.getHookHasPermitted(address(hook));
        assert(permitted);
    }

    /**
     * @notice Tests adding zero liquidity (should revert)
     */
    function test_addZeroLiquidity() public {
        vm.expectRevert();
        int24 tickLower = -60;
        int24 tickUpper = 60;
        bytes memory hookData = abi.encode(lp1, tickLower, tickUpper);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: 0, // Zero liquidity
                salt: bytes32(0)
            }),
            hookData
        );
    }

    /**
     * @notice Tests adding maximum liquidity (should revert due to SafeCastOverflow)
     */
    function test_maxLiquidity() public {
        vm.expectRevert(); // SafeCastOverflow
        int24 tickLower = -60;
        int24 tickUpper = 60;
        bytes memory hookData = abi.encode(lp1, tickLower, tickUpper);

        uint128 maxLiquidity = type(uint128).max;

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(maxLiquidity),
                salt: bytes32(0)
            }),
            hookData
        );
    }

    /**
     * @notice Tests a swap with negative volume
     */
    function test_negativeVolumeSwap() public {
        bytes memory hookData = abi.encode(lp1, -60, 60);

        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether, // Negative volume for swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
    }

    /**
     * @notice Tests multiple users adding liquidity
     */
    function test_multipleUsersAddLiquidity() public {
        for (uint i = 1; i <= 50; i++) {
            vm.startPrank(lp2);

            bytes memory hookData = abi.encode(lp2, -60, 60);
            modifyLiquidityRouter.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: -60,
                    tickUpper: 60,
                    liquidityDelta: 0.1 ether, // Small liquidity per user
                    salt: bytes32(0)
                }),
                hookData
            );
 
            vm.stopPrank();
        }
    }
  
    /** Helper functions ---------------------------------------------------------------*/

    /**
     * @notice Callback function for unlocking liquidity
     * @param data The encoded data containing pool key, modify liquidity params, and hook data
     * @return The encoded balance delta
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
}
