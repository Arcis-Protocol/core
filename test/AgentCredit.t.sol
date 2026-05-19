// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ArcisVault} from "../src/core/ArcisVault.sol";
import {AgentCredit} from "../src/core/AgentCredit.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.sol";

contract AgentCreditTest is Test {
    ArcisVault public vault;
    AgentCredit public credit;
    MockUSDC public usdc;
    MockIdentityRegistry public registry;

    address public owner = address(this);
    address public agent1 = address(0xA1);
    address public agent2 = address(0xA2);
    address public liquidator = address(0xDEAD);
    address public feeRecipient = address(0xFEE);

    function setUp() public {
        usdc = new MockUSDC();
        registry = new MockIdentityRegistry();

        vault = new ArcisVault(
            address(usdc),
            10_000_000e6,
            200,
            feeRecipient,
            1_000
        );

        credit = new AgentCredit(
            address(vault),
            address(usdc),
            address(registry),
            1_000 // 10% base rate
        );

        // Fund agents and let them deposit into vault
        usdc.mint(agent1, 100_000e6);
        usdc.mint(agent2, 100_000e6);
        usdc.mint(liquidator, 100_000e6);

        // Fund the lending pool
        usdc.mint(address(this), 500_000e6);
        usdc.approve(address(credit), 500_000e6);
        credit.fundPool(500_000e6);

        // Agent1 deposits into vault to get raUSDC
        vm.startPrank(agent1);
        usdc.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6);
        vault.approve(address(credit), type(uint256).max);
        usdc.approve(address(credit), type(uint256).max);
        vm.stopPrank();

        // Agent2 deposits too
        vm.startPrank(agent2);
        usdc.approve(address(vault), 50_000e6);
        vault.deposit(50_000e6);
        vault.approve(address(credit), type(uint256).max);
        usdc.approve(address(credit), type(uint256).max);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════════
    //                     BORROW TESTS
    // ══════════════════════════════════════════════════════════════

    function test_borrow_no_identity() public {
        // No identity = 200% collateral ratio
        uint256 shares = vault.balanceOf(agent1);
        uint256 borrowAmount = 10_000e6;

        // Need 200% collateral = 20,000 USDC worth of raUSDC
        vm.prank(agent1);
        uint256 loanId = credit.borrow(borrowAmount, shares);

        assertEq(loanId, 1);
        assertEq(usdc.balanceOf(agent1), 50_000e6 + borrowAmount); // initial - deposited + borrowed
    }

    function test_borrow_with_high_reputation() public {
        // Register agent with high score -> better ratio
        registry.register(agent1, 80); // Tier 4: 115% collateral

        uint256 shares = vault.balanceOf(agent1);
        uint256 borrowAmount = 20_000e6;

        vm.prank(agent1);
        uint256 loanId = credit.borrow(borrowAmount, shares);

        assertGt(loanId, 0);
    }

    function test_borrow_reverts_insufficient_collateral() public {
        // Try to borrow more than collateral supports
        uint256 smallCollateral = vault.balanceOf(agent1) / 100;
        uint256 bigBorrow = 40_000e6;

        vm.prank(agent1);
        vm.expectRevert();
        credit.borrow(bigBorrow, smallCollateral);
    }

    // ══════════════════════════════════════════════════════════════
    //                      REPAY TESTS
    // ══════════════════════════════════════════════════════════════

    function test_repay_returns_collateral() public {
        uint256 shares = vault.balanceOf(agent1);

        vm.prank(agent1);
        uint256 loanId = credit.borrow(10_000e6, shares);

        // Need to fund agent with enough to repay (principal + interest)
        usdc.mint(agent1, 1_000e6); // extra for interest

        vm.prank(agent1);
        credit.repay(loanId);

        // Agent should have collateral back
        assertGt(vault.balanceOf(agent1), 0, "Collateral should be returned");
    }

    function test_repay_reverts_wrong_agent() public {
        uint256 shares = vault.balanceOf(agent1);

        vm.prank(agent1);
        uint256 loanId = credit.borrow(10_000e6, shares);

        vm.prank(agent2);
        vm.expectRevert();
        credit.repay(loanId);
    }

    // ══════════════════════════════════════════════════════════════
    //                  COLLATERAL RATIO TESTS
    // ══════════════════════════════════════════════════════════════

    function test_collateralRatio_tiers() public {
        // No identity
        assertEq(credit.getCollateralRatio(agent1), 20_000); // 200%

        // Tier 1: score 1-25
        registry.register(agent1, 15);
        assertEq(credit.getCollateralRatio(agent1), 17_500); // 175%

        // Tier 2: score 26-50
        registry.setScore(agent1, 40);
        assertEq(credit.getCollateralRatio(agent1), 15_000); // 150%

        // Tier 3: score 51-75
        registry.setScore(agent1, 60);
        assertEq(credit.getCollateralRatio(agent1), 13_000); // 130%

        // Tier 4: score 76-100
        registry.setScore(agent1, 90);
        assertEq(credit.getCollateralRatio(agent1), 11_500); // 115%
    }

    // ══════════════════════════════════════════════════════════════
    //                    HEALTH FACTOR TESTS
    // ══════════════════════════════════════════════════════════════

    function test_isHealthy_returns_true_for_overcollateralized() public {
        uint256 shares = vault.balanceOf(agent1);

        vm.prank(agent1);
        uint256 loanId = credit.borrow(10_000e6, shares);

        (bool healthy, uint256 hf) = credit.isHealthy(loanId);
        assertTrue(healthy, "Loan should be healthy");
        assertGt(hf, 1e18, "Health factor should be > 1.0");
    }

    function test_isHealthy_returns_true_for_repaid() public {
        uint256 shares = vault.balanceOf(agent1);

        vm.prank(agent1);
        uint256 loanId = credit.borrow(10_000e6, shares);

        usdc.mint(agent1, 5_000e6);
        vm.prank(agent1);
        credit.repay(loanId);

        (bool healthy,) = credit.isHealthy(loanId);
        assertTrue(healthy);
    }

    // ══════════════════════════════════════════════════════════════
    //                     INTEREST TESTS
    // ══════════════════════════════════════════════════════════════

    function test_interest_accrues_over_blocks() public {
        uint256 shares = vault.balanceOf(agent1);

        vm.prank(agent1);
        uint256 loanId = credit.borrow(10_000e6, shares);

        uint256 owedBefore = credit.totalOwed(loanId);

        // Advance 1000 blocks
        vm.roll(block.number + 1000);

        uint256 owedAfter = credit.totalOwed(loanId);
        assertGt(owedAfter, owedBefore, "Interest should accrue");
    }

    // ══════════════════════════════════════════════════════════════
    //                      ADMIN TESTS
    // ══════════════════════════════════════════════════════════════

    function test_fundPool() public {
        uint256 poolBefore = credit.lendingPool();
        usdc.mint(address(this), 10_000e6);
        usdc.approve(address(credit), 10_000e6);
        credit.fundPool(10_000e6);
        assertEq(credit.lendingPool(), poolBefore + 10_000e6);
    }

    function test_setCollateralRatios() public {
        uint256[5] memory newRatios = [uint256(25_000), 22_000, 18_000, 15_000, 12_000];
        credit.setCollateralRatios(newRatios);

        assertEq(credit.collateralRatios(0), 25_000);
        assertEq(credit.collateralRatios(4), 12_000);
    }
}
