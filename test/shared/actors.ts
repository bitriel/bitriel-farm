import { MockProvider } from 'ethereum-waffle'
import { Wallet } from 'ethers'

export const WALLET_USER_INDEXES = {
  ROOT: 0,
  FARMER_DEPLOYER: 1,
  WNATIVE_OWNER: 2,
  TOKENS_OWNER: 3,
  LP_USER_0: 4,
  LP_USER_1: 5,
  LP_USER_2: 6,
  TRADER_USER_0: 7,
  TRADER_USER_1: 8,
  TRADER_USER_2: 9,
  FARM_CREATOR: 10,
}

export class ActorFixture {
  wallets: Array<Wallet>
  provider: MockProvider

  constructor(wallets: Array<Wallet>, provider: MockProvider) {
    this.wallets = wallets
    this.provider = provider
  }

  rootUser() {
    return this._getActor(WALLET_USER_INDEXES.ROOT)
  }

  /* EOA that will deploy the farmer contract */
  farmerDeployer() {
    return this._getActor(WALLET_USER_INDEXES.FARMER_DEPLOYER)
  }
  /* EOA that mints and transfers wnative to test accounts */
  wnativeOwner() {
    return this._getActor(WALLET_USER_INDEXES.WNATIVE_OWNER)
  }

  /* EOA that mints all the Test ERC20s we use */
  tokensOwner() {
    return this._getActor(WALLET_USER_INDEXES.TOKENS_OWNER)
  }

  /* These EOAs provide liquidity in pools and collect swap fees and yield farming */
  lpUser0() {
    return this._getActor(WALLET_USER_INDEXES.LP_USER_0)
  }

  lpUser1() {
    return this._getActor(WALLET_USER_INDEXES.LP_USER_1)
  }

  lpUser2() {
    return this._getActor(WALLET_USER_INDEXES.LP_USER_2)
  }

  lpUsers() {
    return [this.lpUser0(), this.lpUser1(), this.lpUser2()]
  }

  /* These EOAs trade in the BitrielPools and incur fees */
  traderUser0() {
    return this._getActor(WALLET_USER_INDEXES.TRADER_USER_0)
  }

  traderUser1() {
    return this._getActor(WALLET_USER_INDEXES.TRADER_USER_1)
  }

  traderUser2() {
    return this._getActor(WALLET_USER_INDEXES.TRADER_USER_2)
  }

  farmCreator() {
    return this._getActor(WALLET_USER_INDEXES.FARM_CREATOR)
  }

  private _getActor(index: number): Wallet {
    /* Actual logic for fetching the wallet */
    if (!index) {
      throw new Error(`Invalid index: ${index}`)
    }
    const account = this.wallets[index]
    if (!account) {
      throw new Error(`Account ID ${index} could not be found`)
    }
    return account
  }
}