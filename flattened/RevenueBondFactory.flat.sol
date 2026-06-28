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

// src/interfaces/IRevenueBond.sol

/// @title IRevenueBond
/// @notice Tokenized claims on agent revenue streams
/// @dev Agents with verified cash flows issue bonds. Human investors buy yield.
interface IRevenueBond {
    enum BondStatus {
        Active,
        Matured,
        Defaulted,
        Cancelled
    }

    struct Bond {
        uint256 id;
        address agent;               // Issuing agent
        address revenueSource;        // Contract generating revenue
        uint256 principal;            // Total capital raised
        uint256 filled;               // Amount purchased so far
        uint256 couponBps;            // Annual yield in bps
        uint256 maturityBlock;        // Block when bond matures
        uint256 issuedBlock;          // Block when bond was issued
        uint256 totalCouponPaid;      // Cumulative coupon distributed
        BondStatus status;
    }

    /// @notice Issue a new revenue bond
    function issueBond(
        address revenueSource,
        uint256 principal,
        uint256 couponBps,
        uint256 durationBlocks
    ) external returns (uint256 bondId);

    /// @notice Purchase bond tokens with USDC
    function purchase(uint256 bondId, uint256 amount) external returns (uint256 tokens);

    /// @notice Claim accrued coupon payments
    function claimCoupon(uint256 bondId) external returns (uint256 payout);

    /// @notice Redeem principal at maturity
    function redeem(uint256 bondId) external returns (uint256 principal);

    /// @notice Service debt from escrowed revenue
    function serviceDebt(uint256 bondId) external;

    event BondIssued(uint256 indexed bondId, address indexed agent, uint256 principal, uint256 couponBps);
    event BondPurchased(uint256 indexed bondId, address indexed buyer, uint256 amount);
    event CouponPaid(uint256 indexed bondId, uint256 totalPaid);
    event BondMatured(uint256 indexed bondId);
    event BondDefaulted(uint256 indexed bondId);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
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

// src/core/RevenueBondFactory.sol

/// @title RevenueBondFactory
/// @author Arcis Protocol
/// @notice Issues tokenized revenue bonds backed by agent cash flows
/// @dev Phase 3. Agents with verified, consistent revenue can issue bonds.
///      Human investors purchase bonds for fixed yield. Revenue flows through
///      an escrow contract that services debt before agent profits.
///
///      Bond lifecycle:
///      1. Agent calls issueBond() with revenue source, principal, coupon, duration
///      2. Investors call purchase() to buy bond tokens with USDC
///      3. Revenue accumulates in RevenueEscrow
///      4. serviceDebt() distributes coupon payments to bondholders
///      5. At maturity, bondholders call redeem() for principal return
contract RevenueBondFactory is IRevenueBond {
    using MathLib for uint256;

    // ══════════════════════════════════════════════════════════════
    //                         STORAGE
    // ══════════════════════════════════════════════════════════════

    address public owner;
    address public immutable usdc;
    address public immutable identityRegistry;

    uint256 public bondCount;
    mapping(uint256 => Bond) public bonds;

    /// @notice Bond token balances: bondId -> holder -> amount
    mapping(uint256 => mapping(address => uint256)) public bondBalances;

    /// @notice Bond token supply per bondId
    mapping(uint256 => uint256) public bondSupply;

    /// @notice Coupon already claimed by holder: bondId -> holder -> amount
    mapping(uint256 => mapping(address => uint256)) public couponClaimed;

    /// @notice Revenue escrow balances per bond
    mapping(uint256 => uint256) public escrowBalances;

    /// @notice Total revenue ever accumulated per bond (for pro-rata calculations)
    mapping(uint256 => uint256) public totalRevenueAccumulated;

    /// @notice Minimum ERC-8004 score to issue bonds
    uint256 public minIssuerScore;

    /// @notice Origination fee in bps
    uint256 public originationFeeBps;

    /// @notice Fee recipient
    address public feeRecipient;

    /// @notice Maximum bond duration in blocks (~6 months at 2s blocks)
    uint256 public maxDurationBlocks;

    bool public paused;
    uint256 private _locked = 1;

    // ══════════════════════════════════════════════════════════════
    //                        MODIFIERS
    // ══════════════════════════════════════════════════════════════

    modifier nonReentrant() {
        if (_locked != 1) revert ErrorLib.Unauthorized(msg.sender);
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ErrorLib.VaultPaused();
        _;
    }

    // ══════════════════════════════════════════════════════════════
    //                       CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════

    constructor(
        address _usdc,
        address _identityRegistry,
        address _feeRecipient,
        uint256 _originationFeeBps,
        uint256 _minIssuerScore,
        uint256 _maxDurationBlocks
    ) {
        if (_usdc == address(0) || _feeRecipient == address(0)) revert ErrorLib.ZeroAddress();

        usdc = _usdc;
        identityRegistry = _identityRegistry;
        feeRecipient = _feeRecipient;
        originationFeeBps = _originationFeeBps;
        minIssuerScore = _minIssuerScore;
        maxDurationBlocks = _maxDurationBlocks;
        owner = msg.sender;
    }

    // ══════════════════════════════════════════════════════════════
    //                     BOND LIFECYCLE
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IRevenueBond
    function issueBond(
        address revenueSource,
        uint256 principal,
        uint256 couponBps,
        uint256 durationBlocks
    ) external nonReentrant whenNotPaused returns (uint256 bondId) {
        if (revenueSource == address(0)) revert ErrorLib.ZeroAddress();
        if (principal == 0) revert ErrorLib.ZeroAmount();
        if (durationBlocks > maxDurationBlocks) revert ErrorLib.InvalidAllocation();

        // Verify agent identity
        if (identityRegistry != address(0)) {
            uint256 score = _getAgentScore(msg.sender);
            if (score < minIssuerScore) revert ErrorLib.AgentNotVerified(msg.sender);
        }

        bondId = ++bondCount;
        bonds[bondId] = Bond({
            id: bondId,
            agent: msg.sender,
            revenueSource: revenueSource,
            principal: principal,
            filled: 0,
            couponBps: couponBps,
            maturityBlock: block.number + durationBlocks,
            issuedBlock: block.number,
            totalCouponPaid: 0,
            status: BondStatus.Active
        });

        emit BondIssued(bondId, msg.sender, principal, couponBps);
    }

    /// @inheritdoc IRevenueBond
    function purchase(uint256 bondId, uint256 amount) external nonReentrant whenNotPaused returns (uint256 tokens) {
        Bond storage bond = bonds[bondId];
        if (bond.status != BondStatus.Active) revert ErrorLib.BondNotActive(bondId);
        if (bond.filled + amount > bond.principal) revert ErrorLib.VaultCapExceeded(amount, bond.principal - bond.filled);

        // Transfer USDC from investor
        _safeTransferFrom(usdc, msg.sender, address(this), amount);

        // Take origination fee
        uint256 fee = MathLib.bps(amount, originationFeeBps);
        if (fee > 0) {
            _safeTransfer(usdc, feeRecipient, fee);
        }

        // Send remaining to agent
        uint256 netToAgent = amount - fee;
        _safeTransfer(usdc, bond.agent, netToAgent);

        // Mint bond tokens to investor (1:1 with USDC)
        tokens = amount;
        bondBalances[bondId][msg.sender] += tokens;
        bondSupply[bondId] += tokens;
        bond.filled += amount;

        emit BondPurchased(bondId, msg.sender, amount);
    }

    /// @inheritdoc IRevenueBond
    function claimCoupon(uint256 bondId) external nonReentrant whenNotPaused returns (uint256 payout) {
        uint256 holderBal = bondBalances[bondId][msg.sender];
        if (holderBal == 0) revert ErrorLib.ZeroAmount();

        // Calculate pro-rata share of ALL revenue ever accumulated
        uint256 totalAccumulated = totalRevenueAccumulated[bondId];
        uint256 alreadyClaimed = couponClaimed[bondId][msg.sender];

        uint256 holderShare = MathLib.mulDiv(totalAccumulated, holderBal, bondSupply[bondId]);

        if (holderShare <= alreadyClaimed) return 0;
        payout = holderShare - alreadyClaimed;

        // Cap at available escrow
        if (payout > escrowBalances[bondId]) {
            payout = escrowBalances[bondId];
        }

        couponClaimed[bondId][msg.sender] += payout;
        escrowBalances[bondId] -= payout;

        _safeTransfer(usdc, msg.sender, payout);
        emit CouponPaid(bondId, payout);
    }

    /// @inheritdoc IRevenueBond
    function redeem(uint256 bondId) external nonReentrant whenNotPaused returns (uint256 principal) {
        Bond storage bond = bonds[bondId];
        if (block.number < bond.maturityBlock) revert ErrorLib.BondNotMatured(bondId);

        uint256 holderBal = bondBalances[bondId][msg.sender];
        if (holderBal == 0) revert ErrorLib.ZeroAmount();

        // Calculate unclaimed coupon
        uint256 coupon = _calculateUnclaimedCoupon(bondId, msg.sender);

        // Burn bond tokens
        principal = holderBal; // 1:1 with USDC
        bondBalances[bondId][msg.sender] = 0;
        bondSupply[bondId] -= holderBal;

        // Total owed = principal + unclaimed coupon
        uint256 totalOwed = principal + coupon;
        uint256 available = escrowBalances[bondId];

        if (available >= totalOwed) {
            // Fully funded — return everything
            escrowBalances[bondId] -= totalOwed;
            couponClaimed[bondId][msg.sender] += coupon;
            _safeTransfer(usdc, msg.sender, totalOwed);
        } else {
            // Underfunded — return what's available
            escrowBalances[bondId] = 0;
            couponClaimed[bondId][msg.sender] += coupon;
            _safeTransfer(usdc, msg.sender, available);
            principal = available > coupon ? available - coupon : 0;
        }

        // Mark matured if fully redeemed
        if (bondSupply[bondId] == 0) {
            bond.status = BondStatus.Matured;
            emit BondMatured(bondId);
        }
    }

    /// @inheritdoc IRevenueBond
    /// @notice Called by the revenue source or keeper to deposit revenue into escrow
    function serviceDebt(uint256 bondId) external nonReentrant whenNotPaused {
        Bond storage bond = bonds[bondId];
        if (bond.status != BondStatus.Active) revert ErrorLib.BondNotActive(bondId);

        // Pull available revenue from the revenue source
        // The revenue source must approve this contract to pull USDC
        uint256 balanceBefore = _usdcBalance();

        // Try to pull revenue
        (bool success,) = bond.revenueSource.call(
            abi.encodeWithSignature("releaseRevenue(uint256)", bondId)
        );

        uint256 received = 0;
        if (success) {
            received = _usdcBalance() - balanceBefore;
        }

        if (received > 0) {
            escrowBalances[bondId] += received;
            totalRevenueAccumulated[bondId] += received;
            bond.totalCouponPaid += received;
        }
    }

    /// @notice Deposit USDC into escrow for principal return (does NOT count as coupon revenue)
    /// @dev Intentionally permissionless: anyone can fund a bond's principal escrow.
    ///      This enables third-party keepers, protocol treasuries, or the agent itself
    ///      to ensure principal is available for redemption at maturity.
    ///      Funds deposited via this function are NOT tracked as revenue and do NOT
    ///      inflate coupon obligations — they are purely for principal return.
    /// @param bondId The bond to fund
    /// @param amount USDC amount to deposit into escrow
    function depositPrincipal(uint256 bondId, uint256 amount) external nonReentrant whenNotPaused {
        Bond storage bond = bonds[bondId];
        if (bond.status != BondStatus.Active) revert ErrorLib.BondNotActive(bondId);

        _safeTransferFrom(usdc, msg.sender, address(this), amount);
        escrowBalances[bondId] += amount;
        // NOTE: intentionally does NOT increment totalRevenueAccumulated
    }

    // ══════════════════════════════════════════════════════════════
    //                     VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Get bond details
    function getBond(uint256 bondId) external view returns (Bond memory) {
        return bonds[bondId];
    }

    /// @notice Get holder's bond token balance
    function holderBalance(uint256 bondId, address holder) external view returns (uint256) {
        return bondBalances[bondId][holder];
    }

    /// @notice Get claimable coupon for a holder
    function claimableCoupon(uint256 bondId, address holder) external view returns (uint256) {
        uint256 holderBal = bondBalances[bondId][holder];
        if (holderBal == 0 || bondSupply[bondId] == 0) return 0;

        uint256 totalAccumulated = totalRevenueAccumulated[bondId];
        uint256 holderShare = MathLib.mulDiv(totalAccumulated, holderBal, bondSupply[bondId]);
        uint256 claimed = couponClaimed[bondId][holder];

        if (holderShare <= claimed) return 0;
        uint256 unclaimed = holderShare - claimed;
        uint256 available = escrowBalances[bondId];
        return unclaimed > available ? available : unclaimed;
    }

    // ══════════════════════════════════════════════════════════════
    //                         ADMIN
    // ══════════════════════════════════════════════════════════════

    /// @notice Mark a bond as defaulted (governance action)
    function markDefault(uint256 bondId) external onlyOwner {
        Bond storage bond = bonds[bondId];
        bond.status = BondStatus.Defaulted;
        emit BondDefaulted(bondId);
    }

    function setMinIssuerScore(uint256 score) external onlyOwner {
        minIssuerScore = score;
    }

    function setOriginationFee(uint256 feeBps) external onlyOwner {
        originationFeeBps = feeBps;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer ownership to a new address (for multisig migration)
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ErrorLib.ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    // ══════════════════════════════════════════════════════════════
    //                    INTERNAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function _calculateUnclaimedCoupon(uint256 bondId, address holder) internal view returns (uint256 payout) {
        uint256 holderBal = bondBalances[bondId][holder];
        if (holderBal == 0 || bondSupply[bondId] == 0) return 0;

        uint256 totalAccumulated = totalRevenueAccumulated[bondId];
        uint256 holderShare = MathLib.mulDiv(totalAccumulated, holderBal, bondSupply[bondId]);
        uint256 claimed = couponClaimed[bondId][holder];

        if (holderShare > claimed) {
            payout = holderShare - claimed;
            // Cap at escrow
            if (payout > escrowBalances[bondId]) {
                payout = escrowBalances[bondId];
            }
        }
    }

    function _getAgentScore(address agent) internal view returns (uint256) {
        (bool success, bytes memory data) = identityRegistry.staticcall(
            abi.encodeWithSignature("getScore(address)", agent)
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    function _usdcBalance() internal view returns (uint256) {
        (bool success, bytes memory data) = usdc.staticcall(
            abi.encodeWithSelector(0x70a08231, address(this))
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

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
}

