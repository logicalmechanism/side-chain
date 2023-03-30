use aiken/bytearray
use aiken/list
use aiken/transaction.{Input, Mint, ScriptContext}
use aiken/transaction/credential
use aiken/transaction/value.{AssetName, PolicyId, Value}
use side_chain/address
use side_chain/data
use side_chain/datum.{ReferenceDatum}
use side_chain/helpers

fn get_first_index(inputs: List<Input>) -> Int {
  let first_input =
    list.head(inputs)
  when first_input is {
    None ->
      256
    Some(input) ->
      input.output_reference.output_index
  }
}

fn get_first_ref(inputs: List<Input>) -> ByteArray {
  let first_input =
    list.head(inputs)
  when first_input is {
    None ->
      #""
    Some(input) ->
      input.output_reference.transaction_id.hash
  }
}

fn unique_token_name(id: ByteArray, idx: Int) -> ByteArray {
  let ending =
    bytearray.drop(id, n: 1)
  bytearray.push(ending, idx)
}

fn correct_mint(mint: Value, pid: PolicyId, tkn: AssetName) -> Bool {
  when
    mint
      |> value.without_lovelace()
      |> value.flatten()
  is {
    [(policy, token_name, quantity)] ->
      list.and(
        [policy == pid, token_name == tkn, quantity == 1 || quantity == -1],
      )
    _ ->
      False
  }
}

validator(starter_pid: ByteArray, starter_tkn: ByteArray, ref_hash_data: Data) {
  fn params(_redeemer: Void, context: ScriptContext) -> Bool {
    let tx =
      context.transaction
    // select the first tx hash from the input list
    let first_tx_hash =
      get_first_ref(tx.inputs)
    // index must be less than 256
    let first_index =
      get_first_index(tx.inputs)
    // prepends the index to the tx hash for a unique token name
    let tkn =
      unique_token_name(first_tx_hash, first_index)
    // get reference data
    expect ref_hash: ByteArray =
      ref_hash_data
    let ref_addr =
      credential.from_script(ref_hash)
    let ref_input =
      address.find_script_input(tx.reference_inputs, ref_addr)
    let ref_value_check =
      value.quantity_of(ref_input.output.value, starter_pid, starter_tkn) == 1
    expect ref_datum: ReferenceDatum =
      data.find_inbound_datum(ref_input)
    // mint validation
    when context.purpose is {
      Mint(own_currency_symbol) ->
        list.and(
          [
            first_index < 256,
            correct_mint(tx.mint, own_currency_symbol, tkn),
            ref_value_check,
            list.or(
              [
                helpers.valid_multisig(tx, ref_datum.keepers.pkhs, 0) >= ref_datum.keepers.threshold,
                helpers.valid_multisig(tx, ref_datum.watchers.pkhs, 0) >= ref_datum.watchers.threshold,
              ],
            ),
          ],
        )
      // Mint only
      _ ->
        False
    }
  }
}
