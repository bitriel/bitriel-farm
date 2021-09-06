import { BigNumber, Wallet } from 'ethers'
import { Erc20Mock } from '../../types'
import { FeeAmount } from '../shared/constants'

export module HelperTypes {
  export type CommandFunction<Input, Output> = (input: Input) => Promise<Output>

  export module CreateFarm {
    export type Args = {
      poolAddress: string
      startTime: number
      endTime?: number
      totalReward: BigNumber
    }
    export type Result = {
      poolAddress: string
      totalReward: BigNumber
      startTime: number
      endTime: number
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module MintDepositStake {
    export type Args = {
      lp: Wallet
      tokensToStake: [Erc20Mock, Erc20Mock]
      amountsToStake: [BigNumber, BigNumber]
      ticks: [number, number]
      createFarmResult: CreateFarm.Result
    }

    export type Result = {
      lp: Wallet
      tokenId: string
      stakedAt: number
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module Mint {
    type Args = {
      lp: Wallet
      tokens: [Erc20Mock, Erc20Mock]
      amounts?: [BigNumber, BigNumber]
      fee?: FeeAmount
      tickLower?: number
      tickUpper?: number
    }

    export type Result = {
      lp: Wallet
      tokenId: string
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module Deposit {
    type Args = {
      lp: Wallet
      tokenId: string
    }
    type Result = void
    export type Command = CommandFunction<Args, Result>
  }

  export module UnstakeCollectBurn {
    type Args = {
      lp: Wallet
      tokenId: string
      createFarmResult: CreateFarm.Result
    }
    export type Result = {
      balance: BigNumber
      unstakedAt: number
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module EndFarm {
    type Args = {
      createFarmResult: CreateFarm.Result
    }

    type Result = {
      amountReturnedToCreator: BigNumber
    }

    export type Command = CommandFunction<Args, Result>
  }

  export module MakeTickGo {
    type Args = {
      direction: 'up' | 'down'
      desiredValue?: number
      trader?: Wallet
    }

    type Result = { currentTick: number }

    export type Command = CommandFunction<Args, Result>
  }

  export module GetFarmId {
    type Args = CreateFarm.Result

    // Returns the farmId as bytes32
    type Result = string

    export type Command = CommandFunction<Args, Result>
  }
}
