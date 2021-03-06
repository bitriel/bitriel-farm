import { constants, Wallet } from 'ethers'
import { waffle } from 'hardhat'
import { FeeAmount, TICK_SPACINGS } from "./shared/constants"
import { TestContext, LoadFixtureFunction } from './shared/types'
import { duration as Duration } from './shared/block'
import { ERC20Mock } from '../types'
import {
  BigNumber,
  blockTimestamp,
  BN,
  BNe18,
  expect,
  getMaxTick,
  getMinTick,
  bitrielFixture,
  log,
  ratioE18,
  bnSum,
  getCurrentTick,
  BNe,
  mintPosition,
} from './shared'
import { createTimeMachine } from './shared/time'
import { ERC20Helper, HelperCommands, farmResultToStakeAdapter } from './helpers'
import { ActorFixture } from './shared/actors'
import { Fixture } from 'ethereum-waffle'
import { HelperTypes } from './helpers/types'

let loadFixture: LoadFixtureFunction

describe("BitrielFarmer", () => {
  const provider = waffle.provider
  const wallets = provider.getWallets()
  const Time = createTimeMachine(provider)
  const actors = new ActorFixture(wallets, provider)
  const e20h = new ERC20Helper()

  before('create fixture loader', async () => {
    loadFixture = waffle.createFixtureLoader(wallets, waffle.provider)
  })

  describe('there are three LPs in the same range', async () => {
    type TestSubject = {
      stakes: Array<HelperTypes.MintDepositStake.Result>
      createFarmResult: HelperTypes.CreateFarm.Result
      helpers: HelperCommands
      context: TestContext
    }
    let subject: TestSubject

    const totalReward = BNe18(3_000)
    const duration = Duration.days(30).toNumber()
    const ticksToStake: [number, number] = [
      getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
      getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM]),
    ]
    const amountsToStake: [BigNumber, BigNumber] = [BNe18(1_000), BNe18(1_000)]

    const scenario: Fixture<TestSubject> = async (_wallets, _provider) => {
      const context = await bitrielFixture(_wallets, _provider)
      const epoch = await blockTimestamp()

      const {
        tokens: [token0, token1],
      } = context
      const helpers = HelperCommands.fromTestContext(context, actors, provider)

      const tokensToStake: [ERC20Mock, ERC20Mock] = [token0, token1]

      const startTime = epoch + 1_000
      const endTime = startTime + duration

      const createFarmResult = await helpers.createFarmFlow({
        startTime,
        endTime,
        poolAddress: context.pool01,
        totalReward,
      })

      const params = {
        tokensToStake,
        amountsToStake,
        createFarmResult,
        ticks: ticksToStake,
      }

      await Time.set(startTime + 1)

      const stakes = await Promise.all(
        actors.lpUsers().map((lp) =>
          helpers.mintDepositStakeFlow({
            ...params,
            lp,
          })
        )
      )

      return {
        context,
        stakes,
        helpers,
        createFarmResult,
      }
    }

    beforeEach('load fixture', async () => {
      subject = await loadFixture(scenario)
    })

    describe('who all stake the entire time ', () => {
      it('allows them all to withdraw at the end', async () => {
        const { helpers, createFarmResult } = subject

        await Time.setAndMine(createFarmResult.endTime + 1)

        // Sanity check: make sure we go past the incentive end time.
        expect(await blockTimestamp(), 'test setup: must be run after start time').to.be.gte(
          createFarmResult.endTime
        )

        // Everyone pulls their liquidity at the same time
        const unstakes = await Promise.all(
          subject.stakes.map(({ lp, tokenId }) =>
            helpers.unstakeCollectBurnFlow({
              lp,
              tokenId,
              createFarmResult,
            })
          )
        )
        const rewardsEarned = bnSum(unstakes.map((o) => o.balance))
        log.debug('Total rewards ', rewardsEarned.toString())

        expect(rewardsEarned).to.eq(totalReward)
      })

      describe('time goes past the farm was end', () => {
        it('still allows an LP to unstake if they have not already', async () => {
          const {
            createFarmResult,
            context: { nft, farmer },
            stakes,
          } = subject

          // Simple wrapper functions since we will call these several times
          const actions = {
            doUnstake: (params: HelperTypes.MintDepositStake.Result) =>
              farmer
                .connect(params.lp)
                .unstake(params.tokenId),

            doWithdraw: (params: HelperTypes.MintDepositStake.Result) =>
              farmer.connect(params.lp).withdraw(params.tokenId, params.lp.address, '0x'),

            doHarvest: (params: HelperTypes.MintDepositStake.Result) =>
              farmer
                .connect(params.lp)
                .harvest(params.lp.address, BN('0')),
          }

          await Time.set(createFarmResult.endTime + 1)

          // First make sure it is still owned by the farmer
          expect(await nft.ownerOf(stakes[0].tokenId)).to.eq(farmer.address)

          // It allows the token to be unstaked the first time
          await expect(actions.doUnstake(stakes[0]))
            .to.emit(farmer, 'TokenUnstaked')
            .withArgs(stakes[0].tokenId)

          // It does not allow them to harvest yield (since we're past end time)
          await actions.doHarvest(stakes[0])

          // Owner is still the farmer
          expect(await nft.ownerOf(stakes[0].tokenId)).to.eq(farmer.address)

          // Now withdraw it
          await expect(actions.doWithdraw(stakes[0]))
            .to.emit(farmer, 'DepositTransferred')
            .withArgs(stakes[0].tokenId, stakes[0].lp.address, constants.AddressZero)

          // Owner is now the LP
          expect(await nft.ownerOf(stakes[0].tokenId)).to.eq(stakes[0].lp.address)
        })

        it('does not allow the LP to harvest yield', async () => {})
      })
    })

    describe('when one LP unstakes halfway through', () => {
      it('only gives them one sixth the total reward', async () => {
        const { helpers, createFarmResult, stakes } = subject
        const { startTime, endTime } = createFarmResult

        // Halfway through, lp0 decides they want out. Pauvre lp0.
        await Time.setAndMine(startTime + duration / 2)

        const [lpUser0] = actors.lpUsers()
        let unstakes: Array<HelperTypes.UnstakeCollectBurn.Result> = []

        unstakes.push(
          await helpers.unstakeCollectBurnFlow({
            lp: lpUser0,
            tokenId: stakes[0].tokenId,
            createFarmResult: subject.createFarmResult,
          })
        )

        /*
         * totalReward is 3000e18
         *
         * This user contributed 1/3 of the total liquidity (amountsToStake = 1000e18)
         * for the first half of the duration, then unstaked.
         *
         * So that's (1/3)*(1/2)*3000e18 = ~500e18
         */
        expect(unstakes[0].balance).to.beWithin(BNe(1, 15), BN('499989197530864021534'))

        // Now the other two LPs hold off till the end and unstake
        await Time.setAndMine(endTime + 1)
        const otherUnstakes = await Promise.all(
          stakes.slice(1).map(({ lp, tokenId }) =>
            helpers.unstakeCollectBurnFlow({
              lp,
              tokenId,
              createFarmResult,
            })
          )
        )
        unstakes.push(...otherUnstakes)

        /* lpUser{1,2} should each have 5/12 of the total rewards.
          (1/3 * 1/2) from before lpUser0 withdrew
          (1/2 * 1/2) from after lpUser0. */

        expect(ratioE18(unstakes[1].balance, unstakes[0].balance)).to.eq('2.50')
        expect(ratioE18(unstakes[2].balance, unstakes[1].balance)).to.eq('1.00')

        // All should add up to totalReward
        expect(bnSum(unstakes.map((u) => u.balance))).to.eq(totalReward)
      })

      describe('and then restakes at the 3/4 mark', () => {
        it('rewards based on their staked time', async () => {
          const {
            helpers,
            createFarmResult,
            stakes,
            context: {
              tokens: [token0, token1],
            },
          } = subject
          const { startTime, endTime } = createFarmResult

          // Halfway through, lp0 decides they want out. Pauvre lp0.
          const [lpUser0] = actors.lpUsers()

          // lpUser0 unstakes at the halfway mark
          await Time.set(startTime + duration / 2)

          await helpers.unstakeCollectBurnFlow({
            lp: lpUser0,
            tokenId: stakes[0].tokenId,
            createFarmResult: subject.createFarmResult,
          })

          // lpUser0 then restakes at the 3/4 mark
          await Time.set(startTime + (3 / 4) * duration)
          const tokensToStake: [ERC20Mock, ERC20Mock] = [token0, token1]

          await e20h.ensureBalancesAndApprovals(
            lpUser0,
            [token0, token1],
            amountsToStake[0],
            subject.context.router.address
          )

          const restake = await helpers.mintDepositStakeFlow({
            lp: lpUser0,
            createFarmResult,
            tokensToStake,
            amountsToStake,
            ticks: ticksToStake,
          })

          await Time.set(endTime + 1)

          const { balance: lpUser0Balance } = await helpers.unstakeCollectBurnFlow({
            lp: lpUser0,
            tokenId: restake.tokenId,
            createFarmResult,
          })

          expect(lpUser0Balance).to.beWithin(BNe(1, 12), BN('749985223767771705507'))
        })
      })
    })

    describe('when another LP starts staking halfway through', () => {
      describe('and provides half the liquidity', () => {
        it('gives them a smaller share of the reward', async () => {
          const { helpers, createFarmResult, stakes, context } = subject
          const { startTime, endTime } = createFarmResult

          // Halfway through, lp3 decides they want in. Good for them.
          await Time.set(startTime + duration / 2)

          const lpUser3 = actors.traderUser2()
          const tokensToStake: [ERC20Mock, ERC20Mock] = [context.tokens[0], context.tokens[1]]

          const extraStake = await helpers.mintDepositStakeFlow({
            tokensToStake,
            amountsToStake: amountsToStake.map((a) => a.div(2)) as [BigNumber, BigNumber],
            createFarmResult,
            ticks: ticksToStake,
            lp: lpUser3,
          })

          // Now, go to the end and get rewards
          await Time.setAndMine(endTime + 1)

          const unstakes = await Promise.all(
            stakes.concat(extraStake).map(({ lp, tokenId }) =>
              helpers.unstakeCollectBurnFlow({
                lp,
                tokenId,
                createFarmResult,
              })
            )
          )

          expect(ratioE18(unstakes[2].balance, unstakes[3].balance)).to.eq('4.34')
          expect(bnSum(unstakes.map((u) => u.balance))).to.eq(totalReward)
        })
      })
    })

    describe('when another LP adds liquidity but does not stake', () => {
      it('still changes the reward amounts', async () => {
        const { helpers, createFarmResult, context, stakes } = subject

        // Go halfway through
        await Time.set(createFarmResult.startTime + duration / 2)

        const lpUser3 = actors.traderUser2()

        // The non-staking user will deposit 25x the liquidity as the others
        const balanceDeposited = amountsToStake[0]

        // Someone starts staking
        await e20h.ensureBalancesAndApprovals(
          lpUser3,
          [context.token0, context.token1],
          balanceDeposited,
          context.nft.address
        )

        await mintPosition(context.nft.connect(lpUser3), {
          token0: context.token0.address,
          token1: context.token1.address,
          fee: FeeAmount.MEDIUM,
          tickLower: ticksToStake[0],
          tickUpper: ticksToStake[1],
          recipient: lpUser3.address,
          amount0Desired: balanceDeposited,
          amount1Desired: balanceDeposited,
          amount0Min: 0,
          amount1Min: 0,
          deadline: (await blockTimestamp()) + 1000,
        })

        await Time.set(createFarmResult.endTime + 1)

        const unstakes = await Promise.all(
          stakes.map(({ lp, tokenId }) =>
            helpers.unstakeCollectBurnFlow({
              lp,
              tokenId,
              createFarmResult,
            })
          )
        )

        /**
         * The reward distributed to LPs should be:
         *
         * totalReward: is 3_000e18
         *
         * Farm Start -> Halfway Through:
         * 3 LPs, all staking the same amount. Each LP gets roughly (totalReward/2) * (1/3)
         */
        const firstHalfRewards = totalReward.div(BN('2'))

        /**
         * Halfway Through -> Farm End:
         * 4 LPs, all providing the same liquidity. Only 3 LPs are staking, so they should
         * each get 1/4 the liquidity for that time. So That's 1/4 * 1/2 * 3_000e18 per staked LP.
         * */
        const secondHalfRewards = totalReward.div(BN('2')).mul('3').div('4')
        const rewardsEarned = bnSum(unstakes.map((s) => s.balance))
        // expect(rewardsEarned).to.be.closeTo(
        //   // @ts-ignore
        //   firstHalfRewards.add(secondHalfRewards),
        //   BNe(5, 16)
        // )

        expect(rewardsEarned).to.eq(totalReward)
      })
    })
  })

  describe('when there are different ranges staked', () => {
    type TestSubject = {
      createFarmResult: HelperTypes.CreateFarm.Result
      helpers: HelperCommands
      context: TestContext
    }
    let subject: TestSubject

    const totalReward = BNe18(3_000)
    const duration = Duration.days(100).toNumber()
    const baseAmount = BNe18(2)

    const scenario: Fixture<TestSubject> = async (_wallets, _provider) => {
      const context = await bitrielFixture(_wallets, _provider)

      const helpers = HelperCommands.fromTestContext(context, new ActorFixture(_wallets, _provider), _provider)

      const epoch = await blockTimestamp()
      const startTime = epoch + 1_000
      const endTime = startTime + duration

      const createFarmResult = await helpers.createFarmFlow({
        startTime,
        endTime,
        poolAddress: context.pool01,
        totalReward,
      })

      return {
        context,
        helpers,
        createFarmResult,
      }
    }

    beforeEach('load fixture', async () => {
      subject = await loadFixture(scenario)
    })

    it('rewards based on how long they are in range', async () => {
      const { helpers, context, createFarmResult } = subject
      type Position = {
        lp: Wallet
        amounts: [BigNumber, BigNumber]
        ticks: [number, number]
      }

      let midpoint = await getCurrentTick(context.poolObj.connect(actors.lpUser0()))

      const positions: Array<Position> = [
        // lpUser0 stakes 2e18 from min-0
        {
          lp: actors.lpUser0(),
          amounts: [baseAmount, baseAmount],
          ticks: [getMinTick(TICK_SPACINGS[FeeAmount.MEDIUM]), midpoint],
        },
        // lpUser1 stakes 4e18 from 0-max
        {
          lp: actors.lpUser1(),
          amounts: [baseAmount.mul(2), baseAmount.mul(2)],
          ticks: [midpoint, getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])],
        },
        // lpUser2 stakes 8e18 from 0-max
        {
          lp: actors.lpUser2(),
          amounts: [baseAmount.mul(4), baseAmount.mul(4)],
          ticks: [midpoint, getMaxTick(TICK_SPACINGS[FeeAmount.MEDIUM])],
        },
      ]

      const tokensToStake: [ERC20Mock, ERC20Mock] = [context.tokens[0], context.tokens[1]]

      Time.set(createFarmResult.startTime + 1)
      const stakes = await Promise.all(
        positions.map((p) =>
          helpers.mintDepositStakeFlow({
            lp: p.lp,
            tokensToStake,
            ticks: p.ticks,
            amountsToStake: p.amounts,
            createFarmResult,
          })
        )
      )

      const trader = actors.traderUser0()

      await helpers.makeTickGoFlow({
        trader,
        direction: 'up',
        desiredValue: midpoint + 10,
      })

      // Go halfway through
      await Time.set(createFarmResult.startTime + duration / 2)

      await helpers.makeTickGoFlow({
        trader,
        direction: 'down',
        desiredValue: midpoint - 10,
      })

      await Time.set(createFarmResult.endTime + 1)

      /* lp0 provided all the liquidity for the second half of the duration. */
      const { balance: lp0Balance } = await helpers.unstakeCollectBurnFlow({
        lp: stakes[0].lp,
        tokenId: stakes[0].tokenId,
        createFarmResult,
      })

      expect(lp0Balance).to.eq(BN('1499999131944544913825'))

      /* lp{1,2} provided liquidity for the first half of the duration.
      lp2 provided twice as much liquidity as lp1. */
      const { balance: lp1Balance } = await helpers.unstakeCollectBurnFlow({
        lp: stakes[1].lp,
        tokenId: stakes[1].tokenId,
        createFarmResult,
      })

      const { balance: lp2Balance } = await helpers.unstakeCollectBurnFlow({
        lp: stakes[2].lp,
        tokenId: stakes[2].tokenId,
        createFarmResult,
      })

      expect(lp1Balance).to.eq(BN('499996238431987566881'))
      expect(lp2Balance).to.eq(BN('999990162082783775671'))

      await expect(
        helpers.unstakeCollectBurnFlow({
          lp: stakes[2].lp,
          tokenId: stakes[2].tokenId,
          createFarmResult,
        })
      ).to.be.reverted
    })
  })
})