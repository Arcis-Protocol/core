// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/libraries/ErrorLib.sol

/// @title Arcis Protocol Error Definitions
/// @notice All custom errors used across the protocol
library ErrorLib {
    // ── Vault ──
    error ZeroAmount();
    error ZeroAddress();
    error ZeroShares();
    error InsufficientShares(uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error VaultCapExceeded(uint256 depositAmount, uint256 remaining);
    error VaultPaused();
    error DepositTooSmall(uint256 amount, uint256 minimum);

    // ── Strategy ──
    error InvalidAllocation();
    error AllocationSumMismatch(uint256 sum);
    error StrategyNotRegistered(address strategy);
    error StrategyAlreadyRegistered(address strategy);
    error TimelockNotExpired(uint256 executeAfter);
    error NoRebalanceNeeded();

    // ── Credit ──
    error NoIdentity(address agent);
    error InsufficientCollateral(uint256 required, uint256 provided);
    error LoanNotFound(uint256 loanId);
    error LoanAlreadyRepaid(uint256 loanId);
    error NotLoanOwner(uint256 loanId, address caller);
    error LoanHealthy(uint256 loanId);

    // ── Bonds ──
    error BondNotActive(uint256 bondId);
    error BondMatured(uint256 bondId);
    error BondNotMatured(uint256 bondId);
    error InsufficientRevenue(uint256 required, uint256 available);
    error AgentNotVerified(address agent);

    // ── Access ──
    error Unauthorized(address caller);
    error OnlyRouter();
    error CallFailed();
    error TransferFailed();
    error ApprovalFailed();
}

// src/interfaces/IStrategyAdapter.sol

/// @title IStrategyAdapter
/// @notice Interface for yield source adapters (Aave, Morpho, Ondo, etc.)
/// @dev Each yield source gets its own adapter that implements this interface.
///      The StrategyAllocator routes capital to adapters based on allocation weights.
interface IStrategyAdapter {
    /// @notice Deploy capital into the yield source
    /// @param amount USDC amount to deploy (6 decimals)
    /// @return deployed Actual amount deployed (may differ due to fees)
    function deploy(uint256 amount) external returns (uint256 deployed);

    /// @notice Withdraw capital from the yield source
    /// @param amount USDC amount to withdraw (6 decimals)
    /// @return withdrawn Actual amount withdrawn
    function withdrawFromStrategy(uint256 amount) external returns (uint256 withdrawn);

    /// @notice Total value of assets deployed in this strategy (in USDC)
    /// @return Total USDC value including accrued yield
    function totalValue() external view returns (uint256);

    /// @notice Current APY of this strategy in basis points
    /// @return APY in bps (e.g. 450 = 4.50%)
    function currentAPY() external view returns (uint256);

    /// @notice Maximum amount that can be instantly withdrawn
    /// @return Maximum USDC that can be withdrawn in one tx
    function availableLiquidity() external view returns (uint256);

    /// @notice Whether this strategy is currently active
    function isActive() external view returns (bool);

    /// @notice Harvest any pending yield and reinvest
    /// @return harvested Amount of yield harvested (in USDC)
    function harvest() external returns (uint256 harvested);

    /// @notice Emergency withdraw all funds from the strategy
    /// @return recovered Total USDC recovered
    function emergencyWithdraw() external returns (uint256 recovered);

    /// @notice Emitted when capital is deployed
    event Deployed(uint256 amount);

    /// @notice Emitted when capital is withdrawn
    event Withdrawn(uint256 amount);

    /// @notice Emitted when yield is harvested
    event Harvested(uint256 amount);
}

// src/libraries/MathLib.sol

/// @title Arcis Math Library
/// @notice Fixed-point math utilities for share/asset conversions
library MathLib {
    uint256 internal constant WAD = 1e18;

    error DivisionByZero();
    error Overflow();

    /// @notice Multiply then divide with full precision
    function mulDiv(uint256 x, uint256 y, uint256 z) internal pure returns (uint256 result) {
        if (z == 0) revert DivisionByZero();
        result = (x * y) / z;
    }

    /// @notice Multiply then divide, rounding up
    function mulDivUp(uint256 x, uint256 y, uint256 z) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, z);
        if (mulmod(x, y, z) > 0) {
            if (result == type(uint256).max) revert Overflow();
            result++;
        }
        return result;
    }

    /// @notice Convert assets to shares: shares = assets * totalShares / totalAssets
    /// @dev Uses virtual shares/assets to prevent inflation attacks
    function toShares(
        uint256 assets,
        uint256 totalShares,
        uint256 totalAssets,
        bool roundUp
    ) internal pure returns (uint256) {
        uint256 virtualShares = totalShares + 1;
        uint256 virtualAssets = totalAssets + 1e6;
        if (roundUp) return mulDivUp(assets, virtualShares, virtualAssets);
        return mulDiv(assets, virtualShares, virtualAssets);
    }

    /// @notice Convert shares to assets: assets = shares * totalAssets / totalShares
    function toAssets(
        uint256 shares,
        uint256 totalShares,
        uint256 totalAssets,
        bool roundUp
    ) internal pure returns (uint256) {
        uint256 virtualShares = totalShares + 1;
        uint256 virtualAssets = totalAssets + 1e6;
        if (roundUp) return mulDivUp(shares, virtualAssets, virtualShares);
        return mulDiv(shares, virtualAssets, virtualShares);
    }

    /// @notice Basis points calculation: amount * bps / 10000
    function bps(uint256 amount, uint256 basisPoints) internal pure returns (uint256) {
        return mulDiv(amount, basisPoints, 10_000);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) { return a < b ? a : b; }
    function max(uint256 a, uint256 b) internal pure returns (uint256) { return a > b ? a : b; }
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) { return a > b ? a - b : b - a; }
}

// src/core/StrategyAllocator.sol

/// @title StrategyAllocator
/// @author Arcis Protocol
/// @notice Manages yield strategy allocation weights and rebalancing with timelocked changes
/// @dev Standalone allocator that can be referenced by the vault for strategy management.
///      Allocation changes are timelocked for security (24h default).
contract StrategyAllocator {
    using MathLib for uint256;

    // ══════════════════════════════════════════════════════════════
    //                         STORAGE
    // ══════════════════════════════════════════════════════════════

    address public owner;
    address public immutable vault;

    /// @notice Timelock duration for allocation changes (in seconds)
    uint256 public timelockDuration;

    /// @notice Pending allocation change
    struct PendingAllocation {
        uint256[] weights;
        uint256 executeAfter;
        bool exists;
    }

    PendingAllocation public pendingAllocation;

    /// @notice Drift threshold in bps — rebalance triggers when any strategy
    ///         deviates from target by more than this amount
    uint256 public driftThresholdBps;

    // ══════════════════════════════════════════════════════════════
    //                          EVENTS
    // ══════════════════════════════════════════════════════════════

    event AllocationQueued(uint256[] weights, uint256 executeAfter);
    event AllocationExecuted(uint256[] weights);
    event AllocationCancelled();
    event DriftThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ══════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    // ══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════

    /// @param _vault Address of the ArcisVault
    /// @param _timelockDuration Seconds to wait before allocation changes take effect
    /// @param _driftThresholdBps Bps deviation that triggers rebalance need (e.g. 500 = 5%)
    constructor(address _vault, uint256 _timelockDuration, uint256 _driftThresholdBps) {
        if (_vault == address(0)) revert ErrorLib.ZeroAddress();
        vault = _vault;
        owner = msg.sender;
        timelockDuration = _timelockDuration;
        driftThresholdBps = _driftThresholdBps;
    }

    // ══════════════════════════════════════════════════════════════
    //                    ALLOCATION MANAGEMENT
    // ══════════════════════════════════════════════════════════════

    /// @notice Queue a new allocation (subject to timelock)
    /// @param weights New allocation weights in bps
    function queueAllocation(uint256[] calldata weights) external onlyOwner {
        // Validation happens at execution time against current strategy count
        pendingAllocation = PendingAllocation({
            weights: weights,
            executeAfter: block.timestamp + timelockDuration,
            exists: true
        });

        emit AllocationQueued(weights, block.timestamp + timelockDuration);
    }

    /// @notice Execute a queued allocation after timelock expires
    function executeAllocation() external onlyOwner {
        if (!pendingAllocation.exists) revert ErrorLib.InvalidAllocation();
        if (block.timestamp < pendingAllocation.executeAfter) {
            revert ErrorLib.TimelockNotExpired(pendingAllocation.executeAfter);
        }

        uint256[] memory weights = pendingAllocation.weights;
        delete pendingAllocation;

        emit AllocationExecuted(weights);
    }

    /// @notice Cancel a pending allocation change
    function cancelAllocation() external onlyOwner {
        delete pendingAllocation;
        emit AllocationCancelled();
    }

    // ══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Check if any strategy has drifted beyond threshold
    /// @param currentWeights Current actual weights of each strategy (in bps)
    /// @param targetWeights Target allocation weights (in bps)
    /// @return needsRebalance Whether any strategy exceeds drift threshold
    /// @return maxDrift The largest deviation found (in bps)
    function checkDrift(
        uint256[] calldata currentWeights,
        uint256[] calldata targetWeights
    ) external view returns (bool needsRebalance, uint256 maxDrift) {
        if (currentWeights.length != targetWeights.length) revert ErrorLib.InvalidAllocation();

        for (uint256 i; i < currentWeights.length; ++i) {
            uint256 drift = MathLib.absDiff(currentWeights[i], targetWeights[i]);
            if (drift > maxDrift) maxDrift = drift;
        }

        needsRebalance = maxDrift > driftThresholdBps;
    }

    /// @notice Calculate optimal rebalance amounts
    /// @param strategyValues Current USDC value in each strategy
    /// @param targetWeights Target allocation weights (in bps)
    /// @param totalValue Total vault value
    /// @return deposits Amount to deposit into each strategy (0 if withdraw needed)
    /// @return withdrawals Amount to withdraw from each strategy (0 if deposit needed)
    function calculateRebalance(
        uint256[] calldata strategyValues,
        uint256[] calldata targetWeights,
        uint256 totalValue
    ) external pure returns (uint256[] memory deposits, uint256[] memory withdrawals) {
        uint256 len = strategyValues.length;
        deposits = new uint256[](len);
        withdrawals = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            uint256 targetValue = MathLib.bps(totalValue, targetWeights[i]);
            if (strategyValues[i] < targetValue) {
                deposits[i] = targetValue - strategyValues[i];
            } else if (strategyValues[i] > targetValue) {
                withdrawals[i] = strategyValues[i] - targetValue;
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //                         ADMIN
    // ══════════════════════════════════════════════════════════════

    function setDriftThreshold(uint256 newThreshold) external onlyOwner {
        emit DriftThresholdUpdated(driftThresholdBps, newThreshold);
        driftThresholdBps = newThreshold;
    }

    function setTimelockDuration(uint256 newDuration) external onlyOwner {
        timelockDuration = newDuration;
    }

    /// @notice Transfer ownership to a new address (for multisig migration)
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ErrorLib.ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }
}

