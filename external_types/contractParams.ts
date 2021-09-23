import { BigNumberish } from 'ethers'

export module ContractParams {
  export type Timestamps = {
    startTime: number
    endTime: number
  }

  export type FarmKey = {
    pool: string
  } & Timestamps

  export type CreateFarm = FarmKey & {
    reward: BigNumberish
  }

  export type EndFarm = FarmKey
}