import { BigNumber, Wallet } from 'ethers'
import { FeeAmount } from '../shared/constants'
import { MockProvider } from 'ethereum-waffle'
import {
  blockTimestamp,
  BNe18,
  getCurrentTick,
  maxGas,
  MaxUint256,
  encodePath,
  arrayWrap,
  getMinTick,
  getMaxTick,
  BN,
} from '../shared/index'
import _ from 'lodash'
import {
  Erc20Mock,
  INonfungiblePositionManager,
  BitrielFarmer,
  IBitrielPool,
  BitrielToken,
  FarmIdMock,
} from '../../types'
import { HelperTypes } from './types'
import { ActorFixture } from '../shared/actors'
import { mintPosition } from '../shared/fixtures'
import { IBitrielSwapRouter } from '../shared/external/types/IBitrielSwapRouter'
import { ethers } from 'hardhat'
import { ContractParams } from '../shared/external/types/contractParams'
import { TestContext } from '../shared/types'

/**
 * HelperCommands is a utility that abstracts away lower-level ethereum details
 * so that we can focus on core business logic.
 *
 * Each helper function should be a `HelperTypes.CommandFunction`
 */
export class HelperCommands {
  actors: ActorFixture
  provider: MockProvider
  farmer: BitrielFarmer
  bitriel: BitrielToken
  nft: INonfungiblePositionManager
  router: IBitrielSwapRouter
  pool: IBitrielPool
  farmIdMock: FarmIdMock

  DEFAULT_FARMING_DURATION = 2_000
  DEFAULT_CLAIM_DURATION = 1_000
  DEFAULT_LP_AMOUNT = BNe18(10)
  DEFAULT_FEE_AMOUNT = FeeAmount.MEDIUM

  constructor({
    provider,
    farmer,
    bitriel,
    nft,
    router,
    pool,
    actors,
    farmIdMock,
  }: {
    actors: ActorFixture
    provider: MockProvider
    farmer: BitrielFarmer
    bitriel: BitrielToken
    nft: INonfungiblePositionManager
    router: IBitrielSwapRouter
    pool: IBitrielPool
    farmIdMock: FarmIdMock
  }) {
    this.actors = actors
    this.provider = provider
    this.farmer = farmer
    this.bitriel = bitriel
    this.nft = nft
    this.router = router
    this.pool = pool
    this.farmIdMock = farmIdMock
  }

  static fromTestContext = (context: TestContext, actors: ActorFixture, provider: MockProvider): HelperCommands => {
    return new HelperCommands({
      actors,
      provider,
      nft: context.nft,
      router: context.router,
      farmer: context.farmer,
      bitriel: context.yieldToken,
      pool: context.poolObj,
      farmIdMock: context.farmIdMock,
    })
  }

  /**
   * Creates a yield farming incentive owned by `farmCreator` for `totalReward` of `rewardToken`
   *
   * Side-Effects:
   *  Transfers `rewardToken` to `farmCreator` if they do not have sufficient blaance.
   */
  createFarmFlow: HelperTypes.CreateFarm.Command = async (params) => {
    const { startTime } = params
    const endTime = params.endTime || startTime + this.DEFAULT_FARMING_DURATION

    const farmCreator = this.actors.farmCreator()
    const times = {
      startTime,
      endTime,
    }
    const bal = await this.bitriel.balanceOf(farmCreator.address)

    if (bal < params.totalReward) {
      await this.bitriel.transfer(farmCreator.address, params.totalReward)
    }

    await this.bitriel.connect(farmCreator).approve(this.farmer.address, params.totalReward)

    await this.farmer.connect(farmCreator).createFarm(
      {
        pool: params.poolAddress,
        ...times,
      },
      params.totalReward
    )

    return {
      ..._.pick(params, ['poolAddress', 'totalReward']),
      ...times,
    }
  }

  /**
   * params.lp mints an NFT backed by a certain amount of `params.tokensToStake`.
   *
   * Side-Effects:
   *  Funds `params.lp` with enough `params.tokensToStake` if they do not have enough.
   *  Handles the ERC20 and ERC721 permits.
   */
  mintDepositStakeFlow: HelperTypes.MintDepositStake.Command = async (params) => {
    // Make sure LP has enough balance
    const bal0 = await params.tokensToStake[0].balanceOf(params.lp.address)
    if (bal0 < params.amountsToStake[0])
      await params.tokensToStake[0]
        // .connect(tokensOwner)
        .transfer(params.lp.address, params.amountsToStake[0])

    const bal1 = await params.tokensToStake[1].balanceOf(params.lp.address)
    if (bal1 < params.amountsToStake[1])
      await params.tokensToStake[1]
        // .connect(tokensOwner)
        .transfer(params.lp.address, params.amountsToStake[1])

    // Make sure LP has authorized NFT to withdraw
    await params.tokensToStake[0].connect(params.lp).approve(this.nft.address, params.amountsToStake[0])
    await params.tokensToStake[1].connect(params.lp).approve(this.nft.address, params.amountsToStake[1])

    // The LP mints their NFT
    const tokenId = await mintPosition(this.nft.connect(params.lp), {
      token0: params.tokensToStake[0].address,
      token1: params.tokensToStake[1].address,
      fee: this.DEFAULT_FEE_AMOUNT,
      tickLower: params.ticks[0],
      tickUpper: params.ticks[1],
      recipient: params.lp.address,
      amount0Desired: params.amountsToStake[0],
      amount1Desired: params.amountsToStake[1],
      amount0Min: 0,
      amount1Min: 0,
      deadline: (await blockTimestamp()) + 1000,
    })

    // Make sure LP has authorized staker
    await params.tokensToStake[0].connect(params.lp).approve(this.farmer.address, params.amountsToStake[0])
    await params.tokensToStake[1].connect(params.lp).approve(this.farmer.address, params.amountsToStake[1])

    // The LP approves and stakes their NFT
    await this.nft.connect(params.lp).approve(this.farmer.address, tokenId)
    await this.nft
      .connect(params.lp)
      ['safeTransferFrom(address,address,uint256)'](params.lp.address, this.farmer.address, tokenId)
    await this.farmer
      .connect(params.lp)
      .stakeToken(farmResultToStakeAdapter(params.createFarmResult), tokenId)

    const stakedAt = await blockTimestamp()

    return {
      tokenId,
      stakedAt,
      lp: params.lp,
    }
  }

  depositFlow: HelperTypes.Deposit.Command = async (params) => {
    await this.nft.connect(params.lp).approve(this.farmer.address, params.tokenId)

    await this.nft
      .connect(params.lp)
      ['safeTransferFrom(address,address,uint256)'](params.lp.address, this.farmer.address, params.tokenId)
  }

  mintFlow: HelperTypes.Mint.Command = async (params) => {
    const fee = params.fee || FeeAmount.MEDIUM
    const e20h = new ERC20Helper()

    const amount0Desired = params.amounts ? params.amounts[0] : this.DEFAULT_LP_AMOUNT

    await e20h.ensureBalancesAndApprovals(params.lp, params.tokens[0], amount0Desired, this.nft.address)

    const amount1Desired = params.amounts ? params.amounts[1] : this.DEFAULT_LP_AMOUNT

    await e20h.ensureBalancesAndApprovals(params.lp, params.tokens[1], amount1Desired, this.nft.address)

    const tokenId = await mintPosition(this.nft.connect(params.lp), {
      token0: params.tokens[0].address,
      token1: params.tokens[1].address,
      fee,
      tickLower: params.tickLower || getMinTick(fee),
      tickUpper: params.tickUpper || getMaxTick(fee),
      recipient: params.lp.address,
      amount0Desired,
      amount1Desired,
      amount0Min: 0,
      amount1Min: 0,
      deadline: (await blockTimestamp()) + 1000,
    })

    return { tokenId, lp: params.lp }
  }

  unstakeCollectBurnFlow: HelperTypes.UnstakeCollectBurn.Command = async (params) => {
    await this.farmer.connect(params.lp).unstakeToken(
      farmResultToStakeAdapter(params.createFarmResult),
      params.tokenId,

      maxGas
    )

    const unstakedAt = await blockTimestamp()

    await this.farmer
      .connect(params.lp)
      .harvest(params.lp.address, BN('0'))

    await this.farmer.connect(params.lp).withdrawToken(params.tokenId, params.lp.address, '0x', maxGas)

    const { liquidity } = await this.nft.connect(params.lp).positions(params.tokenId)

    await this.nft.connect(params.lp).decreaseLiquidity(
      {
        tokenId: params.tokenId,
        liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: (await blockTimestamp()) + 1000,
      },
      maxGas
    )

    const { tokensOwed0, tokensOwed1 } = await this.nft.connect(params.lp).positions(params.tokenId)

    await this.nft.connect(params.lp).collect(
      {
        tokenId: params.tokenId,
        recipient: params.lp.address,
        amount0Max: tokensOwed0,
        amount1Max: tokensOwed1,
      },
      maxGas
    )

    await this.nft.connect(params.lp).burn(params.tokenId, maxGas)

    const balance = await this.bitriel.connect(params.lp).balanceOf(params.lp.address)

    return {
      balance,
      unstakedAt,
    }
  }

  endFarmFlow: HelperTypes.EndFarm.Command = async (params) => {
    const farmCreator = this.actors.farmCreator()

    const receipt = await (
      await this.farmer.connect(farmCreator).endIncentive(
        _.assign({}, _.pick(params.createFarmResult, ['startTime', 'endTime']), {
          pool: params.createFarmResult.poolAddress,
        })
      )
    ).wait()

    const transferFilter = this.bitriel.filters.Transfer(this.farmer.address, farmCreator.address, null)
    const transferTopic = this.bitriel.interface.getEventTopic('Transfer')
    const logItem = receipt.logs.find((log: any) => log.topics.includes(transferTopic))
    const events = await this.bitriel.queryFilter(transferFilter, logItem?.blockHash)
    let amountTransferred: BigNumber

    if (events.length === 1) {
      amountTransferred = events[0].args[2]
    } else {
      throw new Error('Could not find transfer event')
    }

    return {
      amountReturnedToCreator: amountTransferred,
    }
  }

  getIncentiveId: HelperTypes.GetFarmId.Command = async (params) => {
    return this.farmIdMock.compute({
      pool: params.poolAddress,
      startTime: params.startTime,
      endTime: params.endTime,
    })
  }

  makeTickGoFlow: HelperTypes.MakeTickGo.Command = async (params) => {
    // await tok0.transfer(trader0.address, BNe18(2).mul(params.numberOfTrades))
    // await tok0
    //   .connect(trader0)
    //   .approve(router.address, BNe18(2).mul(params.numberOfTrades))

    const MAKE_TICK_GO_UP = params.direction === 'up'
    const actor = params.trader || this.actors.traderUser0()

    const isDone = (tick: number | undefined) => {
      if (!params.desiredValue) {
        return true
      } else if (!tick) {
        return false
      } else if (MAKE_TICK_GO_UP) {
        return tick > params.desiredValue
      } else {
        return tick < params.desiredValue
      }
    }

    const [tok0Address, tok1Address] = await Promise.all([
      this.pool.connect(actor).token0(),
      this.pool.connect(actor).token1(),
    ])
    const erc20 = await ethers.getContractFactory('ERC20Mock')

    const tok0 = erc20.attach(tok0Address) as Erc20Mock
    const tok1 = erc20.attach(tok1Address) as Erc20Mock

    const doTrade = async () => {
      /* If we want to push price down, we need to increase tok0.
         If we want to push price up, we need to increase tok1 */

      const amountIn = BNe18(1)

      const erc20Helper = new ERC20Helper()
      await erc20Helper.ensureBalancesAndApprovals(actor, [tok0, tok1], amountIn, this.router.address)

      const path = encodePath(MAKE_TICK_GO_UP ? [tok1Address, tok0Address] : [tok0Address, tok1Address], [
        FeeAmount.MEDIUM,
      ])

      await this.router.connect(actor).exactInput(
        {
          recipient: actor.address,
          deadline: MaxUint256,
          path,
          amountIn: amountIn.div(10),
          amountOutMinimum: 0,
        },
        maxGas
      )

      return await getCurrentTick(this.pool.connect(actor))
    }

    let currentTick = await doTrade()

    while (!isDone(currentTick)) {
      currentTick = await doTrade()
    }

    return { currentTick }
  }
}

export class ERC20Helper {
  ensureBalancesAndApprovals = async (
    actor: Wallet,
    tokens: Erc20Mock | Array<Erc20Mock>,
    balance: BigNumber,
    spender?: string
  ) => {
    for (let token of arrayWrap(tokens)) {
      await this.ensureBalance(actor, token, balance)
      if (spender) {
        await this.ensureApproval(actor, token, balance, spender)
      }
    }
  }

  ensureBalance = async (actor: Wallet, token: Erc20Mock, balance: BigNumber) => {
    const currentBalance = await token.balanceOf(actor.address)
    if (currentBalance.lt(balance)) {
      await token
        // .connect(this.actors.tokensOwner())
        .transfer(actor.address, balance.sub(currentBalance))
    }

    // if (spender) {
    //   await this.ensureApproval(actor, token, balance, spender)
    // }

    return await token.balanceOf(actor.address)
  }

  ensureApproval = async (actor: Wallet, token: Erc20Mock, balance: BigNumber, spender: string) => {
    const currentAllowance = await token.allowance(actor.address, actor.address)
    if (currentAllowance.lt(balance)) {
      await token.connect(actor).approve(spender, balance)
    }
  }
}

type FarmAdapterFunc = (params: HelperTypes.CreateFarm.Result) => ContractParams.FarmKey

export const farmResultToStakeAdapter: FarmAdapterFunc = (params) => ({
  pool: params.poolAddress,
  startTime: params.startTime,
  endTime: params.endTime,
})