// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/periphery/ATIRouter.sol";
import "../src/core/ArcisVault.sol";
import "../src/core/AgentCredit.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockStrategy.sol";
import "./mocks/MockIdentityRegistry.sol";

contract ATIRouterTest is Test {
    ATIRouter public router;
    ArcisVault public vault;
    AgentCredit public credit;
    MockUSDC public usdc;
    MockStrategy public strategy;
    MockIdentityRegistry public registry;

    address public agent = address(0xA1);

    function setUp() public {
        usdc = new MockUSDC();
        registry = new MockIdentityRegistry();
        vault = new ArcisVault(address(usdc), 10_000_000e6, 200, address(this), 2000);
        strategy = new MockStrategy(address(vault), address(usdc));
        vault.queueStrategy(address(strategy), 7000);
        vm.warp(block.timestamp + 25 hours);
        vault.executeStrategy();
        credit = new AgentCredit(address(vault), address(usdc), address(registry), 500);

        // Fund credit lending pool
        usdc.mint(address(this), 1_000_000e6);
        usdc.approve(address(credit), type(uint256).max);
        credit.fundPool(500_000e6);

        router = new ATIRouter(address(vault), address(credit), address(usdc));

        // Fund agent
        usdc.mint(agent, 100_000e6);
        vm.startPrank(agent);
        usdc.approve(address(router), type(uint256).max);
        // Also approve vault shares for router
        vault.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // ── Deposit ──

    function test_deposit() public {
        vm.prank(agent);
        uint256 shares = router.deposit(1000e6);
        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(agent), shares, "Shares should be in agent wallet");
    }

    function test_deposit_zeroReverts() public {
        vm.prank(agent);
        vm.expectRevert();
        router.deposit(0);
    }

    // ── Withdraw ──

    function test_withdraw() public {
        vm.prank(agent);
        uint256 shares = router.deposit(1000e6);

        uint256 balBefore = usdc.balanceOf(agent);
        vm.prank(agent);
        uint256 amount = router.withdraw(shares);
        assertGt(amount, 0, "Should receive USDC back");
        assertEq(usdc.balanceOf(agent) - balBefore, amount, "USDC should arrive in agent wallet");
    }

    // ── WithdrawMax ──

    function test_withdrawMax() public {
        vm.prank(agent);
        router.deposit(5000e6);

        uint256 balBefore = usdc.balanceOf(agent);
        vm.prank(agent);
        uint256 amount = router.withdrawMax();
        assertGt(amount, 0, "Should receive USDC");
        assertEq(vault.balanceOf(agent), 0, "Should have zero shares after withdrawMax");
    }

    function test_withdrawMax_zeroBalance() public {
        vm.prank(agent);
        uint256 amount = router.withdrawMax();
        assertEq(amount, 0, "Should return 0 for zero balance");
    }

    // ── DepositMax ──

    function test_depositMax() public {
        uint256 balBefore = usdc.balanceOf(agent);
        vm.prank(agent);
        uint256 shares = router.depositMax();
        assertGt(shares, 0, "Should receive shares");
        assertEq(usdc.balanceOf(agent), 0, "All USDC should be deposited");
    }

    // ── DepositAndBorrow ──

    function test_depositAndBorrow() public {
        registry.setScore(agent, 75); // Tier 3: 130% collateral
        vm.prank(agent);
        (uint256 shares, uint256 loanId) = router.depositAndBorrow(10_000e6, 3000e6);
        assertGt(shares, 0, "Should receive shares as collateral");
        assertGt(loanId, 0, "Should create a loan");
        // Agent should receive the borrowed USDC
        // Agent started with 100K, deposited 10K, got 3K back from borrow = 93K
        assertGe(usdc.balanceOf(agent), 90_000e6, "Agent should have borrowed USDC");
    }

    function test_depositAndBorrow_noCreditReverts() public {
        ATIRouter noCreditRouter = new ATIRouter(address(vault), address(0), address(usdc));
        vm.prank(agent);
        usdc.approve(address(noCreditRouter), type(uint256).max);
        vm.prank(agent);
        vm.expectRevert();
        noCreditRouter.depositAndBorrow(1000e6, 500e6);
    }

    // ── View Functions ──

    function test_position() public {
        vm.prank(agent);
        router.deposit(1000e6);
        uint256 pos = router.position(agent);
        assertApproxEqAbs(pos, 1000e6, 1, "Position should match deposit");
    }

    function test_previewDeposit() public {
        uint256 preview = router.previewDeposit(1000e6);
        assertGt(preview, 0, "Preview should return non-zero shares");
    }

    function test_previewWithdraw() public {
        vm.prank(agent);
        uint256 shares = router.deposit(1000e6);
        uint256 preview = router.previewWithdraw(shares);
        assertApproxEqAbs(preview, 1000e6, 1, "Preview should match deposit value");
    }

    // ── ATI v1.1 Discovery ──

    function test_vaultAsset() public view {
        address asset = vault.asset();
        assertEq(asset, address(usdc), "asset() should return USDC address");
    }

    function test_vaultMaxDeposit() public view {
        uint256 max = vault.maxDeposit(agent);
        assertEq(max, 10_000_000e6, "maxDeposit should equal full cap for empty vault");
    }

    function test_vaultMaxDeposit_afterDeposit() public {
        vm.prank(agent);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        vault.deposit(1000e6);
        uint256 max = vault.maxDeposit(agent);
        assertApproxEqAbs(max, 10_000_000e6 - 1000e6, 1, "maxDeposit should decrease after deposit");
    }

    function test_vaultMaxDeposit_whenPaused() public {
        vault.pause();
        uint256 max = vault.maxDeposit(agent);
        assertEq(max, 0, "maxDeposit should be 0 when paused");
    }
}
