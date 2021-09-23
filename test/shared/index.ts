export * from './fixtures'
export * from './actors'
export * from './logging'
export * from './ticks'

import { FeeAmount } from './constants'
import { BigNumber, BigNumberish, Contract, ContractTransaction } from 'ethers'
import { TransactionReceipt, TransactionResponse } from '@ethersproject/abstract-provider'
import { constants } from 'ethers'
import bn from 'bignumber.js'
import { expect, use } from 'chai'
import { solidity } from 'ethereum-waffle'
import { jestSnapshotPlugin } from 'mocha-chai-jest-snapshot'
import { IBitrielPool, ERC20Mock } from '../../types'
import { isArray, isString } from 'lodash'
import { ethers, waffle } from 'hardhat'

export const { MaxUint256 } = constants

export const blockTimestamp = async () => {
  const block = await waffle.provider.getBlock('latest')
  if (!block) {
    throw new Error('null block returned from provider')
  }
  return block.timestamp
}

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 })

use(solidity)
use(jestSnapshotPlugin())

export { expect }
export const BN = BigNumber.from
export const BNe = (n: BigNumberish, exponent: BigNumberish) => BN(n).mul(BN(10).pow(exponent))
export const BNe18 = (n: BigNumberish) => BNe(n, 18)
export const divE18 = (n: BigNumber) => n.div(BNe18('1')).toNumber()
export const ratioE18 = (a: BigNumber, b: BigNumber) => (divE18(a) / divE18(b)).toFixed(2)

const bigNumberSum = (arr: Array<BigNumber>) => arr.reduce((acc, item) => acc.add(item), BN('0'))
export const bnSum = bigNumberSum
export { BigNumber, BigNumberish } from 'ethers'

export function compareToken(a: { address: string }, b: { address: string }): -1 | 1 {
  return a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1
}

export function sortedTokens(
  a: { address: string },
  b: { address: string }
): [typeof a, typeof b] | [typeof b, typeof a] {
  return compareToken(a, b) < 0 ? [a, b] : [b, a]
}

// returns the sqrt price as a 64x96
export const encodePriceSqrt = (reserve1: BigNumberish, reserve0: BigNumberish): BigNumber => {
  return BigNumber.from(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString()
  )
}

export async function snapshotGasCost(
  x:
    | TransactionResponse
    | Promise<TransactionResponse>
    | ContractTransaction
    | Promise<ContractTransaction>
    | TransactionReceipt
    | Promise<BigNumber>
    | BigNumber
    | Contract
    | Promise<Contract>
): Promise<void> {
  const resolved = await x
  if ('deployTransaction' in resolved) {
    const receipt = await resolved.deployTransaction.wait()
    expect(receipt.gasUsed.toNumber()).toMatchSnapshot()
  } else if ('wait' in resolved) {
    const waited = await resolved.wait()
    expect(waited.gasUsed.toNumber()).toMatchSnapshot()
  } else if (BigNumber.isBigNumber(resolved)) {
    expect(resolved.toNumber()).toMatchSnapshot()
  }
}

export function encodePath(path: string[], fees: FeeAmount[]): string {
  if (path.length != fees.length + 1) {
    throw new Error('path/fee lengths do not match')
  }

  let encoded = '0x'
  for (let i = 0; i < fees.length; i++) {
    // 20 byte encoding of the address
    encoded += path[i].slice(2)
    // 3 byte encoding of the fee
    encoded += fees[i].toString(16).padStart(2 * 3, '0')
  }
  // encode the final token
  encoded += path[path.length - 1].slice(2)

  return encoded.toLowerCase()
}

export const MIN_SQRT_RATIO = BigNumber.from('4295128739')
export const MAX_SQRT_RATIO = BigNumber.from('1461446703485210103287273052203988822378723970342')

export const MAX_GAS_LIMIT = 12_450_000
export const maxGas = {
  gasLimit: MAX_GAS_LIMIT,
}

export const getSlot0 = async (pool: IBitrielPool) => {
  if (!pool.signer) {
    throw new Error('Cannot getSlot0 without a signer')
  }
  return await pool.slot0()
}

// This is currently lpUser0 but can be called from anybody.
export const getCurrentTick = async (pool: IBitrielPool): Promise<number> => (await getSlot0(pool)).tick

export const arrayWrap = (x: any) => {
  if (!isArray(x)) {
    return [x]
  }
  return x
}

export const erc20Wrap = async (x: string | ERC20Mock): Promise<ERC20Mock> => {
  if (isString(x)) {
    const factory = await ethers.getContractFactory('ERC20Mock')
    return factory.attach(x.toString()) as ERC20Mock
  }
  return x as ERC20Mock
}

export const makeTimestamps = (n: number, duration: number = 1_000) => ({
  startTime: n + 100,
  endTime: n + 100 + duration,
})