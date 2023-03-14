use aiken/transaction/value.{Value}

pub type ValueData {
  change: Value,
}

pub type FlagData {
  increase: Int,
}

pub type Remove =
  Void

pub type LockRedeemer {
  Remove
  Withdraw { value: ValueData }
  Update { value: ValueData, flag: FlagData }
}
