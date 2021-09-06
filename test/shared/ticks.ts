import { BigNumber } from "ethers"
import { FeeAmount, TICK_SPACINGS } from './constants'

export const getMinTick = (tickSpacing: number) => Math.ceil(-887272 / tickSpacing) * tickSpacing
export const getMaxTick = (tickSpacing: number) => Math.floor(887272 / tickSpacing) * tickSpacing
export const getMaxLiquidityPerTick = (tickSpacing: number) =>
  BigNumber.from(2)
    .pow(128)
    .sub(1)
    .div((getMaxTick(tickSpacing) - getMinTick(tickSpacing)) / tickSpacing + 1)

export const defaultTicks = (fee: FeeAmount = FeeAmount.MEDIUM) => ({
  tickLower: getMinTick(TICK_SPACINGS[fee]),
  tickUpper: getMaxTick(TICK_SPACINGS[fee]),
})

export const defaultTicksArray = (...args: any): [number, number] => {
  const { tickLower, tickUpper } = defaultTicks(...args)
  return [tickLower, tickUpper]
}