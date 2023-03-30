use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use side_chain/address
use side_chain/datum.{ReferenceDatum}
use side_chain/helpers
use side_chain/reference_redeemer.{
  ReferenceRedeemer, UpdateCashier, UpdateContracts, UpdateFee, UpdateKeepers,
  UpdatePool, UpdateWatchers,
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
        let validating_value =
          validating_input.output.value
        let script_addr =
          validating_input.output.address
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
              let l =
                list.length(cont_datum.keepers.pkhs)
              let t =
                cont_datum.keepers.threshold
              let a =
                1
              let b =
                2
              let c =
                1
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.fees == cont_datum.fees,
                  datum.watchers == cont_datum.watchers,
                  datum.staking == cont_datum.staking,
                  datum.contracts == cont_datum.contracts,
                  l >= t,
                  a * l + b * c <= b * t,
                ],
              )
            }
            // Update the hotkey
            UpdateWatchers -> {
              let l =
                list.length(cont_datum.watchers.pkhs)
              let t =
                cont_datum.watchers.threshold
              let a =
                3
              let b =
                4
              let c =
                1
              list.and(
                [
                  datum.cashier == cont_datum.cashier,
                  datum.fees == cont_datum.fees,
                  datum.keepers == cont_datum.keepers,
                  datum.staking == cont_datum.staking,
                  datum.contracts == cont_datum.contracts,
                  l >= t,
                  a * l + b * c <= b * t,
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
            // owner must get the utxo back
            address.find_token_payout(script_addr, validating_value, tx.outputs),
            // single script input
            address.count_script_inputs(tx.inputs, script_addr, 0) == 1,
            // single script output
            address.count_script_outputs(tx.outputs, script_addr, 0) == 1,
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
