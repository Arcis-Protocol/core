// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRevenueBond} from "../interfaces/IRevenueBond.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ErrorLib} from "../libraries/ErrorLib.sol";

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
    ) external nonReentrant returns (uint256 bondId) {
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
    function purchase(uint256 bondId, uint256 amount) external nonReentrant returns (uint256 tokens) {
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
    function claimCoupon(uint256 bondId) external nonReentrant returns (uint256 payout) {
        // Bond lookup not needed — balances tracked separately
        uint256 holderBal = bondBalances[bondId][msg.sender];
        if (holderBal == 0) revert ErrorLib.ZeroAmount();

        // Calculate pro-rata share of available coupon
        uint256 totalAvailable = escrowBalances[bondId];
        uint256 alreadyClaimed = couponClaimed[bondId][msg.sender];

        // Holder's share of total coupon = (holderBalance / bondSupply) * totalAvailable
        uint256 holderShare = MathLib.mulDiv(totalAvailable, holderBal, bondSupply[bondId]);

        if (holderShare <= alreadyClaimed) return 0;
        payout = holderShare - alreadyClaimed;

        couponClaimed[bondId][msg.sender] += payout;
        escrowBalances[bondId] -= payout;

        _safeTransfer(usdc, msg.sender, payout);
        emit CouponPaid(bondId, payout);
    }

    /// @inheritdoc IRevenueBond
    function redeem(uint256 bondId) external nonReentrant returns (uint256 principal) {
        Bond storage bond = bonds[bondId];
        if (block.number < bond.maturityBlock) revert ErrorLib.BondNotMatured(bondId);

        uint256 holderBal = bondBalances[bondId][msg.sender];
        if (holderBal == 0) revert ErrorLib.ZeroAmount();

        // Claim any remaining coupon first
        uint256 coupon = _claimRemainingCoupon(bondId, msg.sender);

        // Return principal pro-rata
        principal = holderBal; // 1:1 with USDC
        bondBalances[bondId][msg.sender] = 0;
        bondSupply[bondId] -= holderBal;

        // Check if escrow has enough for principal return
        if (escrowBalances[bondId] >= principal) {
            escrowBalances[bondId] -= principal;
            _safeTransfer(usdc, msg.sender, principal + coupon);
        } else {
            // Partial return — bond may be in default territory
            uint256 available = escrowBalances[bondId];
            escrowBalances[bondId] = 0;
            _safeTransfer(usdc, msg.sender, available + coupon);
            principal = available;
        }

        // Mark matured if fully redeemed
        if (bondSupply[bondId] == 0) {
            bond.status = BondStatus.Matured;
            emit BondMatured(bondId);
        }
    }

    /// @inheritdoc IRevenueBond
    /// @notice Called by the revenue source or keeper to deposit revenue into escrow
    function serviceDebt(uint256 bondId) external nonReentrant {
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
            bond.totalCouponPaid += received;
        }
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

        uint256 totalAvailable = escrowBalances[bondId];
        uint256 holderShare = MathLib.mulDiv(totalAvailable, holderBal, bondSupply[bondId]);
        uint256 claimed = couponClaimed[bondId][holder];

        return holderShare > claimed ? holderShare - claimed : 0;
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

    // ══════════════════════════════════════════════════════════════
    //                    INTERNAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function _claimRemainingCoupon(uint256 bondId, address holder) internal returns (uint256 payout) {
        uint256 holderBal = bondBalances[bondId][holder];
        if (holderBal == 0 || bondSupply[bondId] == 0) return 0;

        uint256 totalAvailable = escrowBalances[bondId];
        uint256 holderShare = MathLib.mulDiv(totalAvailable, holderBal, bondSupply[bondId]);
        uint256 claimed = couponClaimed[bondId][holder];

        if (holderShare > claimed) {
            payout = holderShare - claimed;
            couponClaimed[bondId][holder] += payout;
            escrowBalances[bondId] -= payout;
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
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
