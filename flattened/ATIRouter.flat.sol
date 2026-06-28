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

// src/interfaces/IAgentCredit.sol

/// @title IAgentCredit
/// @notice Identity-aware lending for autonomous agents
/// @dev Uses ERC-8004 reputation scores to adjust collateral requirements
interface IAgentCredit {
    struct Loan {
        uint256 id;
        address agent;
        uint256 borrowedAmount;      // USDC borrowed
        uint256 collateralShares;    // raUSDC locked
        uint256 interestRateBps;     // Annual rate in bps
        uint256 accruedInterest;     // Accumulated interest
        uint256 startBlock;          // Block when loan was created
        uint256 lastAccrualBlock;    // Last interest accrual
        bool repaid;
    }

    /// @notice Borrow USDC against raUSDC collateral
    /// @param borrowAmount USDC to borrow
    /// @param collateralShares raUSDC shares to lock as collateral
    /// @return loanId Unique identifier for the loan
    function borrow(uint256 borrowAmount, uint256 collateralShares) external returns (uint256 loanId);

    /// @notice Repay a loan and unlock collateral
    /// @param loanId The loan to repay
    function repay(uint256 loanId) external;

    /// @notice Liquidate an undercollateralized loan
    /// @param loanId The loan to liquidate
    function liquidate(uint256 loanId) external;

    /// @notice Get the required collateral ratio for an agent
    /// @param agent Address with optional ERC-8004 identity
    /// @return ratio Collateral ratio in bps (e.g. 15000 = 150%)
    function getCollateralRatio(address agent) external view returns (uint256 ratio);

    /// @notice Check if a loan is healthy (above liquidation threshold)
    /// @param loanId The loan to check
    /// @return healthy Whether the loan is above liquidation threshold
    /// @return healthFactor Current health factor in WAD (1e18 = 1.0)
    function isHealthy(uint256 loanId) external view returns (bool healthy, uint256 healthFactor);

    event LoanCreated(uint256 indexed loanId, address indexed agent, uint256 borrowed, uint256 collateral);
    event LoanRepaid(uint256 indexed loanId, address indexed agent, uint256 totalRepaid);
    event LoanLiquidated(uint256 indexed loanId, address indexed agent, address indexed liquidator);
    event PoolFunded(address indexed funder, uint256 amount);
    event CollateralRatiosUpdated(uint256[5] ratios);
    event RateDiscountsUpdated(uint256[5] discounts);
    event IdentityRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event BaseRateUpdated(uint256 oldRate, uint256 newRate);
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

// src/periphery/ATIRouter.sol

/// @title ATIRouter
/// @author Arcis Protocol
/// @notice Single-call entry point for all agent interactions with Arcis
/// @dev Agents can interact with the vault directly via the ATI interface,
///      but the router provides convenience methods for multi-step operations:
///      - depositAndBorrow: deposit USDC, then borrow against the position
///      - repayAndWithdraw: repay a loan, then withdraw collateral
///      - depositMax: deposit all USDC balance
///      - withdrawMax: withdraw entire position
///
///      The router never holds funds. All operations are atomic.
contract ATIRouter {
    // ══════════════════════════════════════════════════════════════
    //                         STORAGE
    // ══════════════════════════════════════════════════════════════

    address public immutable vault;
    address public immutable credit;
    address public immutable usdc;

    // ══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════

    /// @param _vault ArcisVault address
    /// @param _credit AgentCredit address (address(0) if credit module not yet deployed)
    /// @param _usdc USDC token address
    constructor(address _vault, address _credit, address _usdc) {
        if (_vault == address(0) || _usdc == address(0)) revert ErrorLib.ZeroAddress();
        vault = _vault;
        credit = _credit;
        usdc = _usdc;

        // Approve vault to spend router's USDC (for forwarding deposits)
        _safeApprove(_usdc, _vault, type(uint256).max);

        // Approve credit module to spend router's raUSDC (for forwarding collateral)
        if (_credit != address(0)) {
            _safeApprove(_vault, _credit, type(uint256).max);
        }
    }

    // ══════════════════════════════════════════════════════════════
    //                    VAULT OPERATIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Deposit USDC into the vault (convenience wrapper)
    /// @param amount USDC amount to deposit
    /// @return shares raUSDC shares minted
    function deposit(uint256 amount) external returns (uint256 shares) {
        _safeTransferFrom(usdc, msg.sender, address(this), amount);
        shares = IAgentTreasury(vault).deposit(amount);
        // Transfer shares to the agent
        _safeTransfer(vault, msg.sender, shares);
    }

    /// @notice Withdraw USDC from the vault (convenience wrapper)
    /// @param shares raUSDC shares to redeem
    /// @return amount USDC returned
    function withdraw(uint256 shares) external returns (uint256 amount) {
        _safeTransferFrom(vault, msg.sender, address(this), shares);
        amount = IAgentTreasury(vault).withdraw(shares);
        _safeTransfer(usdc, msg.sender, amount);
    }

    /// @notice Withdraw entire position
    /// @return amount Total USDC returned
    function withdrawMax() external returns (uint256 amount) {
        // Get agent's full share balance
        (bool success, bytes memory data) = vault.staticcall(
            abi.encodeWithSelector(0x70a08231, msg.sender) // balanceOf
        );
        if (!success) revert ErrorLib.CallFailed();
        uint256 shares = abi.decode(data, (uint256));
        if (shares == 0) return 0;

        _safeTransferFrom(vault, msg.sender, address(this), shares);
        amount = IAgentTreasury(vault).withdraw(shares);
        _safeTransfer(usdc, msg.sender, amount);
    }

    /// @notice Deposit all USDC in agent's wallet
    /// @return shares raUSDC shares minted
    function depositMax() external returns (uint256 shares) {
        (bool success, bytes memory data) = usdc.staticcall(
            abi.encodeWithSelector(0x70a08231, msg.sender)
        );
        if (!success) revert ErrorLib.CallFailed();
        uint256 amount = abi.decode(data, (uint256));
        if (amount == 0) return 0;

        _safeTransferFrom(usdc, msg.sender, address(this), amount);
        shares = IAgentTreasury(vault).deposit(amount);
        _safeTransfer(vault, msg.sender, shares);
    }

    // ══════════════════════════════════════════════════════════════
    //                  COMBINED OPERATIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Deposit USDC, then immediately borrow against the position
    /// @param depositAmount USDC to deposit as collateral
    /// @param borrowAmount USDC to borrow
    /// @return shares raUSDC shares minted
    /// @return loanId ID of the created loan
    function depositAndBorrow(
        uint256 depositAmount,
        uint256 borrowAmount
    ) external returns (uint256 shares, uint256 loanId) {
        if (credit == address(0)) revert ErrorLib.ZeroAddress();

        // Step 1: Deposit USDC -> raUSDC
        _safeTransferFrom(usdc, msg.sender, address(this), depositAmount);
        shares = IAgentTreasury(vault).deposit(depositAmount);

        // Step 2: Use raUSDC as collateral to borrow
        loanId = IAgentCredit(credit).borrow(borrowAmount, shares);

        // Step 3: Forward borrowed USDC to the agent
        // (credit.borrow sends USDC to msg.sender which is this router)
        _safeTransfer(usdc, msg.sender, borrowAmount);
    }

    /// @notice Repay a loan and withdraw the freed collateral
    /// @param loanId Loan to repay
    /// @return amount USDC from withdrawn collateral
    function repayAndWithdraw(uint256 loanId) external returns (uint256 amount) {
        if (credit == address(0)) revert ErrorLib.ZeroAddress();

        // Get loan details to know repayment amount
        (bool success, bytes memory data) = credit.staticcall(
            abi.encodeWithSignature("totalOwed(uint256)", loanId)
        );
        if (!success) revert ErrorLib.CallFailed();
        uint256 owed = abi.decode(data, (uint256));

        // Step 1: Transfer repayment USDC from agent
        _safeTransferFrom(usdc, msg.sender, address(this), owed);
        _safeApprove(usdc, credit, owed);

        // Step 2: Repay loan (collateral returned to this router)
        IAgentCredit(credit).repay(loanId);

        // Step 3: Get returned collateral shares
        (success, data) = vault.staticcall(
            abi.encodeWithSelector(0x70a08231, address(this))
        );
        if (!success) revert ErrorLib.CallFailed();
        uint256 shares = abi.decode(data, (uint256));

        // Step 4: Withdraw collateral as USDC
        if (shares > 0) {
            amount = IAgentTreasury(vault).withdraw(shares);
            _safeTransfer(usdc, msg.sender, amount);
        }
    }

    // ══════════════════════════════════════════════════════════════
    //                     VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Get agent's current position value in USDC
    function position(address agent) external view returns (uint256) {
        return IAgentTreasury(vault).balance(agent);
    }

    /// @notice Preview deposit: how many shares for X USDC
    function previewDeposit(uint256 amount) external view returns (uint256) {
        (bool success, bytes memory data) = vault.staticcall(
            abi.encodeWithSignature("previewDeposit(uint256)", amount)
        );
        if (!success) return 0;
        return abi.decode(data, (uint256));
    }

    /// @notice Preview withdraw: how much USDC for X shares
    function previewWithdraw(uint256 shares) external view returns (uint256) {
        (bool success, bytes memory data) = vault.staticcall(
            abi.encodeWithSignature("previewWithdraw(uint256)", shares)
        );
        if (!success) return 0;
        return abi.decode(data, (uint256));
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
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }
}

