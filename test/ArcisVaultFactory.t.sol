// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ArcisVaultFactory} from "../src/core/ArcisVaultFactory.sol";
import {ArcisAgentVault} from "../src/core/ArcisAgentVault.sol";
import {ErrorLib} from "../src/libraries/ErrorLib.sol";

/// @dev Minimal 18-decimal agent token (simulates $CUSTOS / $AKITA on Virtuals)
contract MockAgentToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ArcisVaultFactoryTest is Test {
    ArcisVaultFactory factory;
    MockAgentToken custos;
    MockAgentToken akita;

    address owner = makeAddr("owner");
    address treasury = makeAddr("treasury");
    address agent1 = makeAddr("agent1");
    address agent2 = makeAddr("agent2");
    address attacker = makeAddr("attacker");

    uint256 constant MIN_DEPOSIT = 1e18; // 1 token
    uint256 constant CAP = 10_000_000e18; // 10M tokens

    function setUp() public {
        vm.startPrank(owner);
        factory = new ArcisVaultFactory();
        vm.stopPrank();

        custos = new MockAgentToken("CUSTOS", "CUSTOS");
        akita = new MockAgentToken("AKITA", "AKITA");

        custos.mint(agent1, 1_000_000e18);
        custos.mint(agent2, 1_000_000e18);
        akita.mint(agent1, 1_000_000e18);
    }

    // ── Helper ──

    function _createCustosVault() internal returns (ArcisAgentVault) {
        vm.prank(owner);
        address vault = factory.createVault(
            address(custos), "Arcis CUSTOS", "raCUSTOS", MIN_DEPOSIT, CAP, 0, treasury, 10_000
        );
        return ArcisAgentVault(vault);
    }

    // ══════════════════════════════════════════════════════════════
    //                       FACTORY TESTS
    // ══════════════════════════════════════════════════════════════

    function test_CreateVault() public {
        ArcisAgentVault vault = _createCustosVault();

        assertEq(vault.asset(), address(custos));
        assertEq(vault.name(), "Arcis CUSTOS");
        assertEq(vault.symbol(), "raCUSTOS");
        assertEq(vault.decimals(), 18);
        assertEq(vault.MIN_DEPOSIT(), MIN_DEPOSIT);
        assertEq(vault.depositCap(), CAP);
        assertEq(vault.owner(), owner); // ownership passed through to factory owner
        assertEq(factory.vaultCount(), 1);
        assertEq(factory.vaultFor(address(custos)), address(vault));
        assertTrue(factory.isVault(address(vault)));
    }

    function test_CreateVault_RevertNonOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.Unauthorized.selector, attacker));
        factory.createVault(address(custos), "X", "X", MIN_DEPOSIT, CAP, 0, treasury, 10_000);
    }

    function test_CreateVault_RevertDuplicateAsset() public {
        _createCustosVault();
        vm.prank(owner);
        vm.expectRevert();
        factory.createVault(address(custos), "Dup", "DUP", MIN_DEPOSIT, CAP, 0, treasury, 10_000);
    }

    function test_CreateVault_RevertZeroAsset() public {
        vm.prank(owner);
        vm.expectRevert(ErrorLib.ZeroAddress.selector);
        factory.createVault(address(0), "X", "X", MIN_DEPOSIT, CAP, 0, treasury, 10_000);
    }

    function test_MultipleVaults_Registry() public {
        _createCustosVault();
        vm.prank(owner);
        factory.createVault(address(akita), "Arcis AKITA", "raAKITA", MIN_DEPOSIT, CAP, 0, treasury, 10_000);

        address[] memory all = factory.allVaults();
        assertEq(all.length, 2);
        assertEq(factory.vaultCount(), 2);
        assertTrue(factory.vaultFor(address(custos)) != factory.vaultFor(address(akita)));

        (, address asset,,, uint256 tvl,, bool isPaused) = factory.vaultInfo(1);
        assertEq(asset, address(akita));
        assertEq(tvl, 0);
        assertFalse(isPaused);
    }

    function test_Decimals_ReadFromAsset() public {
        ArcisAgentVault vault = _createCustosVault();
        assertEq(vault.decimals(), custos.decimals());
    }

    // ══════════════════════════════════════════════════════════════
    //                 AGENT VAULT — CORE ATI FLOW
    // ══════════════════════════════════════════════════════════════

    function test_DepositWithdraw_AgentToken() public {
        ArcisAgentVault vault = _createCustosVault();

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(100e18);
        vm.stopPrank();

        assertGt(shares, 0);
        assertApproxEqAbs(vault.balance(agent1), 100e18, 1); // +1/+1 offset: at most 1 wei dust
        assertEq(vault.totalAssets(), 100e18);
        assertEq(vault.reserveBalance(), 100e18); // reserve-only vault

        // Withdraw after fee window
        vm.warp(block.timestamp + 25 hours);
        vm.prank(agent1);
        uint256 amount = vault.withdraw(shares);
        assertApproxEqAbs(amount, 100e18, 2); // rounding dust only
        assertEq(custos.balanceOf(agent1), 1_000_000e18 - 100e18 + amount);
    }

    function test_EarlyWithdrawalFee() public {
        ArcisAgentVault vault = _createCustosVault();

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1000e18);
        // Immediate withdrawal → 0.1% fee
        uint256 amount = vault.withdraw(shares);
        vm.stopPrank();

        // ~0.1% fee applied
        assertApproxEqRel(amount, 999e18, 0.001e18);
        assertGt(custos.balanceOf(treasury), 0); // fee went to treasury
    }

    function test_DepositCap_Enforced() public {
        vm.prank(owner);
        address v = factory.createVault(
            address(custos), "Arcis CUSTOS", "raCUSTOS", MIN_DEPOSIT, 100e18, 0, treasury, 10_000
        );
        ArcisAgentVault vault = ArcisAgentVault(v);

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        vault.deposit(100e18);
        vm.expectRevert();
        vault.deposit(1e18);
        vm.stopPrank();
    }

    function test_MinDeposit_Enforced() public {
        ArcisAgentVault vault = _createCustosVault();
        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(ErrorLib.DepositTooSmall.selector, 0.5e18, MIN_DEPOSIT));
        vault.deposit(0.5e18);
        vm.stopPrank();
    }

    function test_Pause_BlocksDeposits() public {
        ArcisAgentVault vault = _createCustosVault();
        vm.prank(owner);
        vault.pause();

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        vm.expectRevert(ErrorLib.VaultPaused.selector);
        vault.deposit(10e18);
        vm.stopPrank();

        assertEq(vault.maxDeposit(agent1), 0);
    }

    function test_ExchangeRate_InitialAndAfterDeposit() public {
        ArcisAgentVault vault = _createCustosVault();
        assertEq(vault.exchangeRate(), 1e18);

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        vault.deposit(500e18);
        vm.stopPrank();

        // Rate stays ~1.0 with no yield
        assertApproxEqRel(vault.exchangeRate(), 1e18, 0.0001e18);
    }

    function test_InflationAttack_Blocked() public {
        ArcisAgentVault vault = _createCustosVault();

        // Attacker deposits dust then donates to skew rate
        custos.mint(attacker, 10_000e18);
        vm.startPrank(attacker);
        custos.approve(address(vault), type(uint256).max);
        vault.deposit(1e18);
        custos.transfer(address(vault), 5000e18); // donation (not counted — reserveBalance accounting)
        vm.stopPrank();

        // Victim deposits — must not be wiped out
        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        uint256 victimShares = vault.deposit(100e18);
        vm.stopPrank();

        assertGt(victimShares, 0);
        // Victim can withdraw ~full value (donation isn't in totalAssets since accounting is internal)
        assertApproxEqRel(vault.balance(agent1), 100e18, 0.01e18);
    }

    function test_PerAgentCap() public {
        ArcisAgentVault vault = _createCustosVault();
        vm.prank(owner);
        vault.setPerAgentCap(50e18);

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        vault.deposit(50e18);
        vm.expectRevert();
        vault.deposit(1e18);
        vm.stopPrank();

        // agent2 unaffected
        vm.startPrank(agent2);
        custos.approve(address(vault), type(uint256).max);
        assertGt(vault.deposit(50e18), 0);
        vm.stopPrank();
    }

    function test_TwoStepOwnership_OnVault() public {
        ArcisAgentVault vault = _createCustosVault();
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), owner); // unchanged until accept

        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner);
    }

    function test_StrategyTimelock_OnAgentVault() public {
        ArcisAgentVault vault = _createCustosVault();
        address fakeStrategy = makeAddr("strategy");

        vm.prank(owner);
        vault.queueStrategy(fakeStrategy, 5000);

        // Cannot execute before 24h
        vm.prank(owner);
        vm.expectRevert();
        vault.executeStrategy();

        vm.warp(block.timestamp + 24 hours + 1);
        vm.prank(owner);
        vault.executeStrategy();
        assertTrue(vault.isStrategy(fakeStrategy));
    }

    function test_EmergencyWithdraw_WhenPaused() public {
        ArcisAgentVault vault = _createCustosVault();

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(100e18);
        vm.stopPrank();

        vm.prank(owner);
        vault.pause();

        vm.warp(block.timestamp + 25 hours);
        vm.prank(agent1);
        uint256 amount = vault.emergencyWithdraw(shares);
        assertApproxEqAbs(amount, 100e18, 2);
    }

    // ══════════════════════════════════════════════════════════════
    //                        FUZZ TESTS
    // ══════════════════════════════════════════════════════════════

    function testFuzz_DepositWithdraw_RoundTrip(uint256 amount) public {
        amount = bound(amount, MIN_DEPOSIT, 1_000_000e18);
        ArcisAgentVault vault = _createCustosVault();

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount);
        vm.warp(block.timestamp + 25 hours);
        uint256 returned = vault.withdraw(shares);
        vm.stopPrank();

        // Never returns more than deposited; dust loss at most 1 wei with 1:1 shares
        assertLe(returned, amount);
        assertApproxEqAbs(returned, amount, 1);
    }

    function testFuzz_SharesNeverZeroForValidDeposit(uint256 amount) public {
        amount = bound(amount, MIN_DEPOSIT, CAP);
        ArcisAgentVault vault = _createCustosVault();
        custos.mint(agent1, amount);

        vm.startPrank(agent1);
        custos.approve(address(vault), type(uint256).max);
        assertGt(vault.deposit(amount), 0);
        vm.stopPrank();
    }
}
