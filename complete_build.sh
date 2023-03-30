#!/bin/bash
set -e

function cat_file_or_empty() {
  if [ -e "$1" ]; then
    cat "$1"
  else
    echo ""
  fi
}

# build out the entire script
echo -e "\033[1;34m Building Contracts \033[0m"
aiken build

# start with data reference
echo -e "\033[1;33m Convert Reference Contract \033[0m"
aiken blueprint convert -v data_reference.data_reference > contracts/reference_contract.plutus
cardano-cli transaction policyid --script-file contracts/reference_contract.plutus > hashes/reference_contract.hash

# reference hash
ref=$(cat hashes/reference_contract.hash)

# the reference token
pid=$(jq -r '.starterPid' start_info.json)
tkn=$(jq -r '.starterTkn' start_info.json)

# cbor representation
ref_cbor=$(python ./convert_to_cbor.py ${ref})
pid_cbor=$(python ./convert_to_cbor.py ${pid})
tkn_cbor=$(python ./convert_to_cbor.py ${tkn})

# The pool to stake at
poolId=$(jq -r '.poolId' start_info.json)

# build the stake contract
echo -e "\033[1;33m Convert Stake Contract \033[0m"
aiken blueprint apply --validator staking.params . "(con data #${pid_cbor})"
aiken blueprint apply --validator staking.params . "(con data #${tkn_cbor})"
aiken blueprint apply --validator staking.params . "(con data #${ref_cbor})"
aiken blueprint convert -v staking.params > contracts/stake_contract.plutus
cardano-cli transaction policyid --script-file contracts/stake_contract.plutus > hashes/stake.hash
cardano-cli stake-address registration-certificate --stake-script-file contracts/stake_contract.plutus --out-file certs/stake.cert
cardano-cli stake-address delegation-certificate --stake-script-file contracts/stake_contract.plutus --stake-pool-id ${poolId} --out-file certs/deleg.cert

# build the bank contract
echo -e "\033[1;33m Convert Bank Contract \033[0m"
aiken blueprint apply --validator bank.params . "(con data #${pid_cbor})"
aiken blueprint apply --validator bank.params . "(con data #${tkn_cbor})"
aiken blueprint apply --validator bank.params . "(con data #${ref_cbor})"
aiken blueprint convert -v bank.params > contracts/bank_contract.plutus
cardano-cli transaction policyid --script-file contracts/bank_contract.plutus > hashes/bank.hash

# build the minter contract
echo -e "\033[1;33m Convert Minter Contract \033[0m"
aiken blueprint apply --validator controlled_minter.params . "(con data #${pid_cbor})"
aiken blueprint apply --validator controlled_minter.params . "(con data #${tkn_cbor})"
aiken blueprint apply --validator controlled_minter.params . "(con data #${ref_cbor})"
aiken blueprint convert -v controlled_minter.params > contracts/controlled_minter_contract.plutus
cardano-cli transaction policyid --script-file contracts/controlled_minter_contract.plutus > hashes/policy.hash

#build the lock contract
echo -e "\033[1;33m Convert Locking Contract \033[0m"
aiken blueprint apply --validator locking.params . "(con data #${pid_cbor})"
aiken blueprint apply --validator locking.params . "(con data #${tkn_cbor})"
aiken blueprint apply --validator locking.params . "(con data #${ref_cbor})"
aiken blueprint convert -v locking.params > contracts/locking_contract.plutus
cardano-cli transaction policyid --script-file contracts/locking_contract.plutus > hashes/locking.hash

###############DATUM AND REDEEMER STUFF
echo -e "\033[1;33m Updating Reference Datum \033[0m"
# # build out the reference datum data
caPkh=$(cat_file_or_empty ./scripts/wallets/cashier-wallet/payment.hash)
caSc=$(cat_file_or_empty ./scripts/wallets/cashier-wallet/stake.hash)
# service fee
withdrawFee=2000000
depositFee=2000000
# keepers
pkh1=$(cat_file_or_empty ./scripts/wallets/keeper1-wallet/payment.hash)
pkh2=$(cat_file_or_empty ./scripts/wallets/keeper2-wallet/payment.hash)
pkh3=$(cat_file_or_empty ./scripts/wallets/keeper3-wallet/payment.hash)
pkhs="[{\"bytes\": \"$pkh1\"}, {\"bytes\": \"$pkh2\"}, {\"bytes\": \"$pkh3\"}]"
thres=2
# pool stuff
rewardPkh=$(cat_file_or_empty ./scripts/wallets/reward-wallet/payment.hash)
rewardSc=$(cat_file_or_empty ./scripts/wallets/reward-wallet/stake.hash)
# validator hashes
bankHash=$(cat hashes/bank.hash)
lockHash=$(cat hashes/locking.hash)
stakeHash=$(cat hashes/stake.hash)
#
jq \
--arg caPkh "$caPkh" \
--arg caSc "$caSc" \
--argjson withdrawFee "$withdrawFee" \
--argjson depositFee "$depositFee" \
--argjson pkhs "$pkhs" \
--argjson thres "$thres" \
--arg poolId "$poolId" \
--arg rewardPkh "$rewardPkh" \
--arg rewardSc "$rewardSc" \
--arg bankHash "$bankHash" \
--arg lockHash "$lockHash" \
--arg stakeHash "$stakeHash" \
'.fields[0].fields[0].bytes=$caPkh | 
.fields[0].fields[1].bytes=$caSc | 
.fields[1].fields[0].int=$withdrawFee | 
.fields[1].fields[1].int=$depositFee | 
.fields[2].fields[0].list |= ($pkhs | .[0:length]) | 
.fields[2].fields[1].int=$thres | 
.fields[4].fields[0].bytes=$poolId |
.fields[4].fields[1].bytes=$rewardPkh |
.fields[4].fields[2].bytes=$rewardSc |
.fields[5].fields[0].bytes=$bankHash |
.fields[5].fields[1].bytes=$lockHash |
.fields[5].fields[2].bytes=$stakeHash
' \
./scripts/data/reference/reference-datum.json | sponge ./scripts/data/reference/reference-datum.json

# Update Staking Redeemer
echo -e "\033[1;33m Updating Stake Redeemer \033[0m"
stakeHash=$(cat_file_or_empty ./hashes/stake.hash)
jq \
--arg stakeHash "$stakeHash" \
'.fields[0].fields[0].bytes=$stakeHash' \
./scripts/data/staking/delegate-redeemer.json | sponge ./scripts/data/staking/delegate-redeemer.json