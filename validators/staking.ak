use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction.{Publish, ScriptContext, WithdrawFrom}
use aiken/transaction/certificate.{CredentialDelegation}
use aiken/transaction/credential.{Inline, Script, ScriptCredential}
use aiken/transaction/value
use side_chain/address
use side_chain/data
use side_chain/datum.{ReferenceDatum}
use side_chain/helpers

type StakeData {
  stake_cred: Hash<Blake2b_224, Script>,
}

type WithdrawRedeemer {
  Withdraw
  Delegate(StakeData)
}

validator(starter_pid: ByteArray, starter_tkn: ByteArray, ref_hash_data: Data) {
  fn params(redeemer: WithdrawRedeemer, context: ScriptContext) -> Bool {
    expect ref_hash: ByteArray =
      ref_hash_data
    let ref_addr =
      credential.from_script(ref_hash)
    let tx =
      context.transaction
    let ref_input =
      address.find_script_input(tx.reference_inputs, ref_addr)
    let ref_value_check =
      value.quantity_of(ref_input.output.value, starter_pid, starter_tkn) == 1
    expect ref_datum: ReferenceDatum =
      data.find_inbound_datum(ref_input)
    when context.purpose is {
      // handle all withdrawals
      WithdrawFrom(stake_credential) -> {
        let reward_addr =
          credential.from_verification_key(ref_datum.staking.reward_pkh)
            |> credential.with_delegation_key(ref_datum.staking.reward_sc)
        let withdraws =
          tx.withdrawals
        let reward =
          helpers.get_reward_amt(withdraws, stake_credential)
        when redeemer is {
          Withdraw ->
            list.and(
              [
                ref_value_check,
                address.find_exact_payout(
                  reward_addr,
                  value.from_lovelace(reward),
                  tx.outputs,
                ),
              ],
            )
          _ ->
            False
        }
      }
      // handle all delegation certs
      Publish(certificate) -> {
        let pool_id =
          ref_datum.staking.pool_id
        when redeemer is {
          Delegate(sd) -> {
            let stake_credential =
              Inline(ScriptCredential(sd.stake_cred))
            let new_delegation =
              CredentialDelegation {
                delegator: stake_credential,
                delegatee: pool_id,
              }
            list.and([ref_value_check, certificate == new_delegation])
          }
          _ ->
            False
        }
      }
      _ ->
        False
    }
  }
}
