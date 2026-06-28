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

// src/interfaces/IAgentTreasury.sol

/// @title IAgentTreasury — Agent Treasury Interface v1.1
/// @author Arcis Protocol (arcis.money)
/// @notice The ATI standard. Three core functions. Two discovery views.
/// @dev Compliant vaults MUST implement deposit, withdraw, balance, asset, totalAssets.
///      Designed for autonomous AI agents to manage treasury capital.
///      No UI required. No human approval flows. Pure contract interaction.
///
///      Changelog v1.1:
///      - Added asset() for token discovery (agents need to know what to approve)
///      - Added totalAssets() for vault health assessment
///      - Added maxDeposit() for cap-aware deposits
///      - Added ATI_VERSION constant for interface versioning
///      - Standardized event parameter order: (agent, assets, shares) for both events
///      - Added ERC-165 interface ID: 0x7a5b2d14
interface IAgentTreasury {

    // ── Core Operations ──

    /// @notice Deposit the underlying asset into the vault
    /// @param amount The amount of the underlying asset to deposit
    /// @return shares The number of vault shares minted to the caller
    /// @dev MUST revert if amount is 0 or below minimum
    /// @dev MUST revert if vault deposit cap is reached
    /// @dev Caller MUST have approved the vault to spend `amount` of asset()
    /// @dev MUST emit Deposit(agent, amount, shares)
    function deposit(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraw the underlying asset by redeeming vault shares
    /// @param shares The number of vault shares to redeem
    /// @return amount The amount of the underlying asset returned (principal + yield)
    /// @dev MUST revert if shares exceeds caller balance
    /// @dev MUST revert if vault has insufficient liquidity
    /// @dev MUST emit Withdraw(agent, amount, shares)
    function withdraw(uint256 shares) external returns (uint256 amount);

    /// @notice Query the current value of an agent's position in the underlying asset
    /// @param agent The address of the agent (or any holder)
    /// @return The current value including accrued yield
    /// @dev MUST NOT revert for any valid address
    /// @dev MUST return 0 for addresses with no position
    function balance(address agent) external view returns (uint256);

    // ── Discovery Views ──

    /// @notice The address of the underlying asset token (e.g. USDC)
    /// @dev MUST return a valid ERC-20 address
    /// @dev Agents call this to discover what token to approve before depositing
    function asset() external view returns (address);

    /// @notice Total value of all assets under management
    /// @dev MUST return the total value denominated in the underlying asset
    /// @dev Agents use this to assess vault health and relative position size
    function totalAssets() external view returns (uint256);

    /// @notice Maximum amount that can be deposited by a given agent
    /// @param agent The address that would deposit
    /// @return The maximum deposit amount (0 if vault is full or paused)
    /// @dev Agents call this before depositing to avoid reverts
    function maxDeposit(address agent) external view returns (uint256);

    // ── Events ──
    // Parameter order standardized: (agent, assets, shares) for both events

    /// @notice Emitted when an agent deposits the underlying asset
    event Deposit(address indexed agent, uint256 amount, uint256 shares);

    /// @notice Emitted when an agent withdraws the underlying asset
    event Withdraw(address indexed agent, uint256 amount, uint256 shares);
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

// src/core/ArcisVault.sol

/// @title ArcisVault
/// @author Arcis Protocol (arcis.money)
/// @notice ERC-4626 yield-bearing vault for autonomous AI agents
/// @dev Accepts USDC, mints raUSDC share tokens, routes capital to yield strategies.
///      Implements the ATI standard (deposit/withdraw/balance) plus ERC-20 for shares.
///
///      Security:
///      - Virtual shares/assets offset to prevent ERC-4626 inflation attacks
///      - Reentrancy guard on all state-changing functions
///      - Deposit cap enforced per-vault
///      - Pausable by owner (multisig)
///      - Management fee accrual on harvest
///
///      Share price: exchangeRate = totalAssets / totalShares
///      As yield accrues, each raUSDC becomes worth more USDC.
contract ArcisVault is IAgentTreasury {
    using MathLib for uint256;

    // ══════════════════════════════════════════════════════════════
    //                          CONSTANTS
    // ══════════════════════════════════════════════════════════════

    /// @notice USDC token address (set in constructor)
    address public immutable USDC;

    /// @notice Minimum deposit amount (1 USDC)
    uint256 public constant MIN_DEPOSIT = 1e6;

    /// @notice Maximum management fee: 5% (500 bps)
    uint256 public constant MAX_FEE_BPS = 500;

    /// @notice Fee denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ══════════════════════════════════════════════════════════════
    //                        ERC-20 STORAGE
    // ══════════════════════════════════════════════════════════════

    string public constant name = "Arcis USDC";
    string public constant symbol = "raUSDC";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Timestamp of last deposit per agent (for withdrawal fee ramp)
    mapping(address => uint256) public lastDepositTime;

    /// @notice Early withdrawal fee in bps (applied within WITHDRAWAL_FEE_WINDOW)
    uint256 public constant WITHDRAWAL_FEE_BPS = 10; // 0.1%

    /// @notice Window after deposit during which withdrawal fee applies
    uint256 public constant WITHDRAWAL_FEE_WINDOW = 24 hours;

    // ══════════════════════════════════════════════════════════════
    //                       VAULT STORAGE
    // ══════════════════════════════════════════════════════════════

    /// @notice Total USDC held in vault reserve (not deployed to strategies)
    uint256 public reserveBalance;

    /// @notice Total USDC value across all strategies (updated on harvest)
    uint256 public deployedBalance;

    /// @notice Maximum total deposits (in USDC)
    uint256 public depositCap;

    /// @notice Maximum deposit per agent (0 = no per-agent limit)
    uint256 public perAgentCap;

    /// @notice Management fee in basis points
    uint256 public feeBps;

    /// @notice Fee recipient address
    address public feeRecipient;

    /// @notice Owner (multisig)
    address public owner;

    /// @notice Pending owner for two-step transfer
    address public pendingOwner;

    /// @notice Whether deposits/withdrawals are paused
    bool public paused;

    /// @notice Reentrancy lock
    uint256 private _locked = 1;

    // ══════════════════════════════════════════════════════════════
    //                     STRATEGY STORAGE
    // ══════════════════════════════════════════════════════════════

    /// @notice Registered strategy adapters
    IStrategyAdapter[] public strategies;

    /// @notice Allocation weight per strategy (in bps, must sum to 10000)
    uint256[] public allocationWeights;

    /// @notice Whether an address is a registered strategy
    mapping(address => bool) public isStrategy;

    /// @notice Target reserve ratio in bps (portion kept liquid in vault)
    uint256 public immutable reserveRatioBps;

    /// @notice Strategy addition timelock (24 hours)
    uint256 public constant STRATEGY_TIMELOCK = 24 hours;

    /// @notice Pending strategy addition
    struct PendingStrategy {
        address strategy;
        uint256 weight;
        uint256 executeAfter;
    }
    PendingStrategy public pendingStrategy;

    event StrategyQueued(address indexed strategy, uint256 weight, uint256 executeAfter);
    event StrategyCancelled(address indexed strategy);

    // ══════════════════════════════════════════════════════════════
    //                         EVENTS
    // ══════════════════════════════════════════════════════════════

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event StrategyAdded(address indexed strategy, uint256 weight);
    event StrategyRemoved(address indexed strategy);
    event AllocationUpdated(uint256[] weights);
    event Harvested(uint256 totalYield, uint256 fee);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event OwnershipTransferStarted(address indexed current, address indexed pending);
    event OwnershipTransferred(address indexed previous, address indexed current);
    event EmergencyWithdraw(address indexed strategy, uint256 recovered);

    // ══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ══════════════════════════════════════════════════════════════

    modifier nonReentrant() {
        if (_locked != 1) revert ErrorLib.Unauthorized(msg.sender);
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier whenNotPaused() {
        if (paused) revert ErrorLib.VaultPaused();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    // ══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════

    /// @param _usdc USDC token address
    /// @param _depositCap Initial deposit cap in USDC (6 decimals)
    /// @param _feeBps Management fee in basis points
    /// @param _feeRecipient Address to receive management fees
    /// @param _reserveRatioBps Percentage of deposits kept liquid (e.g. 1000 = 10%)
    constructor(
        address _usdc,
        uint256 _depositCap,
        uint256 _feeBps,
        address _feeRecipient,
        uint256 _reserveRatioBps
    ) {
        if (_usdc == address(0)) revert ErrorLib.ZeroAddress();
        if (_feeRecipient == address(0)) revert ErrorLib.ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert ErrorLib.InvalidAllocation();
        if (_reserveRatioBps > BPS_DENOMINATOR) revert ErrorLib.InvalidAllocation();

        USDC = _usdc;
        depositCap = _depositCap;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;
        reserveRatioBps = _reserveRatioBps;
        owner = msg.sender;
    }

    // ══════════════════════════════════════════════════════════════
    //                  ATI INTERFACE (3 functions)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IAgentTreasury
    function deposit(uint256 amount) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert ErrorLib.ZeroAmount();
        if (amount < MIN_DEPOSIT) revert ErrorLib.DepositTooSmall(amount, MIN_DEPOSIT);

        uint256 totalBefore = totalAssets();
        if (totalBefore + amount > depositCap) {
            revert ErrorLib.VaultCapExceeded(amount, depositCap - totalBefore);
        }

        // Per-agent cap check
        if (perAgentCap > 0) {
            uint256 currentValue = balanceOf[msg.sender] > 0 ? _convertToAssets(balanceOf[msg.sender], false) : 0;
            if (currentValue + amount > perAgentCap) {
                revert ErrorLib.VaultCapExceeded(amount, perAgentCap - currentValue);
            }
        }

        // Calculate shares BEFORE transfer (prevents manipulation)
        shares = _convertToShares(amount, false);
        if (shares == 0) revert ErrorLib.ZeroShares();

        // Transfer USDC from agent to vault
        _safeTransferFrom(USDC, msg.sender, address(this), amount);

        // Update reserve balance
        reserveBalance += amount;

        // Record deposit time for withdrawal fee ramp
        lastDepositTime[msg.sender] = block.timestamp;

        // Mint raUSDC shares
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount, shares);
    }

    /// @inheritdoc IAgentTreasury
    function withdraw(uint256 shares) external nonReentrant whenNotPaused returns (uint256 amount) {
        if (shares == 0) revert ErrorLib.ZeroShares();
        if (balanceOf[msg.sender] < shares) {
            revert ErrorLib.InsufficientShares(shares, balanceOf[msg.sender]);
        }

        // Calculate USDC amount BEFORE burning shares
        amount = _convertToAssets(shares, false);
        if (amount == 0) revert ErrorLib.ZeroAmount();

        // Check liquidity — try reserve first, then pull from strategies
        if (amount > reserveBalance) {
            uint256 deficit = amount - reserveBalance;
            uint256 pulled = _pullFromStrategies(deficit);
            if (reserveBalance + pulled < amount) {
                revert ErrorLib.InsufficientLiquidity(amount, reserveBalance + pulled);
            }
        }

        // Burn shares
        _burn(msg.sender, shares);

        // Apply early withdrawal fee if within 24h of deposit
        uint256 fee = 0;
        if (block.timestamp < lastDepositTime[msg.sender] + WITHDRAWAL_FEE_WINDOW) {
            fee = MathLib.bps(amount, WITHDRAWAL_FEE_BPS);
            if (fee > 0 && feeRecipient != address(0)) {
                _safeTransfer(USDC, feeRecipient, fee);
            }
            amount -= fee;
        }

        // Update reserve (full amount including fee leaves the vault)
        reserveBalance -= (amount + fee);

        // Transfer USDC to agent
        _safeTransfer(USDC, msg.sender, amount);

        emit Withdraw(msg.sender, amount, shares);
    }

    /// @notice Emergency withdrawal — works even when vault is paused
    /// @dev Only withdraws from reserve (no strategy pulls). Users can exit
    ///      after owner calls emergencyWithdrawStrategy() to refill reserve.
    /// @param shares raUSDC shares to redeem
    /// @return amount USDC returned to caller
    function emergencyWithdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        if (shares == 0) revert ErrorLib.ZeroShares();
        if (balanceOf[msg.sender] < shares) {
            revert ErrorLib.InsufficientShares(shares, balanceOf[msg.sender]);
        }

        amount = _convertToAssets(shares, false);
        if (amount == 0) revert ErrorLib.ZeroAmount();

        // Emergency: reserve only, no strategy pulls
        if (amount > reserveBalance) {
            revert ErrorLib.InsufficientLiquidity(amount, reserveBalance);
        }

        _burn(msg.sender, shares);
        reserveBalance -= amount;
        _safeTransfer(USDC, msg.sender, amount);

        emit Withdraw(msg.sender, amount, shares);
    }

    /// @inheritdoc IAgentTreasury
    function balance(address agent) external view returns (uint256) {
        if (balanceOf[agent] == 0) return 0;
        return _convertToAssets(balanceOf[agent], false);
    }

    // ══════════════════════════════════════════════════════════════
    //                      VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Total USDC value managed by the vault
    function totalAssets() public view returns (uint256) {
        return reserveBalance + deployedBalance;
    }

    /// @notice The underlying asset token address (ATI v1.1)
    /// @dev Agents call this to discover what token to approve before depositing
    function asset() external view returns (address) {
        return USDC;
    }

    /// @notice Maximum amount that can be deposited by a given agent (ATI v1.1)
    /// @dev Returns 0 if vault is paused or at capacity
    function maxDeposit(address agent) external view returns (uint256) {
        if (paused) return 0;
        uint256 total = totalAssets();
        if (total >= depositCap) return 0;
        uint256 globalRemaining = depositCap - total;

        if (perAgentCap == 0) return globalRemaining;

        uint256 currentValue = balanceOf[agent] > 0 ? _convertToAssets(balanceOf[agent], false) : 0;
        if (currentValue >= perAgentCap) return 0;
        uint256 agentRemaining = perAgentCap - currentValue;

        return MathLib.min(globalRemaining, agentRemaining);
    }

    /// @notice Current exchange rate: USDC per raUSDC share (in WAD)
    function exchangeRate() external view returns (uint256) {
        if (totalSupply == 0) return 1e18;
        return MathLib.mulDiv(totalAssets(), 1e18, totalSupply);
    }

    /// @notice Preview how many shares a deposit would mint
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, false);
    }

    /// @notice Preview how much USDC a withdrawal would return
    function previewWithdraw(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, false);
    }

    // ══════════════════════════════════════════════════════════════
    //                     ERC-4626 COMPATIBILITY
    // ══════════════════════════════════════════════════════════════

    /// @notice Convert asset amount to share amount (no rounding direction preference)
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _convertToShares(assets, false);
    }

    /// @notice Convert share amount to asset amount
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Preview redeem (alias for previewWithdraw — same calculation)
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, false);
    }

    /// @notice Preview mint — how many assets needed to mint exact shares
    function previewMint(uint256 shares) external view returns (uint256) {
        return _convertToAssets(shares, true); // Round up for minting
    }

    /// @notice Maximum assets an owner can withdraw
    function maxWithdraw(address account) external view returns (uint256) {
        if (paused) return 0;
        if (balanceOf[account] == 0) return 0;
        return _convertToAssets(balanceOf[account], false);
    }

    /// @notice Maximum shares an owner can redeem
    function maxRedeem(address account) external view returns (uint256) {
        if (paused) return 0;
        return balanceOf[account];
    }

    /// @notice Maximum shares that can be minted (based on remaining deposit cap)
    function maxMint(address) external view returns (uint256) {
        if (paused) return 0;
        uint256 total = totalAssets();
        if (total >= depositCap) return 0;
        return _convertToShares(depositCap - total, false);
    }

    /// @notice Remaining capacity before deposit cap
    function remainingCapacity() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total >= depositCap) return 0;
        return depositCap - total;
    }

    /// @notice Number of registered strategies
    function strategyCount() external view returns (uint256) {
        return strategies.length;
    }

    // ══════════════════════════════════════════════════════════════
    //                    STRATEGY MANAGEMENT
    // ══════════════════════════════════════════════════════════════

    /// @notice Add a new yield strategy
    /// @param strategy Address of the strategy adapter
    /// @param weight Allocation weight in bps
    function queueStrategy(address strategy, uint256 weight) external onlyOwner {
        if (strategy == address(0)) revert ErrorLib.ZeroAddress();
        if (isStrategy[strategy]) revert ErrorLib.StrategyAlreadyRegistered(strategy);

        uint256 executeAfter = block.timestamp + STRATEGY_TIMELOCK;
        pendingStrategy = PendingStrategy(strategy, weight, executeAfter);

        emit StrategyQueued(strategy, weight, executeAfter);
    }

    function executeStrategy() external onlyOwner {
        PendingStrategy memory ps = pendingStrategy;
        if (ps.strategy == address(0)) revert ErrorLib.ZeroAddress();
        if (block.timestamp < ps.executeAfter) revert ErrorLib.TimelockNotExpired(ps.executeAfter);
        if (isStrategy[ps.strategy]) revert ErrorLib.StrategyAlreadyRegistered(ps.strategy);

        strategies.push(IStrategyAdapter(ps.strategy));
        allocationWeights.push(ps.weight);
        isStrategy[ps.strategy] = true;

        _safeApprove(USDC, ps.strategy, type(uint256).max);

        delete pendingStrategy;
        emit StrategyAdded(ps.strategy, ps.weight);
    }

    function cancelPendingStrategy() external onlyOwner {
        address s = pendingStrategy.strategy;
        delete pendingStrategy;
        emit StrategyCancelled(s);
    }

    /// @notice Update allocation weights for all strategies
    /// @param weights New weights array (must sum to 10000 - reserveRatioBps)
    function updateAllocations(uint256[] calldata weights) external onlyOwner {
        if (weights.length != strategies.length) revert ErrorLib.InvalidAllocation();

        uint256 sum = 0;
        for (uint256 i; i < weights.length; ++i) {
            sum += weights[i];
        }

        // Weights + reserve ratio must equal 10000
        if (sum + reserveRatioBps != BPS_DENOMINATOR) {
            revert ErrorLib.AllocationSumMismatch(sum + reserveRatioBps);
        }

        allocationWeights = weights;
        emit AllocationUpdated(weights);
    }

    /// @notice Deploy reserve capital to strategies according to allocation weights
    function rebalance() external onlyOwner nonReentrant {
        uint256 total = totalAssets();
        if (total == 0) return;

        uint256 targetReserve = MathLib.bps(total, reserveRatioBps);

        // Deploy excess reserve to strategies
        if (reserveBalance > targetReserve) {
            uint256 toDeploy = reserveBalance - targetReserve;
            _deployToStrategies(toDeploy);
        }
    }

    /// @notice Harvest yield from all strategies, take fee, update deployed balance
    function harvest() external nonReentrant returns (uint256 totalYield) {
        uint256 totalValueBefore = deployedBalance;
        uint256 stratLen = strategies.length;

        // Harvest each strategy
        for (uint256 i; i < stratLen; ++i) {
            if (strategies[i].isActive()) {
                strategies[i].harvest();
            }
        }

        // Recalculate total deployed value
        uint256 newDeployed = 0;
        for (uint256 i; i < stratLen; ++i) {
            newDeployed += strategies[i].totalValue();
        }

        if (newDeployed > totalValueBefore) {
            totalYield = newDeployed - totalValueBefore;

            // Take management fee on yield
            uint256 fee = MathLib.bps(totalYield, feeBps);
            if (fee > 0) {
                // Mint fee shares to feeRecipient
                uint256 feeShares = _convertToShares(fee, false);
                if (feeShares > 0) {
                    _mint(feeRecipient, feeShares);
                }
            }
        }

        deployedBalance = newDeployed;
        emit Harvested(totalYield, MathLib.bps(totalYield, feeBps));
    }

    // ══════════════════════════════════════════════════════════════
    //                     ADMIN FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function setDepositCap(uint256 newCap) external onlyOwner {
        emit DepositCapUpdated(depositCap, newCap);
        depositCap = newCap;
    }

    function setPerAgentCap(uint256 newCap) external onlyOwner {
        perAgentCap = newCap;
    }

    function setFeeBps(uint256 newFee) external onlyOwner {
        if (newFee > MAX_FEE_BPS) revert ErrorLib.InvalidAllocation();
        emit FeeUpdated(feeBps, newFee);
        feeBps = newFee;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ErrorLib.ZeroAddress();
        feeRecipient = newRecipient;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Two-step ownership transfer
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ErrorLib.ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert ErrorLib.Unauthorized(msg.sender);
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /// @notice Emergency: pull all funds from a strategy
    function emergencyWithdrawStrategy(uint256 index) external onlyOwner nonReentrant {
        IStrategyAdapter strategy = strategies[index];
        uint256 recovered = strategy.emergencyWithdraw();
        reserveBalance += recovered;
        deployedBalance -= MathLib.min(strategies[index].totalValue(), deployedBalance);
        emit EmergencyWithdraw(address(strategy), recovered);
    }

    // ══════════════════════════════════════════════════════════════
    //                     ERC-20 FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function transfer(address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ErrorLib.ZeroAddress();
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ErrorLib.ZeroAddress();
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ══════════════════════════════════════════════════════════════
    //                    INTERNAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function _convertToShares(uint256 assets, bool roundUp) internal view returns (uint256) {
        return MathLib.toShares(assets, totalSupply, totalAssets(), roundUp);
    }

    function _convertToAssets(uint256 shares, bool roundUp) internal view returns (uint256) {
        return MathLib.toAssets(shares, totalSupply, totalAssets(), roundUp);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @dev Deploy capital to strategies according to allocation weights
    function _deployToStrategies(uint256 amount) internal {
        uint256 stratLen = strategies.length;
        for (uint256 i; i < stratLen; ++i) {
            if (!strategies[i].isActive()) continue;

            uint256 portion = MathLib.bps(amount, allocationWeights[i]);
            if (portion == 0) continue;

            // Transfer USDC to strategy and deploy
            _safeTransfer(USDC, address(strategies[i]), portion);
            uint256 deployed = strategies[i].deploy(portion);

            reserveBalance -= portion;
            deployedBalance += deployed;
        }
    }

    /// @dev Pull capital from strategies to cover withdrawal deficit
    function _pullFromStrategies(uint256 deficit) internal returns (uint256 totalPulled) {
        uint256 stratLen = strategies.length;
        for (uint256 i; i < stratLen && totalPulled < deficit; ++i) {
            if (!strategies[i].isActive()) continue;

            uint256 available = strategies[i].availableLiquidity();
            uint256 toPull = MathLib.min(available, deficit - totalPulled);

            if (toPull > 0) {
                uint256 pulled = strategies[i].withdrawFromStrategy(toPull);
                totalPulled += pulled;
                deployedBalance -= MathLib.min(pulled, deployedBalance);
                reserveBalance += pulled;
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //                    SAFE TOKEN HELPERS
    // ══════════════════════════════════════════════════════════════

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.ApprovalFailed();
    }
}

