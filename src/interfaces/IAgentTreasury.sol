// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentTreasury — Agent Treasury Interface v1
/// @author Arcis Protocol (arcis.money)
/// @notice The ATI standard. Three functions. One interface.
/// @dev Compliant vaults MUST implement all three functions.
///      Designed for autonomous AI agents to manage treasury capital.
///      No UI required. No human approval flows. Pure contract interaction.
interface IAgentTreasury {
    /// @notice Deposit USDC into the vault
    /// @param amount The amount of USDC to deposit (6 decimals)
    /// @return shares The number of raUSDC shares minted to the caller
    /// @dev MUST revert if amount is 0
    /// @dev MUST revert if vault deposit cap is reached
    /// @dev Caller MUST have approved the vault to spend `amount` USDC
    /// @dev MUST emit Deposit(agent, amount, shares)
    function deposit(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraw USDC from the vault by redeeming shares
    /// @param shares The number of raUSDC shares to redeem
    /// @return amount The amount of USDC returned (principal + yield)
    /// @dev MUST revert if shares exceeds caller balance
    /// @dev MUST revert if vault has insufficient liquidity
    /// @dev MUST emit Withdraw(agent, shares, amount)
    function withdraw(uint256 shares) external returns (uint256 amount);

    /// @notice Query the current USDC value of an agent's position
    /// @param agent The address of the agent (or any holder)
    /// @return The current value in USDC (6 decimals) including accrued yield
    /// @dev MUST NOT revert for any valid address
    /// @dev MUST return 0 for addresses with no position
    function balance(address agent) external view returns (uint256);

    /// @notice Emitted when an agent deposits USDC
    event Deposit(address indexed agent, uint256 amount, uint256 shares);

    /// @notice Emitted when an agent withdraws USDC
    event Withdraw(address indexed agent, uint256 shares, uint256 amount);
}
