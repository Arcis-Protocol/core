import { BigDecimal, BigInt } from "@graphprotocol/graph-ts";
import { Deposit as DepositEvent, Withdraw as WithdrawEvent, Harvested, Paused, Unpaused } from "../../generated/ArcisVault/ArcisVault";
import { Deposit, Withdrawal, Harvest, ProtocolStats, VaultSnapshot } from "../../generated/schema";

let USDC_DECIMALS = BigDecimal.fromString("1000000");
let ZERO = BigDecimal.fromString("0");

function toUSDC(amount: BigInt): BigDecimal {
  return amount.toBigDecimal().div(USDC_DECIMALS);
}

function getStats(): ProtocolStats {
  let stats = ProtocolStats.load("protocol");
  if (!stats) {
    stats = new ProtocolStats("protocol");
    stats.totalDeposits = BigInt.fromI32(0);
    stats.totalWithdrawals = BigInt.fromI32(0);
    stats.totalHarvests = BigInt.fromI32(0);
    stats.totalLoansCreated = BigInt.fromI32(0);
    stats.totalLoansRepaid = BigInt.fromI32(0);
    stats.totalLiquidations = BigInt.fromI32(0);
    stats.cumulativeYield = ZERO;
    stats.cumulativeFees = ZERO;
  }
  return stats;
}

export function handleDeposit(event: DepositEvent): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let deposit = new Deposit(id);
  deposit.agent = event.params.agent;
  deposit.amount = toUSDC(event.params.amount);
  deposit.shares = toUSDC(event.params.shares);
  deposit.timestamp = event.block.timestamp;
  deposit.block = event.block.number;
  deposit.txHash = event.transaction.hash;
  deposit.save();

  let stats = getStats();
  stats.totalDeposits = stats.totalDeposits.plus(BigInt.fromI32(1));
  stats.save();
}

export function handleWithdraw(event: WithdrawEvent): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let withdrawal = new Withdrawal(id);
  withdrawal.agent = event.params.agent;
  withdrawal.amount = toUSDC(event.params.amount);
  withdrawal.shares = toUSDC(event.params.shares);
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.block = event.block.number;
  withdrawal.txHash = event.transaction.hash;
  withdrawal.save();

  let stats = getStats();
  stats.totalWithdrawals = stats.totalWithdrawals.plus(BigInt.fromI32(1));
  stats.save();
}

export function handleHarvest(event: Harvested): void {
  let id = event.transaction.hash.toHexString();
  let harvest = new Harvest(id);
  harvest.totalYield = toUSDC(event.params.totalYield);
  harvest.fee = toUSDC(event.params.fee);
  harvest.timestamp = event.block.timestamp;
  harvest.block = event.block.number;
  harvest.txHash = event.transaction.hash;
  harvest.save();

  let stats = getStats();
  stats.totalHarvests = stats.totalHarvests.plus(BigInt.fromI32(1));
  stats.cumulativeYield = stats.cumulativeYield.plus(harvest.totalYield);
  stats.cumulativeFees = stats.cumulativeFees.plus(harvest.fee);
  stats.save();
}

export function handlePause(event: Paused): void {
  let id = event.block.number.toString();
  let snap = new VaultSnapshot(id);
  snap.timestamp = event.block.timestamp;
  snap.block = event.block.number;
  snap.tvl = ZERO;
  snap.totalSupply = ZERO;
  snap.exchangeRate = ZERO;
  snap.reserveBalance = ZERO;
  snap.deployedBalance = ZERO;
  snap.paused = true;
  snap.save();
}

export function handleUnpause(event: Unpaused): void {
  let id = event.block.number.toString();
  let snap = new VaultSnapshot(id);
  snap.timestamp = event.block.timestamp;
  snap.block = event.block.number;
  snap.tvl = ZERO;
  snap.totalSupply = ZERO;
  snap.exchangeRate = ZERO;
  snap.reserveBalance = ZERO;
  snap.deployedBalance = ZERO;
  snap.paused = false;
  snap.save();
}
