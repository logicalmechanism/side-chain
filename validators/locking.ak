use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/credential
use aiken/transaction/value
use side_chain/address
use side_chain/data
use side_chain/datum.{LockDatum, ReferenceDatum}
use side_chain/helpers
use side_chain/lock_redeemer.{Deposit, LockRedeemer, Remove, Update, Withdraw}

validator params(
  starter_pid: ByteArray,
  starter_tkn: ByteArray,
  ref_hash_data: Data,
) {
  fn(datum: LockDatum, redeemer: LockRedeemer, context: ScriptContext) -> Bool {
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
          // Remove the the funds from the L1 locking contract
          Remove -> {
            // owner info
            let owner_addr =
              credential.from_verification_key(datum.owner.pkh)
                |> credential.with_delegation_key(datum.owner.sc)
            // fee info
            let cashier_addr =
              credential.from_verification_key(ref_datum.cashier.pkh)
                |> credential.with_delegation_key(ref_datum.cashier.sc)
            let withdraw_fee = value.from_lovelace(ref_datum.fees.withdraw_fee)
            list.and(
              [
                // keepers or watchers must sign it
                list.or(
                  [
                    helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                    helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
                  ],
                ),
                // owner must sign it
                helpers.must_be_signed_by(tx, datum.owner.pkh),
                // owner must get the utxo back
                address.find_exact_payout(
                  owner_addr,
                  validating_value,
                  tx.outputs,
                ),
                // make sure its the correct reference contract
                ref_value_check,
                // single script input
                address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 0,
                // pay the removal service fee
                address.find_exact_payout(
                  cashier_addr,
                  withdraw_fee,
                  tx.outputs,
                ),
              ],
            )
          }
          // take some a specific value from the lock contract
          Withdraw { value } -> {
            let outbound_value = value.change
            let cont_value =
              value.add(validating_value, value.negate(outbound_value))
            // owner info
            let owner_addr =
              credential.from_verification_key(datum.owner.pkh)
                |> credential.with_delegation_key(datum.owner.sc)
            // fee info
            let cashier_addr =
              credential.from_verification_key(ref_datum.cashier.pkh)
                |> credential.with_delegation_key(ref_datum.cashier.sc)
            let withdraw_fee = value.from_lovelace(ref_datum.fees.withdraw_fee)
            expect cont_datum: LockDatum =
              helpers.get_outbound_datum(tx, validating_input)
            list.and(
              [
                // keepers or watchers must sign it
                list.or(
                  [
                    helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                    helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
                  ],
                ),
                // owner must sign it
                helpers.must_be_signed_by(tx, datum.owner.pkh),
                // make sure its the correct reference contract
                ref_value_check,
                // single script input
                address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
                // make sure value is continuing
                address.find_exact_payout(script_addr, cont_value, tx.outputs),
                // pay the removal service fee
                address.find_exact_payout(
                  cashier_addr,
                  withdraw_fee,
                  tx.outputs,
                ),
                // owner with the withdrawn value
                address.find_token_payout(
                  owner_addr,
                  outbound_value,
                  tx.outputs,
                ),
                // ownership can not change
                datum == cont_datum,
              ],
            )
          }
          // Deposit more value onto the lock contract
          Deposit { value } -> {
            let outbound_value = value.change
            let cont_value = value.add(validating_value, outbound_value)
            // fee info
            let cashier_addr =
              credential.from_verification_key(ref_datum.cashier.pkh)
                |> credential.with_delegation_key(ref_datum.cashier.sc)
            let deposit_fee = value.from_lovelace(ref_datum.fees.deposit_fee)
            expect cont_datum: LockDatum =
              helpers.get_outbound_datum(tx, validating_input)
            list.and(
              [
                // keepers or watchers must sign it
                list.or(
                  [
                    helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                    helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
                  ],
                ),
                // owner must sign it
                helpers.must_be_signed_by(tx, datum.owner.pkh),
                // make sure its the correct reference contract
                ref_value_check,
                // single script input
                address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
                // make sure value is continuing
                address.find_exact_payout(script_addr, cont_value, tx.outputs),
                // pay the removal service fee
                address.find_exact_payout(cashier_addr, deposit_fee, tx.outputs),
                // ownership can not change
                datum == cont_datum,
              ],
            )
          }
          // keeper and watcher update endpoint
          Update { value, flag } -> {
            let bank_addr =
              credential.from_script(ref_datum.contracts.bank)
                |> credential.with_delegation_script(ref_datum.contracts.stake)
            // The value going back to the contract
            let cont_value =
              if flag.increase == 0 {
                value.add(validating_value, value.change)
              } else {
                value.add(validating_value, value.negate(value.change))
              }
            expect cont_datum: LockDatum =
              helpers.get_outbound_datum(tx, validating_input)
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
                // single script input from the bank script
                address.count_script_inputs(tx.inputs, bank_addr, 0) == 1,
                // single script input from this script
                address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
                // single script output
                address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
                // make sure value is continuing
                address.find_exact_payout(script_addr, cont_value, tx.outputs),
                // ownership can not change
                datum == cont_datum,
              ],
            )
          }
        }
      }
      // anything else fails
      _ -> False
    }
  }
}
