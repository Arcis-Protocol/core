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

// src/interfaces/IStrategyAdapter.sol

/// @title IStrategyAdapter
/// @notice Interface for yield source adapters (Aave, Morpho, Ondo, etc.)
/// @dev Each yield source gets its own adapter that implements this interface.
///      The StrategyAllocator routes capital to adapters based on allocation weights.
interface IStrategyAdapter {
    /// @notice Deploy capital into the yield source
    /// @param amount USDC amount to deploy (6 decimals)
    /// @return deployed Actual amount deployed (may differ due to fees)
    function deploy(uint256 amount) external returns (uint256 deployed);

    /// @notice Withdraw capital from the yield source
    /// @param amount USDC amount to withdraw (6 decimals)
    /// @return withdrawn Actual amount withdrawn
    function withdrawFromStrategy(uint256 amount) external returns (uint256 withdrawn);

    /// @notice Total value of assets deployed in this strategy (in USDC)
    /// @return Total USDC value including accrued yield
    function totalValue() external view returns (uint256);

    /// @notice Current APY of this strategy in basis points
    /// @return APY in bps (e.g. 450 = 4.50%)
    function currentAPY() external view returns (uint256);

    /// @notice Maximum amount that can be instantly withdrawn
    /// @return Maximum USDC that can be withdrawn in one tx
    function availableLiquidity() external view returns (uint256);

    /// @notice Whether this strategy is currently active
    function isActive() external view returns (bool);

    /// @notice Harvest any pending yield and reinvest
    /// @return harvested Amount of yield harvested (in USDC)
    function harvest() external returns (uint256 harvested);

    /// @notice Emergency withdraw all funds from the strategy
    /// @return recovered Total USDC recovered
    function emergencyWithdraw() external returns (uint256 recovered);

    /// @notice Emitted when capital is deployed
    event Deployed(uint256 amount);

    /// @notice Emitted when capital is withdrawn
    event Withdrawn(uint256 amount);

    /// @notice Emitted when yield is harvested
    event Harvested(uint256 amount);
}

// src/periphery/BaseStrategy.sol

/// @title BaseStrategy
/// @notice Shared logic for all yield strategy adapters
/// @dev Concrete adapters (Aave, Morpho, Ondo) inherit from this.
///      Handles access control, pausing, and safe token transfers.
abstract contract BaseStrategy is IStrategyAdapter {
    address public immutable vault;
    address public immutable usdc;
    address public owner;

    bool public active;
    uint256 internal _deployedAmount;

    modifier onlyVault() {
        if (msg.sender != vault) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert ErrorLib.Unauthorized(msg.sender);
        _;
    }

    modifier whenActive() {
        if (!active) revert ErrorLib.StrategyNotRegistered(address(this));
        _;
    }

    constructor(address _vault, address _usdc) {
        if (_vault == address(0) || _usdc == address(0)) revert ErrorLib.ZeroAddress();
        vault = _vault;
        usdc = _usdc;
        owner = msg.sender;
        active = true;
    }

    function isActive() external view override returns (bool) {
        return active;
    }

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ErrorLib.ZeroAddress();
        owner = newOwner;
        // Event omitted — use owner() view to check
    }

    // ── Safe token helpers ──

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

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert ErrorLib.TransferFailed();
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(0x70a08231, account)
        );
        if (!success || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }
}

// src/periphery/StrategyAave.sol

/// @title StrategyAave
/// @author Arcis Protocol
/// @notice Deploys USDC into Aave V3 lending pool on Base
/// @dev Deposits USDC -> receives aUSDC -> earns supply APY.
///      On withdrawal, redeems aUSDC for USDC + accrued interest.
///
///      Aave V3 Base addresses (verify before mainnet deploy):
///      - Pool: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
///      - aUSDC: set in constructor
contract StrategyAave is BaseStrategy {
    /// @notice Aave V3 Pool (IPool interface)
    address public immutable aavePool;

    /// @notice aUSDC token (interest-bearing USDC receipt)
    address public immutable aToken;

    constructor(
        address _vault,
        address _usdc,
        address _aavePool,
        address _aToken
    ) BaseStrategy(_vault, _usdc) {
        if (_aavePool == address(0) || _aToken == address(0)) revert ErrorLib.ZeroAddress();
        aavePool = _aavePool;
        aToken = _aToken;

        // Approve Aave Pool to spend USDC
        _safeApprove(_usdc, _aavePool, type(uint256).max);
    }

    /// @notice Override
    function deploy(uint256 amount) external override onlyVault whenActive returns (uint256 deployed) {
        // Aave V3 Pool.supply(asset, amount, onBehalfOf, referralCode)
        (bool success,) = aavePool.call(
            abi.encodeWithSignature(
                "supply(address,uint256,address,uint16)",
                usdc,
                amount,
                address(this), // aUSDC minted to this strategy
                0              // no referral
            )
        );
        if (!success) revert ErrorLib.CallFailed();

        _deployedAmount += amount;
        deployed = amount;
        emit Deployed(amount);
    }

    /// @notice Override
    function withdrawFromStrategy(uint256 amount) external override onlyVault returns (uint256 withdrawn) {
        // Aave V3 Pool.withdraw(asset, amount, to)
        (bool success, bytes memory data) = aavePool.call(
            abi.encodeWithSignature(
                "withdraw(address,uint256,address)",
                usdc,
                amount,
                vault // send USDC directly to vault
            )
        );
        if (!success) revert ErrorLib.CallFailed();

        withdrawn = abi.decode(data, (uint256));
        _deployedAmount = _deployedAmount > withdrawn ? _deployedAmount - withdrawn : 0;
        emit Withdrawn(withdrawn);
    }

    /// @notice Override
    function totalValue() external view override returns (uint256) {
        // aToken balance = principal + accrued interest
        return _balanceOf(aToken, address(this));
    }

    /// @notice Override
    function currentAPY() external view override returns (uint256) {
        // Fetch current liquidity rate from Aave
        // Pool.getReserveData(asset) returns ReserveData struct
        // liquidityRate is at a specific offset, in RAY (1e27)
        (bool success, bytes memory data) = aavePool.staticcall(
            abi.encodeWithSignature("getReserveData(address)", usdc)
        );

        if (!success || data.length < 64) return 0;

        // liquidityRate is the second uint256 in the struct (index 1)
        // Convert from RAY (1e27) to BPS
        uint256 liquidityRate;
        assembly {
            liquidityRate := mload(add(data, 64))
        }

        // RAY to BPS: rate * 10000 / 1e27
        return liquidityRate / 1e23;
    }

    /// @notice Override
    function availableLiquidity() external view override returns (uint256) {
        return _balanceOf(aToken, address(this));
    }

    /// @notice Override
    function harvest() external override returns (uint256 harvested) {
        // Aave auto-compounds via aToken rebasing
        // Just update deployed amount to reflect new total
        uint256 currentValue = _balanceOf(aToken, address(this));
        if (currentValue > _deployedAmount) {
            harvested = currentValue - _deployedAmount;
            _deployedAmount = currentValue;
            emit Harvested(harvested);
        }
    }

    /// @notice Override
    function emergencyWithdraw() external override onlyOwner returns (uint256 recovered) {
        uint256 balance = _balanceOf(aToken, address(this));
        if (balance == 0) return 0;

        (bool success, bytes memory data) = aavePool.call(
            abi.encodeWithSignature(
                "withdraw(address,uint256,address)",
                usdc,
                type(uint256).max, // withdraw all
                vault
            )
        );
        if (!success) revert ErrorLib.CallFailed();

        recovered = abi.decode(data, (uint256));
        _deployedAmount = 0;
        active = false;
        emit Withdrawn(recovered);
    }
}

