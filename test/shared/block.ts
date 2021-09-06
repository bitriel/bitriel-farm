import { ethers } from "hardhat"
import { BigNumber } from "ethers"

export async function advanceBlock() {
  return ethers.provider.send("evm_mine", [])
}

export async function advanceTime(time: number) {
  return ethers.provider.send("evm_increaseTime", [time])
}

export async function advanceBlockTo(blockNumber: number) {
  for(let i = await ethers.provider.getBlockNumber(); i < blockNumber; i++) {
    await advanceBlock()
  }
}

export async function increaseTime(value: BigNumber) {
  await ethers.provider.send("evm_increaseTime", [value.toNumber()])
  await advanceBlock()
}

export async function latestBlockTimestamp(): Promise<BigNumber> {
  const block = await ethers.provider.getBlock("latest")
  return BigNumber.from(block.timestamp)
}

export async function advanceTimeAndBlock(time: number) {
  await advanceTime(time)
  await advanceBlock()
}

export const duration = {
  seconds: (val: any) => BigNumber.from(val),
  minutes: (val: any) => BigNumber.from(val).mul(duration.seconds(60)),
  hours: (val: any) => BigNumber.from(val).mul(duration.minutes(60)),
  days: (val: any) => BigNumber.from(val).mul(duration.hours(24)),
  weeks: (val: any) => BigNumber.from(val).mul(duration.days(7)),
  months: (val: any) => BigNumber.from(val).mul(duration.days(30)),
  years: (val: any) => BigNumber.from(val).mul(duration.days(365))
}