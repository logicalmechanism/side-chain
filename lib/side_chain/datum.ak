use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{PoolId, Script, VerificationKey}

pub type PublicKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type ValidatorHash =
  Hash<Blake2b_224, Script>

pub type AddressData {
  pkh: PublicKeyHash,
  sc: PublicKeyHash,
}

// side chain fee info
pub type ServiceFeeData {
  service_fee: Int,
}

// keepers are like admins
pub type KeeperData {
  pkhs: List<PublicKeyHash>,
  threshold: Int,
}

// watchers are trusted
pub type WatcherData {
  pkhs: List<PublicKeyHash>,
  threshold: Int,
}

// staking info
pub type StakePoolData {
  pool_id: PoolId,
  reward_pkh: PublicKeyHash,
  reward_sc: PublicKeyHash,
}

// contract validator hashes
pub type ContractHashData {
  bank: ValidatorHash,
  lock: ValidatorHash,
  stake: ValidatorHash,
}

pub type ReferenceDatum {
  cashier: AddressData,
  fees: ServiceFeeData,
  keepers: KeeperData,
  watchers: WatcherData,
  staking: StakePoolData,
  contracts: ContractHashData,
}

pub type LockDatum {
  owner: AddressData,
}
