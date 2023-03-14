use aiken/transaction.{OutputReference, TransactionId}
use aiken/transaction/value.{Value}

pub type ValueData {
  change: Value,
}

pub type UTxO {
  tx: ByteArray,
  idx: Int,
}

pub fn utxo_to_out_ref(utxo: UTxO) -> OutputReference {
  let tx_id = TransactionId { hash: utxo.tx }
  OutputReference { transaction_id: tx_id, output_index: utxo.idx }
}

pub type BankRedeemer {
  Withdraw { value: ValueData }
  Deposit { value: ValueData }
  Combine { utxo: UTxO }
}
