use aiken/list
use aiken/transaction.{Input, ScriptContext, Spend, Transaction}
use side_chain/address
use side_chain/datum.{ReferenceDatum}
use side_chain/helpers
use side_chain/reference_redeemer.{
  ReferenceRedeemer, UpdateCashier, UpdateContracts, UpdateFee, UpdateKeepers,
  UpdatePool, UpdateWatchers,
}

fn cont_validation(tx: Transaction, validating_input: Input) -> Bool {
  let validating_value =
    validating_input.output.value
  let script_addr =
    validating_input.output.address
  list.and(
    [
      // owner must get the utxo back
      address.find_token_payout(script_addr, validating_value, tx.outputs),
      // single script input
      address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
      // single script output
      address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
    ],
  )
}

validator {
  fn data_reference(
    datum: ReferenceDatum,
    redeemer: ReferenceRedeemer,
    context: ScriptContext,
  ) -> Bool {
    when context.purpose is {
      Spend(output_reference) -> {
        let tx =
          context.transaction
        let validating_input =
          helpers.get_validating_input(tx.inputs, output_reference)
        expect cont_datum: ReferenceDatum =
          helpers.get_outbound_datum(tx, validating_input)
        let datum_cont_check =
          when redeemer is {
            // Update the cashier address
            UpdateCashier ->
              list.and(
                [
                  datum.fees == cont_datum.fees,
                  datum.keepers == cont_datum.keepers,
                  datum.watchers == cont_datum.watchers,
                  datum.staking == cont_datum.staking,
                  datum.contracts == cont_datum.contracts,
                ],
              )
            // Update the service fee
            UpdateFee ->
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.keepers == cont_datum.keepers,
                  datum.watchers == cont_datum.watchers,
                  datum.staking == cont_datum.staking,
                  datum.contracts == cont_datum.contracts,
                ],
              )
            // Update the multisig
            UpdateKeepers -> {
              let keeper_length =
                list.length(cont_datum.keepers.pkhs)
              let threshold =
                cont_datum.keepers.threshold
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.fees == cont_datum.fees,
                  datum.watchers == cont_datum.watchers,
                  datum.staking == cont_datum.staking,
                  datum.contracts == cont_datum.contracts,
                  keeper_length >= threshold,
                  // more than not
                  2 * threshold >= 2 + keeper_length,
                ],
              )
            }
            // Update the hotkey
            UpdateWatchers -> {
              let watcher_length =
                list.length(cont_datum.watchers.pkhs)
              let threshold =
                cont_datum.watchers.threshold
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.fees == cont_datum.fees,
                  datum.keepers == cont_datum.keepers,
                  datum.staking == cont_datum.staking,
                  datum.contracts == cont_datum.contracts,
                  watcher_length >= threshold,
                  // twice as many as not
                  2 * ( watcher_length - threshold ) <= threshold,
                ],
              )
            }
            // Update stake pool info
            UpdatePool ->
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.fees == cont_datum.fees,
                  datum.keepers == cont_datum.keepers,
                  datum.watchers == cont_datum.watchers,
                  datum.contracts == cont_datum.contracts,
                ],
              )
            // Update contract hash info
            UpdateContracts ->
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.fees == cont_datum.fees,
                  datum.keepers == cont_datum.keepers,
                  datum.watchers == cont_datum.watchers,
                  datum.staking == cont_datum.staking,
                ],
              )
          }
        list.and(
          [
            // validating value conts to script addr
            cont_validation(tx, validating_input),
            // only keepers can update the data
            helpers.valid_multisig(tx, datum.keepers.pkhs, 0) >= datum.keepers.threshold,
            // the cont datum check
            datum_cont_check,
          ],
        )
      }
      _ ->
        False
    }
  }
}
