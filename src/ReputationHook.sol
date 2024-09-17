// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ReentrancyGuard} from "./libs/ReentrancyGuard.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {HookUtils} from "./libs/HookUtils.sol";
import {ConfigUtils} from "./libs/ConfigUtils.sol";
import {ReputationTypes} from "./libs/ReputationTypes.sol";
import {IReputationHook} from "./interfaces/IReputationHook.sol";
import {IReputationLogic} from "./interfaces/IReputationLogic.sol";
import {IReputationOracle} from "./interfaces/IReputationOracle.sol";
import {MetaPoolLibrary} from "./libs/MetaPoolLibrary.sol";
import {ICustomPoolHook} from "./interfaces/IHulks.sol";

/**
 * @title ReputationHook
 * @notice A hook contract for managing reputation and dynamic fees in Uniswap V4 pools
 * @dev Implements BaseHook and IReputationHook interfaces
 */
contract ReputationHook is BaseHook, ReentrancyGuard, IReputationHook {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;
    using ConfigUtils for bytes32;
    using ERC165Checker for address;
    using MetaPoolLibrary for MetaPoolLibrary.MetaPool;

    /**
     * @notice Fixed fee taken by the hook on each swap
     */
    uint256 public constant FIXED_HOOK_FEE = 0.0001e18;

    uint256 public constant MIN_COLLATERAL_AMOUNT = 0.1 ether;

    /**
     * @notice Mapping of pool IDs to their respective Pools struct
     */
    mapping(PoolId => Pools) private pools;

    /**
     * @notice Mapping of admin addresses to their balances
     */
    mapping(address => uint256) internal adminBalances;

    /**
     * @notice Mapping of pool IDs to their custom pool hooks
     */
    mapping(PoolId => ICustomPoolHook) public customPoolHooks;

    /**
     * @notice MetaPool instance for storing aggregate pool data
     */
    MetaPoolLibrary.MetaPool private metaPool;

    /**
     * @notice Address of the hook admin
     */
    address public hookAdmin;

    /**
     * @notice Address of the ReputationLogic implementation contract
     */
    address private reputationLogicImplementation;

    /**
     * @notice Modifier to restrict function access to the hook admin
     */
    modifier onlyHookAdmin() {
        if (msg.sender != hookAdmin) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Modifier to restrict function access to the pool admin
     * @param key The PoolKey of the pool
     */
    modifier onlyPoolAdmin(PoolKey calldata key) {
        if (msg.sender != pools[key.toId()].admin) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Modifier to restrict function access to the pool admin & hook admin
     * @param key The PoolKey of the pool
     */
    modifier onlyPoolOrHookAdmin(PoolKey calldata key) {
        if (msg.sender != pools[key.toId()].admin && msg.sender != hookAdmin) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Modifier to ensure the pool is initialized before certain operations
     * @param key The PoolKey of the pool
     */
    modifier onlyRegisteredPools(PoolKey calldata key) {
        PoolId poolId = key.toId();
        if (pools[poolId].reputationOracle == IReputationOracle(address(0))) {
            revert PoolNotInitialized();
        }
        _;
    }

    /**
     * @notice Constructor for the ReputationHook contract
     * @param _poolManager Address of the IPoolManager contract
     * @param _hookAdmin Address of the hook admin
     * @param _reputationLogicImplementation Address of the ReputationLogic implementation
     */
    constructor(
        IPoolManager _poolManager,
        address _hookAdmin,
        address _reputationLogicImplementation
    ) BaseHook(_poolManager) {
        hookAdmin = _hookAdmin;
        reputationLogicImplementation = _reputationLogicImplementation;
    }

    /**
     * @notice Updates the ReputationLogic implementation address
     * @param _reputationLogicImplementation The new implementation address
     */
    function updateReputationLogicImp(
        address _reputationLogicImplementation
    ) external onlyHookAdmin {
        reputationLogicImplementation = _reputationLogicImplementation;
    }

    /**
     * @notice Returns the hook permissions
     * @return Hooks.Permissions struct with the hook permissions
     */
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /**
     * @notice Hook called before pool initialization
     * param sender Address of the sender
     * @param key PoolKey of the pool
     * param sqrtPriceX96 Initial sqrt price of the pool
     * @param hookData Additional data for the hook
     * @return The function selector
     */
    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4) {
        (
            address _admin,
            address _reputationOracle,
            uint24 _automationInterval,
            uint24 _baseFee,
            bool _isDynamicFee
        ) = abi.decode(hookData, (address, address, uint24, uint24, bool));

        HookUtils.validateUniswapParams(
            _admin,
            _reputationOracle,
            _automationInterval,
            _baseFee
        );

        address reputationLogicAddress = HookUtils.deployReputationLogic(
            reputationLogicImplementation,
            _admin,
            _reputationOracle,
            _automationInterval
        );

        if (reputationLogicAddress == address(0)) {
            revert("Reputation Logic deployment failed");
        }

        PoolId poolId = key.toId();

        if (!key.fee.isDynamicFee()) {
            revert MustUseDynamicFee();
        }

        Pools storage pool = pools[poolId];

        pool.admin = _admin;
        pool.configData = ConfigUtils.packConfig(
            ConfigUtils.ConfigData({
                automationInterval: _automationInterval,
                baseFee: _baseFee,
                isDynamicFee: _isDynamicFee
            })
        );

        pool.isActive = true; // By default, the pool is active
        pool.reputationOracle = IReputationOracle(_reputationOracle);
        pool.reputationLogic = IReputationLogic(reputationLogicAddress);

        metaPool.updateMetaPoolMetrics(
            poolManager,
            poolId,
            address(0),
            0,
            0,
            0,
            0
        );

        emit PoolCreated(poolId);

        return this.beforeInitialize.selector;
    }

    /**
     * @notice Hook called after pool initialization
     * param sender Address of the sender
     * @param key PoolKey of the pool
     * param sqrtPriceX96 Initial sqrt price of the pool
     * param tick Initial tick of the pool
     * param hookData Additional data for the hook
     * @return The function selector
     */
    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();
        Pools storage pool = pools[poolId];
        uint24 _baseFee = ConfigUtils.getBaseFee(pool.configData);

        poolManager.updateDynamicLPFee(key, _baseFee);

        return this.afterInitialize.selector;
    }

    /**
     * @notice Hook called before adding liquidity
     * param sender Address of the sender
     * param key PoolKey of the pool
     * param params Liquidity parameters
     * param hookData Additional data for the hook
     * @return The function selector
     */
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        return this.beforeAddLiquidity.selector;
    }

    /**
     * @notice Hook called after adding liquidity
     * param sender Address of the sender
     * @param key PoolKey of the pool
     * @param params Liquidity parameters
     * @param delta Balance delta
     * @param hookData Additional data for the hook
     * @return The function selector and the balance delta
     */
    function afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    )
        external
        override
        onlyPoolManager
        onlyRegisteredPools(key)
        returns (bytes4, BalanceDelta)
    {
        (address user, int24 tickLower, int24 tickUpper) = abi.decode(
            hookData,
            (address, int24, int24)
        );

        if (user != address(0)) {
            PoolId poolId = key.toId();
            metaPool.updateMetaPoolMetrics(
                poolManager,
                poolId,
                user,
                params.liquidityDelta,
                0,
                tickLower,
                tickUpper
            );
        }

        return (this.afterAddLiquidity.selector, delta);
    }

    /**
     * @notice Hook called after removing liquidity
     * param sender Address of the sender
     * @param key PoolKey of the pool
     * @param params Liquidity parameters
     * @param delta Balance delta
     * @param hookData Additional data for the hook
     * @return The function selector and the balance delta
     */
    function afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    )
        external
        override
        onlyPoolManager
        onlyRegisteredPools(key)
        returns (bytes4, BalanceDelta)
    {
        (address user, int24 tickLower, int24 tickUpper) = abi.decode(
            hookData,
            (address, int24, int24)
        );

        if (user != address(0)) {
            PoolId poolId = key.toId();
            metaPool.updateMetaPoolMetrics(
                poolManager,
                poolId,
                user,
                -params.liquidityDelta,
                0,
                tickLower,
                tickUpper
            );
        }

        return (this.afterRemoveLiquidity.selector, delta);
    }

    /**
     * @notice Hook called before a swap
     * param sender Address of the sender
     * @param key PoolKey of the pool
     * @param params Swap parameters
     * @param hookData Additional data for the hook
     * @return The function selector, before swap delta, and fee
     */
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (address user, , ) = abi.decode(hookData, (address, int24, int24));

        PoolId poolId = key.toId();
        Pools storage pool = pools[poolId];

        uint24 fee = ConfigUtils.getBaseFee(pool.configData);
        uint256 points = 0;

        /* ------------------------------- CUSTOM HOOKS -------------------------------- */

        // Custom hooks for each pool - from Custom Hook Providers (Hulks)
        ICustomPoolHook customHook = customPoolHooks[poolId];

        if (address(customHook) != address(0)) {
            require(
                address(customHook).supportsInterface(
                    type(ICustomPoolHook).interfaceId
                ),
                "Custom hook does not implement ICustomPoolHook"
            );

            ICustomPoolHook.CustomHookResult memory result = customHook
                .beforeSwap(user, key, params, hookData);
            // e.g.
            if (!result.allowSwap) {
                revert("Swap not allowed by custom hook");
            }

            if (result.customFee > 0) {
                fee = uint24(result.customFee);
            }

            if (result.extraData.length > 0) {
                // Optionally handle extra data
            }
        }

        /* ------------------------------- CUSTOM HOOKS -------------------------------- */

        bool dynamicFee = ConfigUtils.isDynamicFee(pool.configData);
        if (dynamicFee) {
            if (user != address(0)) {
                points = _getUserPoints(key, user);

                if (points != 0) fee = _calculateDynamicFee(points, fee);
            }

            fee = _asOverrideFee(fee);
        } else {
            fee = ConfigUtils.getBaseFee(pool.configData);
        }

        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee
        );
    }

    /**
     * @notice Hook called after a swap
     * param sender Address of the sender
     * @param key PoolKey of the pool
     * @param params Swap parameters
     * @param delta Balance delta
     * @param hookData Additional data for the hook
     * @return The function selector and the hook fee
     */
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    )
        external
        override
        onlyPoolManager
        onlyRegisteredPools(key)
        returns (bytes4, int128)
    {
        (address user, int24 tickLower, int24 tickUpper) = abi.decode(
            hookData,
            (address, int24, int24)
        );

        PoolId poolId = key.toId();
        ICustomPoolHook customHook = customPoolHooks[poolId];

        /* ------------------------------- HULKS! the CUSTOM HOOKS -------------------------------- */

        if (address(customHook) != address(0)) {
            require(
                address(customHook).supportsInterface(
                    type(ICustomPoolHook).interfaceId
                ),
                "Custom hook does not implement ICustomPoolHook"
            );

            ICustomPoolHook.CustomHookResult memory result = customHook
                .afterSwap(user, key, params, delta, hookData);

            ICustomPoolHook.CustomHookResult memory result2 = customHook
                .whenTickRangeIsBetween(
                    user,
                    key,
                    -60,
                    60,
                    params,
                    delta,
                    hookData
                );

            ICustomPoolHook.CustomHookResult memory result3 = customHook
                .whenTheWeatherIsRainy(user, key, params, delta, hookData);

            bytes[] memory results = new bytes[](3);
            results[0] = result.extraData;
            results[1] = result2.extraData;
            results[3] = result3.extraData;
            ICustomPoolHook.CustomHookResult memory __result4 = customHook
                .whenHulksChained(user, key, params, delta, hookData, "genesis", results);
            // customResult can be used for further processing...
        }

        /* ------------------------------- HULKS! the CUSTOM HOOKS -------------------------------- */

        int256 volumeTraded = params.zeroForOne
            ? delta.amount0()
            : delta.amount1();
        uint256 absVolumeTraded = volumeTraded < 0
            ? uint256(-volumeTraded)
            : uint256(volumeTraded);

        if (user != address(0) && absVolumeTraded != 0) {
            metaPool.updateMetaPoolMetrics(
                poolManager,
                poolId,
                user,
                0,
                volumeTraded,
                tickLower,
                tickUpper
            );
        }

        uint256 hookFee = (absVolumeTraded * FIXED_HOOK_FEE) / 1e18;

        Currency feeCurrency = params.zeroForOne
            ? key.currency1
            : key.currency0;
        if (feeCurrency.isNative()) {
            Pools memory pool = pools[poolId];
            poolManager.take(
                feeCurrency,
                address(pool.reputationLogic),
                hookFee
            );
        } else {
            poolManager.take(feeCurrency, address(this), hookFee);
        }

        _queueReputationUpdate(
            poolId,
            user,
            volumeTraded,
            tickLower,
            tickUpper,
            key.currency0,
            key.currency1
        );

        return (BaseHook.afterSwap.selector, int128(int256(hookFee)));
    }

    /**
     * @notice Applies the override fee flag to a fee
     * @param self The fee to apply the flag to
     * @return The fee with the override flag applied
     */
    function _asOverrideFee(uint24 self) internal pure returns (uint24) {
        return self | LPFeeLibrary.OVERRIDE_FEE_FLAG;
    }

    /**
     * @notice Calculates the fee based on user points
     * @param points The user's points
     * @param baseFee The baseFee fee
     * @return The calculated fee
     */
    function _calculateDynamicFee(
        uint256 points,
        uint24 baseFee
    ) internal pure returns (uint24) {
        if (points > 10000) {
            return baseFee / 2; // 50% discount
        } else if (points > 5000) {
            return (baseFee * 75) / 100; // 25% discount
        } else if (points > 1000) {
            return (baseFee * 90) / 100; // 10% discount
        } else {
            return baseFee;
        }
    }

    /**
     * @notice Retrieves the user points from the reputation oracle
     * @param key The PoolKey of the pool
     * @param user The address of the user
     * @return The user's points
     */
    function _getUserPoints(
        PoolKey calldata key,
        address user
    ) internal view returns (uint256) {
        try pools[key.toId()].reputationOracle.getUserPoints(user) returns (
            uint256 _points
        ) {
            return _points;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Sets a new hook admin
     * @param _hookAdmin The address of the new hook admin
     */
    function setHookAdmin(address _hookAdmin) external onlyHookAdmin {
        hookAdmin = _hookAdmin;
        emit HookAdminUpdated(_hookAdmin);
    }

    /**
     * @notice Retrieves the meta pool statistics
     * @return totalValueLocked The total value locked in the meta pool
     * @return totalVolumeTraded The total volume traded in the meta pool
     * @return activePoolCount The number of active pools
     * @return totalUniqueUsers The total number of unique users
     */
    function getMetaPoolStats()
        external
        view
        returns (
            uint256 totalValueLocked,
            uint256 totalVolumeTraded,
            uint256 activePoolCount,
            uint256 totalUniqueUsers
        )
    {
        return metaPool.getMetaPoolStats();
    }

    /**
     * @notice Retrieves statistics for a specific pool
     * @param poolId The ID of the pool
     * @return totalLiquidity The total liquidity in the pool
     * @return currentTick The current tick of the pool
     * @return volumeTraded The volume traded in the pool
     * @return apr The annual percentage rate of the pool
     * @return apy The annual percentage yield of the pool
     * @return healthScore The health score of the pool
     * @return volatility The volatility of the pool
     * @return zapInOutCount The number of zap in/out operations
     * @return liquidityChangeCount The number of liquidity change operations
     * @return tickMoveSpeed The speed of tick movement
     * @return priceChangeAcceleration The acceleration of price change
     */
    function getPoolStats(
        PoolId poolId
    )
        external
        view
        returns (
            uint256 totalLiquidity,
            int24 currentTick,
            uint256 volumeTraded,
            uint256 apr,
            uint256 apy,
            uint256 healthScore,
            uint256 volatility,
            uint256 zapInOutCount,
            uint256 liquidityChangeCount,
            int256 tickMoveSpeed,
            int256 priceChangeAcceleration
        )
    {
        return metaPool.getPoolStats(poolManager, poolId);
    }

    /**
     * @notice Retrieves statistics for a specific user in a pool
     * @param poolId The ID of the pool
     * @param user The address of the user
     * @return totalLiquidity The total liquidity provided by the user
     * @return totalVolume The total volume traded by the user
     * @return actionCount The number of actions performed by the user
     */
    function getUserStats(
        PoolId poolId,
        address user
    )
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 totalVolume,
            uint256 actionCount
        )
    {
        return metaPool.getUserStats(poolId, user);
    }

    /**
     * @notice Checks if a user is new to the system
     * @param user The address of the user
     * @return A boolean indicating whether the user is new
     */
    function isNewUser(address user) external view returns (bool) {
        return metaPool.isNewUser(user);
    }

    /* Pool management  ------------------------------------------------------------- */

    /**
     * @notice Activates a pool
     * @param key The PoolKey of the pool to activate
     */
    function activatePool(PoolKey calldata key) external onlyPoolAdmin(key) {
        PoolId poolId = key.toId();
        pools[poolId].isActive = true;
        emit PoolActivated(poolId);
    }

    /**
     * @notice Deactivates a pool
     * @param key The PoolKey of the pool to deactivate
     */
    function deactivatePool(PoolKey calldata key) external onlyPoolAdmin(key) {
        PoolId poolId = key.toId();
        pools[poolId].isActive = false;
        emit PoolDeactivated(poolId);
    }

    /**
     * @notice Checks if a pool is active
     * @param key The PoolKey of the pool to check
     * @return A boolean indicating whether the pool is active
     */
    function getIsPoolActive(
        PoolKey calldata key
    ) external view returns (bool) {
        PoolId poolId = key.toId();
        return pools[poolId].isActive;
    }

    /**
     * @notice Retrieves the configuration of a pool
     * @param key The PoolKey of the pool
     * @return admin The address of the pool admin
     * @return baseFee The base fee of the pool
     * @return automationInterval The automation interval of the pool
     * @return isDynamicFee A boolean indicating whether the fee is dynamic
     * @return reputationOracle The address of the reputation oracle
     * @return reputationLogic The address of the reputation logic contract
     */
    function getPoolConfig(
        PoolKey calldata key
    )
        external
        view
        returns (
            address admin,
            uint24 baseFee,
            uint24 automationInterval,
            bool isDynamicFee,
            address reputationOracle,
            address reputationLogic
        )
    {
        PoolId poolId = key.toId();
        Pools storage pool = pools[poolId];
        ConfigUtils.ConfigData memory configData = ConfigUtils.unpackConfig(
            pool.configData
        );

        return (
            pool.admin,
            configData.baseFee,
            configData.automationInterval,
            configData.isDynamicFee,
            address(pool.reputationOracle),
            address(pool.reputationLogic)
        );
    }

    /**
     * @notice Queues a reputation update for a user
     * @param poolId The ID of the pool
     * @param user The address of the user
     * @param volumeTraded The volume traded by the user
     * @param tickLower The lower tick of the user's position
     * @param tickUpper The upper tick of the user's position
     * @param currency0 The first currency of the pool
     * @param currency1 The second currency of the pool
     */
    function _queueReputationUpdate(
        PoolId poolId,
        address user,
        int256 volumeTraded,
        int24 tickLower,
        int24 tickUpper,
        Currency currency0,
        Currency currency1
    ) internal {
        Pools storage pool = pools[poolId];
        (, int24 currentTick, , ) = poolManager.getSlot0(poolId);

        ReputationTypes.ReputationUpdate memory _update = ReputationTypes
            .ReputationUpdate({
                user: user,
                swapInfo: ReputationTypes.SwapInfo({
                    amount0: volumeTraded,
                    amount1: -volumeTraded,
                    zeroForOne: volumeTraded > 0,
                    amountSpecified: volumeTraded
                }),
                tickInfo: ReputationTypes.TickInfo({
                    currentTick: currentTick,
                    lastTick: currentTick // We're not storing lastTick anymore, so we use currentTick
                }),
                tokenInfo: ReputationTypes.TokenInfo({
                    token0: Currency.unwrap(currency0),
                    token1: Currency.unwrap(currency1)
                }),
                metricsInfo: ReputationTypes.MetricsInfo({
                    liquidityUtilization: metaPool.getLiquidityUtilization(
                        poolManager,
                        poolId,
                        user
                    ),
                    tickRange: uint24(tickUpper - tickLower),
                    activityScore: metaPool.getActivityScore(poolId, user)
                })
            });

        try pool.reputationLogic.queueReputationUpdate(_update) {} catch {
            // unblocking but it could be enhanced
        }
    }

    /**
     * @notice Deposits fee collateral for a pool
     * @param key The PoolKey of the pool
     */
    function depositFeeCollateral(
        PoolKey calldata key
    ) public payable override nonReentrant onlyPoolAdmin(key) {
        if (msg.value < MIN_COLLATERAL_AMOUNT) revert CollateralAmountTooLow();
        require(msg.value > 0, "No collateral provided");

        PoolId poolId = key.toId();
        Pools storage pool = pools[poolId];

        emit CollateralDeposited(msg.sender, msg.value, poolId);

        pool.reputationOracle.depositFeeCollateral{value: msg.value}(
            address(pool.reputationLogic)
        );
    }

    /**
     * @notice Registers a pool with the oracle
     * @param key The PoolKey of the pool
     */
    function registerToOracle(
        PoolKey calldata key
    ) public payable override nonReentrant onlyPoolOrHookAdmin(key) {
        require(msg.value >= 0.1 ether, "Insufficient registration fee");

        _registerToOracleSilent(key, msg.value);

        emit OracleRegistered(msg.sender, key.toId(), msg.value);
    }

    /**
     * @notice Silently registers a pool with the oracle
     * @param key The PoolKey of the pool
     * @param value The registration fee
     */
    function _registerToOracleSilent(
        PoolKey calldata key,
        uint256 value
    ) internal {
        PoolId poolId = key.toId();
        Pools storage pool = pools[poolId];

        require(
            address(this).balance >= value,
            "Insufficient contract balance for registration"
        );
        require(
            address(pool.reputationLogic) != address(0),
            "ReputationLogic address is not set"
        );

        (bool success, bytes memory data) = address(pool.reputationLogic).call{
            value: value
        }(
            abi.encodeWithSelector(
                IReputationLogic.registerToOracle.selector,
                address(this),
                address(pool.reputationLogic)
            )
        );

        if (!success) {
            if (data.length > 0) {
                assembly {
                    let returndata_size := mload(data)
                    revert(add(32, data), returndata_size)
                }
            } else {
                revert("Failed to register hook with reputation oracle");
            }
        }
    }

    /**
     * @notice Unregisters a pool from the oracle
     * @param key The PoolKey of the pool
     */
    function unregisterFromOracle(
        PoolKey calldata key
    ) public override onlyPoolAdmin(key) {
        PoolId poolId = key.toId();
        Pools storage pool = pools[poolId];

        pool.reputationOracle.unregisterPool(address(pool.reputationLogic));

        emit OracleUnregistered(msg.sender, poolId);
    }

    /**
     * @notice Withdraws collateral for an admin
     * @param amount The amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) external nonReentrant {
        require(
            adminBalances[msg.sender] >= amount,
            "Insufficient collateral balance"
        );
        adminBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Gets the balance of an admin
     * @param admin The address of the admin
     * @return The balance of the admin
     */
    function getAdminBalance(address admin) external view returns (uint256) {
        return adminBalances[admin];
    }

    /**
     * @notice Sets a custom pool hook for a specific pool
     * @param key The PoolKey of the pool
     * @param hook The address of the custom pool hook
     */
    function setCustomPoolHook(
        PoolKey calldata key,
        ICustomPoolHook hook
    ) external onlyPoolAdmin(key) {
        require(
            address(hook).supportsInterface(type(ICustomPoolHook).interfaceId),
            "Hook must implement ICustomPoolHook"
        );
        PoolId poolId = key.toId();
        customPoolHooks[poolId] = hook;
        emit CustomPoolHookSet(poolId, address(hook));
    }
}
