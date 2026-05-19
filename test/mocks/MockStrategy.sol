// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStrategyAdapter} from "../../src/interfaces/IStrategyAdapter.sol";

/// @title MockStrategy
/// @notice Simulated yield strategy for testing
/// @dev Owner can set yield to simulate interest accrual
contract MockStrategy is IStrategyAdapter {
    address public usdc;
    address public vault;
    bool public active = true;

    uint256 public deployed;
    uint256 public simulatedYield;
    uint256 public mockAPY = 500; // 5.00%

    constructor(address _usdc, address _vault) {
        usdc = _usdc;
        vault = _vault;
    }

    function deploy(uint256 amount) external override returns (uint256) {
        // Just hold the USDC
        deployed += amount;
        emit Deployed(amount);
        return amount;
    }

    function withdrawFromStrategy(uint256 amount) external override returns (uint256) {
        uint256 toWithdraw = amount > deployed ? deployed : amount;
        deployed -= toWithdraw;

        // Transfer USDC to caller (vault)
        (bool success,) = usdc.call(
            abi.encodeWithSelector(0xa9059cbb, msg.sender, toWithdraw)
        );
        require(success);

        emit Withdrawn(toWithdraw);
        return toWithdraw;
    }

    function totalValue() external view override returns (uint256) {
        return deployed + simulatedYield;
    }

    function currentAPY() external view override returns (uint256) {
        return mockAPY;
    }

    function availableLiquidity() external view override returns (uint256) {
        return deployed + simulatedYield;
    }

    function isActive() external view override returns (bool) {
        return active;
    }

    function harvest() external override returns (uint256) {
        uint256 yield_ = simulatedYield;
        if (yield_ > 0) {
            deployed += yield_;
            simulatedYield = 0;
            emit Harvested(yield_);
        }
        return yield_;
    }

    function emergencyWithdraw() external override returns (uint256) {
        uint256 total = deployed + simulatedYield;
        deployed = 0;
        simulatedYield = 0;
        active = false;

        if (total > 0) {
            (bool success,) = usdc.call(
                abi.encodeWithSelector(0xa9059cbb, msg.sender, total)
            );
            require(success);
        }

        emit Withdrawn(total);
        return total;
    }

    // ── Test helpers ──

    function addYield(uint256 amount) external {
        simulatedYield += amount;
    }

    function setActive(bool _active) external {
        active = _active;
    }

    function setAPY(uint256 apy) external {
        mockAPY = apy;
    }
}
