// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/StrategyAllocator.sol";

contract StrategyAllocatorTest is Test {
    StrategyAllocator public allocator;
    address public vault = address(0xAAAA);
    address public attacker = address(0xBAD);

    function setUp() public {
        allocator = new StrategyAllocator(vault, 86400, 500); // 24h timelock, 5% drift
    }

    // ── Access Control ──

    function test_onlyOwner_queueAllocation() public {
        uint256[] memory w = new uint256[](2);
        w[0] = 7000; w[1] = 3000;
        vm.prank(attacker);
        vm.expectRevert();
        allocator.queueAllocation(w);
    }

    function test_onlyOwner_executeAllocation() public {
        vm.prank(attacker);
        vm.expectRevert();
        allocator.executeAllocation();
    }

    function test_onlyOwner_cancelAllocation() public {
        vm.prank(attacker);
        vm.expectRevert();
        allocator.cancelAllocation();
    }

    function test_onlyOwner_transferOwnership() public {
        vm.prank(attacker);
        vm.expectRevert();
        allocator.transferOwnership(attacker);
    }

    // ── Queue + Execute Flow ──

    function test_queueAndExecute() public {
        uint256[] memory w = new uint256[](2);
        w[0] = 6000; w[1] = 4000;
        allocator.queueAllocation(w);

        // Cannot execute before timelock
        vm.expectRevert();
        allocator.executeAllocation();

        // Warp past timelock
        vm.warp(block.timestamp + 86401);
        allocator.executeAllocation();
    }

    function test_cancelAllocation() public {
        uint256[] memory w = new uint256[](2);
        w[0] = 6000; w[1] = 4000;
        allocator.queueAllocation(w);
        allocator.cancelAllocation();

        // Execute should revert — nothing pending
        vm.expectRevert();
        allocator.executeAllocation();
    }

    // ── Drift Detection ──

    function test_checkDrift_noDrift() public view {
        uint256[] memory current = new uint256[](2);
        current[0] = 7000; current[1] = 3000;
        uint256[] memory target = new uint256[](2);
        target[0] = 7000; target[1] = 3000;

        (bool needs, uint256 maxDrift) = allocator.checkDrift(current, target);
        assertFalse(needs, "No drift should not need rebalance");
        assertEq(maxDrift, 0, "Max drift should be 0");
    }

    function test_checkDrift_aboveThreshold() public view {
        uint256[] memory current = new uint256[](2);
        current[0] = 7600; current[1] = 2400;
        uint256[] memory target = new uint256[](2);
        target[0] = 7000; target[1] = 3000;

        (bool needs, uint256 maxDrift) = allocator.checkDrift(current, target);
        assertTrue(needs, "Should need rebalance at 6% drift");
        assertEq(maxDrift, 600, "Max drift should be 600 bps");
    }

    // ── Rebalance Calculation ──

    function test_calculateRebalance() public {
        uint256[] memory values = new uint256[](2);
        values[0] = 8000e6; values[1] = 2000e6; // 80/20 actual
        uint256[] memory target = new uint256[](2);
        target[0] = 7000; target[1] = 3000; // 70/30 target

        StrategyAllocator temp = new StrategyAllocator(address(1), 0, 0);
        (uint256[] memory deposits, uint256[] memory withdrawals) = temp.calculateRebalance(values, target, 10_000e6);

        assertEq(withdrawals[0], 1000e6, "Should withdraw 1000 from strategy 0");
        assertEq(deposits[1], 1000e6, "Should deposit 1000 into strategy 1");
    }

    // ── Admin ──

    function test_setDriftThreshold() public {
        allocator.setDriftThreshold(300);
        assertEq(allocator.driftThresholdBps(), 300);
    }

    function test_transferOwnership() public {
        address newOwner = address(0xBBBB);
        allocator.transferOwnership(newOwner);
        assertEq(allocator.owner(), newOwner);

        // Old owner can no longer call
        vm.expectRevert();
        allocator.setDriftThreshold(100);
    }
}
