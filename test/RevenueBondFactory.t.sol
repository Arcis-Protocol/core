// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/RevenueBondFactory.sol";
import "../src/interfaces/IRevenueBond.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockIdentityRegistry.sol";

/// @title MockRevenueSource
/// @notice Simulates an agent's revenue-producing contract
contract MockRevenueSource {
    address public usdc;
    address public bondFactory;
    mapping(uint256 => uint256) public revenuePool;

    constructor(address _usdc) {
        usdc = _usdc;
    }

    function setBondFactory(address _factory) external {
        bondFactory = _factory;
    }

    /// @notice Simulate revenue accumulation
    function addRevenue(uint256 bondId, uint256 amount) external {
        revenuePool[bondId] += amount;
    }

    /// @notice Called by BondFactory.serviceDebt()
    function releaseRevenue(uint256 bondId) external returns (uint256) {
        require(msg.sender == bondFactory, "ONLY_FACTORY");
        uint256 available = revenuePool[bondId];
        if (available == 0) return 0;

        revenuePool[bondId] = 0;

        // Transfer USDC to the bond factory
        (bool success,) = usdc.call(
            abi.encodeWithSelector(0xa9059cbb, msg.sender, available)
        );
        require(success, "TRANSFER_FAILED");
        return available;
    }
}

contract RevenueBondFactoryTest is Test {
    RevenueBondFactory public factory;
    MockUSDC public usdc;
    MockIdentityRegistry public registry;
    MockRevenueSource public revenueSource;

    address public owner = address(this);
    address public agent = address(0xA1);
    address public investor1 = address(0xB1);
    address public investor2 = address(0xB2);
    address public feeRecipient = address(0xFEE);

    uint256 constant PRINCIPAL = 100_000e6;       // 100K USDC
    uint256 constant COUPON_BPS = 800;             // 8% coupon
    uint256 constant DURATION = 1_000_000;         // ~23 days at 2s blocks
    uint256 constant ORIGINATION_FEE = 50;         // 0.5%
    uint256 constant MIN_SCORE = 50;
    uint256 constant MAX_DURATION = 7_776_000;     // ~6 months

    function setUp() public {
        usdc = new MockUSDC();
        registry = new MockIdentityRegistry();
        revenueSource = new MockRevenueSource(address(usdc));

        factory = new RevenueBondFactory(
            address(usdc),
            address(registry),
            feeRecipient,
            ORIGINATION_FEE,
            MIN_SCORE,
            MAX_DURATION
        );

        revenueSource.setBondFactory(address(factory));

        // Give agent a reputation score of 75
        registry.setScore(agent, 75);

        // Mint USDC
        usdc.mint(investor1, 500_000e6);
        usdc.mint(investor2, 500_000e6);
        usdc.mint(address(revenueSource), 1_000_000e6);

        // Approve factory
        vm.prank(investor1);
        usdc.approve(address(factory), type(uint256).max);
        vm.prank(investor2);
        usdc.approve(address(factory), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════
    //  BOND ISSUANCE
    // ═══════════════════════════════════════════════════

    function test_issueBond() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        assertEq(bondId, 1, "First bond should be ID 1");
        assertEq(factory.bondCount(), 1, "Bond count should be 1");

        IRevenueBond.Bond memory bond = factory.getBond(bondId);
        assertEq(bond.agent, agent, "Agent mismatch");
        assertEq(bond.principal, PRINCIPAL, "Principal mismatch");
        assertEq(bond.couponBps, COUPON_BPS, "Coupon mismatch");
        assertEq(bond.filled, 0, "Should start unfilled");
        assertEq(uint8(bond.status), uint8(IRevenueBond.BondStatus.Active), "Should be active");
    }

    function test_issueBond_incrementsId() public {
        vm.startPrank(agent);
        uint256 id1 = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);
        uint256 id2 = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(factory.bondCount(), 2);
    }

    function test_issueBond_revertInsufficientScore() public {
        // Agent with score 30 (below minIssuerScore of 50)
        address lowAgent = address(0xA2);
        registry.setScore(lowAgent, 30);

        vm.prank(lowAgent);
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.AgentNotVerified.selector, lowAgent));
        factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);
    }

    function test_issueBond_revertZeroAddress() public {
        vm.prank(agent);
        vm.expectRevert(ErrorLib.ZeroAddress.selector);
        factory.issueBond(address(0), PRINCIPAL, COUPON_BPS, DURATION);
    }

    function test_issueBond_revertZeroPrincipal() public {
        vm.prank(agent);
        vm.expectRevert(ErrorLib.ZeroAmount.selector);
        factory.issueBond(address(revenueSource), 0, COUPON_BPS, DURATION);
    }

    function test_issueBond_revertExcessDuration() public {
        vm.prank(agent);
        vm.expectRevert(ErrorLib.InvalidAllocation.selector);
        factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, MAX_DURATION + 1);
    }

    // ═══════════════════════════════════════════════════
    //  BOND PURCHASE
    // ═══════════════════════════════════════════════════

    function test_purchase() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        uint256 agentBefore = usdc.balanceOf(agent);
        uint256 feeBefore = usdc.balanceOf(feeRecipient);
        uint256 investorBefore = usdc.balanceOf(investor1);

        vm.prank(investor1);
        uint256 tokens = factory.purchase(bondId, 50_000e6);

        // Investor gets tokens
        assertEq(tokens, 50_000e6, "Tokens should equal purchase amount");
        assertEq(factory.holderBalance(bondId, investor1), 50_000e6, "Holder balance mismatch");

        // Bond fills
        IRevenueBond.Bond memory bond = factory.getBond(bondId);
        assertEq(bond.filled, 50_000e6, "Filled amount mismatch");

        // Fee taken
        uint256 expectedFee = 50_000e6 * ORIGINATION_FEE / 10_000; // 0.5% = 250 USDC
        assertEq(usdc.balanceOf(feeRecipient) - feeBefore, expectedFee, "Fee mismatch");

        // Agent receives net
        uint256 expectedNet = 50_000e6 - expectedFee;
        assertEq(usdc.balanceOf(agent) - agentBefore, expectedNet, "Agent net mismatch");
    }

    function test_purchase_multipleInvestors() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, 60_000e6);
        vm.prank(investor2);
        factory.purchase(bondId, 40_000e6);

        assertEq(factory.holderBalance(bondId, investor1), 60_000e6);
        assertEq(factory.holderBalance(bondId, investor2), 40_000e6);
        assertEq(factory.bondSupply(bondId), 100_000e6);

        IRevenueBond.Bond memory bond = factory.getBond(bondId);
        assertEq(bond.filled, PRINCIPAL, "Should be fully filled");
    }

    function test_purchase_revertOverfill() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        vm.expectRevert();
        factory.purchase(bondId, PRINCIPAL + 1);
    }

    // ═══════════════════════════════════════════════════
    //  REVENUE & COUPON
    // ═══════════════════════════════════════════════════

    function test_serviceDebt_and_claimCoupon() public {
        // Issue and fill bond
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, 60_000e6);
        vm.prank(investor2);
        factory.purchase(bondId, 40_000e6);

        // Simulate revenue
        revenueSource.addRevenue(bondId, 5_000e6); // $5K revenue

        // Service debt
        factory.serviceDebt(bondId);

        // Check escrow
        assertEq(factory.escrowBalances(bondId), 5_000e6, "Escrow should have 5K");

        // Investor1 claims (60% of bond → 60% of coupon)
        uint256 bal1Before = usdc.balanceOf(investor1);
        vm.prank(investor1);
        uint256 payout1 = factory.claimCoupon(bondId);

        assertEq(payout1, 3_000e6, "Investor1 should get 60% of 5K = 3K");
        assertEq(usdc.balanceOf(investor1) - bal1Before, 3_000e6);

        // Investor2 claims (40%)
        uint256 bal2Before = usdc.balanceOf(investor2);
        vm.prank(investor2);
        uint256 payout2 = factory.claimCoupon(bondId);

        assertEq(payout2, 2_000e6, "Investor2 should get 40% of 5K = 2K");
        assertEq(usdc.balanceOf(investor2) - bal2Before, 2_000e6);

        // Escrow drained
        assertEq(factory.escrowBalances(bondId), 0, "Escrow should be empty");
    }

    function test_claimCoupon_multipleRounds() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, PRINCIPAL); // 100% holder

        // Round 1: 2K revenue
        revenueSource.addRevenue(bondId, 2_000e6);
        factory.serviceDebt(bondId);

        vm.prank(investor1);
        uint256 payout1 = factory.claimCoupon(bondId);
        assertEq(payout1, 2_000e6);

        // Round 2: 3K more revenue
        revenueSource.addRevenue(bondId, 3_000e6);
        factory.serviceDebt(bondId);

        vm.prank(investor1);
        uint256 payout2 = factory.claimCoupon(bondId);
        assertEq(payout2, 3_000e6);

        // No double-claim
        vm.prank(investor1);
        uint256 payout3 = factory.claimCoupon(bondId);
        assertEq(payout3, 0, "Should not double-claim");
    }

    function test_claimableCoupon_view() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, PRINCIPAL);

        // Before revenue
        assertEq(factory.claimableCoupon(bondId, investor1), 0);

        // After revenue
        revenueSource.addRevenue(bondId, 10_000e6);
        factory.serviceDebt(bondId);

        assertEq(factory.claimableCoupon(bondId, investor1), 10_000e6);
    }

    // ═══════════════════════════════════════════════════
    //  MATURITY & REDEMPTION
    // ═══════════════════════════════════════════════════

    function test_redeem_atMaturity() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, PRINCIPAL);

        // Coupon payments via revenue source
        revenueSource.addRevenue(bondId, 8_000e6);
        factory.serviceDebt(bondId);
        vm.prank(investor1);
        factory.claimCoupon(bondId); // Claims 8K

        // Agent deposits principal return (does NOT increase coupon debt)
        usdc.mint(agent, PRINCIPAL);
        vm.startPrank(agent);
        usdc.approve(address(factory), PRINCIPAL);
        factory.depositPrincipal(bondId, PRINCIPAL);
        vm.stopPrank();

        // Warp past maturity
        vm.roll(block.number + DURATION + 1);

        uint256 before = usdc.balanceOf(investor1);
        vm.prank(investor1);
        uint256 redeemed = factory.redeem(bondId);

        // Principal returned fully
        assertEq(redeemed, PRINCIPAL, "Should get full principal back");
        assertTrue(usdc.balanceOf(investor1) > before, "Should have received USDC");

        // Bond marked matured
        IRevenueBond.Bond memory bond = factory.getBond(bondId);
        assertEq(uint8(bond.status), uint8(IRevenueBond.BondStatus.Matured));
    }

    function test_redeem_revertBeforeMaturity() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, PRINCIPAL);

        vm.prank(investor1);
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.BondNotMatured.selector, bondId));
        factory.redeem(bondId);
    }

    function test_redeem_partialReturn_underfunded() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        vm.prank(investor1);
        factory.purchase(bondId, PRINCIPAL);

        // Only fund 30K — less than 100K principal, so partial return
        revenueSource.addRevenue(bondId, 30_000e6);
        factory.serviceDebt(bondId);

        vm.roll(block.number + DURATION + 1);

        uint256 before = usdc.balanceOf(investor1);
        vm.prank(investor1);
        uint256 redeemed = factory.redeem(bondId);

        // Should get partial return (30K total, 30K is coupon share, principal = 0)
        // Underfunded bonds mean investors lose principal
        assertTrue(redeemed < PRINCIPAL, "Should be partial");
        assertTrue(usdc.balanceOf(investor1) > before, "Should have received something");
    }

    // ═══════════════════════════════════════════════════
    //  FULL LIFECYCLE
    // ═══════════════════════════════════════════════════

    function test_fullLifecycle() public {
        // 1. Agent issues bond
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        // 2. Two investors buy in
        vm.prank(investor1);
        factory.purchase(bondId, 70_000e6);
        vm.prank(investor2);
        factory.purchase(bondId, 30_000e6);

        // 3. Revenue flows in over time (3 rounds)
        for (uint256 i = 0; i < 3; i++) {
            revenueSource.addRevenue(bondId, 10_000e6);
            factory.serviceDebt(bondId);
            vm.roll(block.number + DURATION / 4);
        }

        // 4. Investors claim coupons mid-life
        vm.prank(investor1);
        factory.claimCoupon(bondId);
        vm.prank(investor2);
        factory.claimCoupon(bondId);

        // 5. Final revenue round
        revenueSource.addRevenue(bondId, PRINCIPAL + 10_000e6); // Cover principal + extra
        factory.serviceDebt(bondId);

        // 6. Warp past maturity
        vm.roll(block.number + DURATION);

        // 7. Both redeem
        vm.prank(investor1);
        factory.redeem(bondId);
        vm.prank(investor2);
        factory.redeem(bondId);

        // 8. Bond fully matured
        IRevenueBond.Bond memory bond = factory.getBond(bondId);
        assertEq(uint8(bond.status), uint8(IRevenueBond.BondStatus.Matured), "Should be matured");
        assertEq(factory.bondSupply(bondId), 0, "Supply should be zero");
    }

    // ═══════════════════════════════════════════════════
    //  ADMIN
    // ═══════════════════════════════════════════════════

    function test_markDefault() public {
        vm.prank(agent);
        uint256 bondId = factory.issueBond(address(revenueSource), PRINCIPAL, COUPON_BPS, DURATION);

        factory.markDefault(bondId);

        IRevenueBond.Bond memory bond = factory.getBond(bondId);
        assertEq(uint8(bond.status), uint8(IRevenueBond.BondStatus.Defaulted));
    }

    function test_setMinIssuerScore() public {
        factory.setMinIssuerScore(80);
        assertEq(factory.minIssuerScore(), 80);
    }

    function test_setOriginationFee() public {
        factory.setOriginationFee(100);
        assertEq(factory.originationFeeBps(), 100);
    }

    function test_pauseUnpause() public {
        factory.pause();
        assertTrue(factory.paused());
        factory.unpause();
        assertFalse(factory.paused());
    }
}
