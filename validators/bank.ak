use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/credential
use aiken/transaction/value
use side_chain/address
use side_chain/bank_redeemer.{BankRedeemer, Combine, Deposit, Withdraw}
use side_chain/data
use side_chain/datum.{ReferenceDatum}
use side_chain/helpers

validator params(
  starter_pid: ByteArray,
  starter_tkn: ByteArray,
  ref_hash_data: Data,
) {
  fn(_datum: Void, redeemer: BankRedeemer, context: ScriptContext) -> Bool {
    expect ref_hash: ByteArray = ref_hash_data
    let ref_addr = credential.from_script(ref_hash)
    let tx = context.transaction
    let ref_input = address.find_script_input(tx.reference_inputs, ref_addr)
    let ref_value_check =
      value.quantity_of(ref_input.output.value, starter_pid, starter_tkn) == 1
    expect ref_datum: ReferenceDatum = data.find_inbound_datum(ref_input)
    when context.purpose is {
      Spend(output_reference) -> {
        // used by both redeemers
        let validating_input =
          helpers.get_validating_input(tx.inputs, output_reference)
        let validating_value = validating_input.output.value
        let script_addr = validating_input.output.address
        when redeemer is {
          Withdraw { value } -> {
            // THIS LINE CAUSES AN ERROR
            // let lock_addr =
            //   credential.from_script(ref_datum.contracts.lock)
            //   |> credential.with_delegation_script(ref_datum.contracts.stake)
            let cont_value =
              value.add(validating_value, value.negate(value.change))
            list.and(
              [
                // keepers or watchers must sign it
                list.or(
                  [
                    helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                    helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
                  ],
                ),
                // make sure its the correct reference contract
                ref_value_check,
                // single script input from the lock script
                // address.count_script_inputs(tx.inputs, lock_addr, 0) == 1,
                // single script input
                address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
                // make sure value is continuing
                address.find_exact_payout(script_addr, cont_value, tx.outputs),
              ],
            )
          }
          Deposit { value } -> {
            // THIS LINE CAUSES AN ERROR
            // let lock_addr =
            //   credential.from_script(ref_datum.contracts.lock)
            //   |> credential.with_delegation_script(ref_datum.contracts.stake)
            let cont_value = value.add(validating_value, value.change)
            list.and(
              [
                // keepers or watchers must sign it
                list.or(
                  [
                    helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                    helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
                  ],
                ),
                // make sure its the correct reference contract
                ref_value_check,
                // single script input from the lock script
                // address.count_script_inputs(tx.inputs, lock_addr, 0) == 1,
                // single script input
                address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
                // make sure value is continuing
                address.find_exact_payout(script_addr, cont_value, tx.outputs),
              ],
            )
          }
          Combine { utxo } -> {
            let other_output_reference = bank_redeemer.utxo_to_out_ref(utxo)
            let other_validating_input =
              helpers.get_validating_input(tx.inputs, other_output_reference)
            let other_validating_value = other_validating_input.output.value
            let cont_value = value.add(validating_value, other_validating_value)
            list.and(
              [
                // keepers or watchers must sign it
                list.or(
                  [
                    helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                    helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
                  ],
                ),
                // make sure its the correct reference contract
                ref_value_check,
                // single script input
                address.count_script_inputs(tx.inputs, script_addr, 0) == 2,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
                // make sure value is continuing
                address.find_exact_payout(script_addr, cont_value, tx.outputs),
                // cant reference yourself
                output_reference != other_output_reference,
              ],
            )
          }
        }
      }
      _ -> False
    }
  }
}
