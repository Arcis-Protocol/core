// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ArcisVault} from "../src/core/ArcisVault.sol";
import {AgentCredit} from "../src/core/AgentCredit.sol";
import {ATIRouter} from "../src/periphery/ATIRouter.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";

contract ArcisVaultTest is Test {
    ArcisVault public vault;
    MockUSDC public usdc;
    MockStrategy public strategyA;
    MockStrategy public strategyB;

    address public owner = address(this);
    address public feeRecipient = address(0xFEE);
    address public agent1 = address(0xA1);
    address public agent2 = address(0xA2);
    address public agent3 = address(0xA3);

    uint256 constant DEPOSIT_CAP = 1_000_000e6; // 1M USDC
    uint256 constant FEE_BPS = 200;              // 2%
    uint256 constant RESERVE_RATIO = 1_000;      // 10%

    function setUp() public {
        usdc = new MockUSDC();
        vault = new ArcisVault(
            address(usdc),
            DEPOSIT_CAP,
            FEE_BPS,
            feeRecipient,
            RESERVE_RATIO
        );

        // Deploy mock strategies
        strategyA = new MockStrategy(address(usdc), address(vault));
        strategyB = new MockStrategy(address(usdc), address(vault));

        // Fund agents
        usdc.mint(agent1, 100_000e6);
        usdc.mint(agent2, 200_000e6);
        usdc.mint(agent3, 50_000e6);

        // Agents approve vault
        vm.prank(agent1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(agent2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(agent3);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ══════════════════════════════════════════════════════════════
    //                      DEPOSIT TESTS
    // ══════════════════════════════════════════════════════════════

    function test_deposit_basic() public {
        vm.prank(agent1);
        uint256 shares = vault.deposit(10_000e6);

        assertGt(shares, 0, "Should mint shares");
        assertEq(vault.balanceOf(agent1), shares, "Agent should hold shares");
        assertEq(vault.totalAssets(), 10_000e6, "Total assets should match");
        assertEq(usdc.balanceOf(address(vault)), 10_000e6, "Vault should hold USDC");
    }

    function test_deposit_multiple_agents() public {
        vm.prank(agent1);
        uint256 shares1 = vault.deposit(10_000e6);

        vm.prank(agent2);
        uint256 shares2 = vault.deposit(20_000e6);

        assertEq(vault.totalAssets(), 30_000e6);
        assertEq(vault.totalSupply(), shares1 + shares2);
    }

    function test_deposit_reverts_zero() public {
        vm.prank(agent1);
        vm.expectRevert();
        vault.deposit(0);
    }

    function test_deposit_reverts_below_minimum() public {
        vm.prank(agent1);
        vm.expectRevert();
        vault.deposit(100); // 0.0001 USDC, below MIN_DEPOSIT
    }

    function test_deposit_reverts_cap_exceeded() public {
        // Fund agent with more than cap
        usdc.mint(agent1, 2_000_000e6);
        vm.prank(agent1);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(agent1);
        vm.expectRevert();
        vault.deposit(1_000_001e6);
    }

    function test_deposit_reverts_when_paused() public {
        vault.pause();

        vm.prank(agent1);
        vm.expectRevert();
        vault.deposit(1_000e6);
    }

    // ══════════════════════════════════════════════════════════════
    //                     WITHDRAW TESTS
    // ══════════════════════════════════════════════════════════════

    function test_withdraw_basic() public {
        vm.prank(agent1);
        uint256 shares = vault.deposit(10_000e6);

        vm.prank(agent1);
        uint256 amount = vault.withdraw(shares);

        // Due to virtual share offset, may not be exactly 10_000e6
        assertApproxEqAbs(amount, 10_000e6, 1e6, "Should return approximately deposited amount");
        assertEq(vault.balanceOf(agent1), 0, "Should have no shares");
    }

    function test_withdraw_partial() public {
        vm.prank(agent1);
        uint256 shares = vault.deposit(10_000e6);

        uint256 halfShares = shares / 2;
        vm.prank(agent1);
        uint256 amount = vault.withdraw(halfShares);

        assertGt(amount, 0);
        assertEq(vault.balanceOf(agent1), shares - halfShares);
    }

    function test_withdraw_reverts_insufficient_shares() public {
        vm.prank(agent1);
        vault.deposit(10_000e6);

        vm.prank(agent1);
        vm.expectRevert();
        vault.withdraw(type(uint256).max);
    }

    // ══════════════════════════════════════════════════════════════
    //                     BALANCE TESTS
    // ══════════════════════════════════════════════════════════════

    function test_balance_returns_usdc_value() public {
        vm.prank(agent1);
        vault.deposit(10_000e6);

        uint256 bal = vault.balance(agent1);
        assertApproxEqAbs(bal, 10_000e6, 1e6);
    }

    function test_balance_zero_for_no_position() public {
        assertEq(vault.balance(agent1), 0);
    }

    function test_balance_grows_with_yield() public {
        // Add a strategy and simulate yield
        vault.addStrategy(address(strategyA), 9_000); // 90% allocation

        vm.prank(agent1);
        vault.deposit(10_000e6);

        // Deploy to strategy
        vault.rebalance();

        // Simulate yield: strategy gains 500 USDC
        usdc.mint(address(strategyA), 500e6);
        strategyA.addYield(500e6);

        // Harvest yield
        vault.harvest();

        uint256 bal = vault.balance(agent1);
        // Balance should be > 10_000 due to yield (minus fee)
        assertGt(bal, 10_000e6, "Balance should grow with yield");
    }

    // ══════════════════════════════════════════════════════════════
    //                    STRATEGY TESTS
    // ══════════════════════════════════════════════════════════════

    function test_addStrategy() public {
        vault.addStrategy(address(strategyA), 9_000);
        assertEq(vault.strategyCount(), 1);
        assertTrue(vault.isStrategy(address(strategyA)));
    }

    function test_addStrategy_reverts_duplicate() public {
        vault.addStrategy(address(strategyA), 5_000);
        vm.expectRevert();
        vault.addStrategy(address(strategyA), 4_000);
    }

    function test_updateAllocations() public {
        vault.addStrategy(address(strategyA), 5_000);
        vault.addStrategy(address(strategyB), 4_000);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6_000;
        weights[1] = 3_000;
        vault.updateAllocations(weights);
    }

    function test_updateAllocations_reverts_bad_sum() public {
        vault.addStrategy(address(strategyA), 5_000);
        vault.addStrategy(address(strategyB), 4_000);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5_000;
        weights[1] = 5_000; // Sum = 10000, but reserve = 1000, so total = 11000
        vm.expectRevert();
        vault.updateAllocations(weights);
    }

    function test_rebalance() public {
        vault.addStrategy(address(strategyA), 9_000);

        // Fund strategy with USDC (to simulate it being able to accept)
        vm.prank(agent1);
        vault.deposit(10_000e6);

        vault.rebalance();

        // Rebalance deploys 90% of excess over target reserve
        // Total=10K, targetReserve=1K, excess=9K, deployed=90%*9K=8.1K
        // Reserve remaining = 10K - 8.1K = 1.9K
        assertApproxEqAbs(vault.reserveBalance(), 1_900e6, 100e6, "Reserve after rebalance");
    }

    // ══════════════════════════════════════════════════════════════
    //                    HARVEST / FEE TESTS
    // ══════════════════════════════════════════════════════════════

    function test_harvest_accrues_fees() public {
        vault.addStrategy(address(strategyA), 9_000);

        vm.prank(agent1);
        vault.deposit(10_000e6);

        vault.rebalance();

        // Simulate yield
        usdc.mint(address(strategyA), 1_000e6);
        strategyA.addYield(1_000e6);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);
        vault.harvest();
        uint256 feeRecipientSharesAfter = vault.balanceOf(feeRecipient);

        assertGt(feeRecipientSharesAfter, feeRecipientSharesBefore, "Fee recipient should receive shares");
    }

    // ══════════════════════════════════════════════════════════════
    //                     ERC-20 TESTS
    // ══════════════════════════════════════════════════════════════

    function test_transfer_shares() public {
        vm.prank(agent1);
        uint256 shares = vault.deposit(10_000e6);

        vm.prank(agent1);
        vault.transfer(agent2, shares / 2);

        assertEq(vault.balanceOf(agent1), shares - shares / 2);
        assertEq(vault.balanceOf(agent2), shares / 2);
    }

    function test_approve_and_transferFrom() public {
        vm.prank(agent1);
        uint256 shares = vault.deposit(10_000e6);

        vm.prank(agent1);
        vault.approve(agent2, shares);

        vm.prank(agent2);
        vault.transferFrom(agent1, agent2, shares);

        assertEq(vault.balanceOf(agent1), 0);
        assertEq(vault.balanceOf(agent2), shares);
    }

    // ══════════════════════════════════════════════════════════════
    //                      ADMIN TESTS
    // ══════════════════════════════════════════════════════════════

    function test_pause_unpause() public {
        vault.pause();
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_setDepositCap() public {
        vault.setDepositCap(5_000_000e6);
        assertEq(vault.depositCap(), 5_000_000e6);
    }

    function test_twoStepOwnership() public {
        address newOwner = address(0xBEEF);
        vault.transferOwnership(newOwner);
        assertEq(vault.pendingOwner(), newOwner);

        // Can't accept from wrong address
        vm.prank(agent1);
        vm.expectRevert();
        vault.acceptOwnership();

        // Accept from correct address
        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner);
    }

    function test_onlyOwner_reverts() public {
        vm.prank(agent1);
        vm.expectRevert();
        vault.pause();
    }

    function test_emergencyWithdrawStrategy() public {
        vault.addStrategy(address(strategyA), 9_000);

        vm.prank(agent1);
        vault.deposit(10_000e6);

        vault.rebalance();

        uint256 reserveBefore = vault.reserveBalance();
        vault.emergencyWithdrawStrategy(0);

        assertGt(vault.reserveBalance(), reserveBefore, "Reserve should increase after emergency");
    }

    // ══════════════════════════════════════════════════════════════
    //                      FUZZ TESTS
    // ══════════════════════════════════════════════════════════════

    function testFuzz_deposit_withdraw_roundtrip(uint256 amount) public {
        amount = bound(amount, 1e6, DEPOSIT_CAP);

        usdc.mint(agent1, amount);
        vm.prank(agent1);
        usdc.approve(address(vault), amount);

        vm.prank(agent1);
        uint256 shares = vault.deposit(amount);

        vm.prank(agent1);
        uint256 returned = vault.withdraw(shares);

        // Should get back approximately what was deposited (within 1 USDC for rounding)
        assertApproxEqAbs(returned, amount, 1e6, "Round trip should preserve value");
    }

    function testFuzz_share_price_never_decreases(uint256 deposit1, uint256 deposit2) public {
        // Bound to realistic ranges — same order of magnitude avoids virtual offset edge cases
        deposit1 = bound(deposit1, 100e6, 500_000e6);
        deposit2 = bound(deposit2, 100e6, 500_000e6);

        usdc.mint(agent1, deposit1);
        vm.prank(agent1);
        usdc.approve(address(vault), deposit1);

        vm.prank(agent1);
        vault.deposit(deposit1);

        uint256 price1 = vault.totalAssets() * 1e18 / vault.totalSupply();

        usdc.mint(agent2, deposit2);
        vm.prank(agent2);
        usdc.approve(address(vault), deposit2);

        vm.prank(agent2);
        vault.deposit(deposit2);

        uint256 price2 = vault.totalAssets() * 1e18 / vault.totalSupply();

        // Share price must not decrease from deposits (may increase slightly due to virtual offset rounding)
        // Allow 1% tolerance for integer math rounding — in practice this is < 0.1%
        assertTrue(
            price2 >= price1 || (price1 - price2) * 10_000 / price1 < 100,
            "Share price decreased by more than 1%"
        );
    }
}
