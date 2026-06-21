import { BigDecimal, BigInt } from "@graphprotocol/graph-ts";
import { LoanCreated, LoanRepaid, LoanLiquidated } from "../../generated/AgentCredit/AgentCredit";
import { Loan, ProtocolStats } from "../../generated/schema";

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

export function handleLoanCreated(event: LoanCreated): void {
  let loan = new Loan(event.params.loanId.toString());
  loan.loanId = event.params.loanId;
  loan.agent = event.params.agent;
  loan.amount = toUSDC(event.params.amount);
  loan.collateral = toUSDC(event.params.collateral);
  loan.rateBps = event.params.rateBps;
  loan.createdAt = event.block.timestamp;
  loan.repaid = false;
  loan.liquidated = false;
  loan.save();

  let stats = getStats();
  stats.totalLoansCreated = stats.totalLoansCreated.plus(BigInt.fromI32(1));
  stats.save();
}

export function handleLoanRepaid(event: LoanRepaid): void {
  let loan = Loan.load(event.params.loanId.toString());
  if (loan) {
    loan.repaid = true;
    loan.repaidAt = event.block.timestamp;
    loan.save();
  }

  let stats = getStats();
  stats.totalLoansRepaid = stats.totalLoansRepaid.plus(BigInt.fromI32(1));
  stats.save();
}

export function handleLoanLiquidated(event: LoanLiquidated): void {
  let loan = Loan.load(event.params.loanId.toString());
  if (loan) {
    loan.liquidated = true;
    loan.repaid = true;
    loan.repaidAt = event.block.timestamp;
    loan.save();
  }

  let stats = getStats();
  stats.totalLiquidations = stats.totalLiquidations.plus(BigInt.fromI32(1));
  stats.save();
}
