import { Fixture } from 'ethereum-waffle'
import { constants } from 'ethers'
import { ethers, waffle } from 'hardhat'

import BitrielPool from '@bitriel/bitrielswap-core/build/contracts/BitrielPool.json'
import BitrielFactoryJson from '@bitriel/bitrielswap-core/build/contracts/BitrielFactory.json'
import NFTDescriptorJson from '@bitriel/bitrielswap-periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json'
import NonfungiblePositionManagerJson from '@bitriel/bitrielswap-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json'
import NonfungibleTokenPositionDescriptor from '@bitriel/bitrielswap-periphery/artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json'
import BitrielSwapRouter from '@bitriel/bitrielswap-periphery/artifacts/contracts/BitrielSwapRouter.sol/BitrielSwapRouter.json'
import WNATIVE from './external/wnative.json'

import { linkLibraries } from './linkLibraries'
import { BigNumber, encodePriceSqrt, MAX_GAS_LIMIT } from '../shared'
import { FeeAmount } from './constants'
import { ActorFixture } from './actors'

import { IBitrielSwapRouter } from '../../external_types/IBitrielSwapRouter'
import { Iwnative as IWNATIVE } from '../../external_types/Iwnative'
import { NftDescriptor as NFTDescriptor } from '../../external_types/NftDescriptor'
import {
  BitrielFarmer,
  ERC20Mock,
  INonfungiblePositionManager,
  IBitrielFactory,
  IBitrielPool,
  FarmIdMock,
  BitrielToken,
} from '../../types'

type WNATIVEFixture = { wnative: IWNATIVE }

export const wnativeFixture: Fixture<WNATIVEFixture> = async ([wallet]) => {
  const wnative = (await waffle.deployContract(wallet, {
    bytecode: WNATIVE.bytecode,
    abi: WNATIVE.abi,
  })) as IWNATIVE

  return { wnative }
}

const factoryFixture: Fixture<IBitrielFactory> = async ([wallet]) => {
  return (await waffle.deployContract(wallet, {
    bytecode: BitrielFactoryJson.bytecode,
    abi: BitrielFactoryJson.abi,
  })) as IBitrielFactory
}

export const swapRouterFixture: Fixture<{
  wnative: IWNATIVE
  factory: IBitrielFactory
  router: IBitrielSwapRouter
}> = async ([wallet], provider) => {
  const { wnative } = await wnativeFixture([wallet], provider)
  const factory = await factoryFixture([wallet], provider)

  const router = ((await waffle.deployContract(
    wallet,
    {
      bytecode: BitrielSwapRouter.bytecode,
      abi: BitrielSwapRouter.abi,
    },
    [factory.address, wnative.address]
  )) as unknown) as IBitrielSwapRouter

  return { factory, wnative, router }
}

const nftDescriptorLibraryFixture: Fixture<NFTDescriptor> = async ([wallet]) => {
  return (await waffle.deployContract(wallet, {
    bytecode: NFTDescriptorJson.bytecode,
    abi: NFTDescriptorJson.abi,
  })) as NFTDescriptor
}

type BitrielFactoryFixture = {
  wnative: IWNATIVE
  factory: IBitrielFactory
  router: IBitrielSwapRouter
  nft: INonfungiblePositionManager
  tokens: [ERC20Mock, ERC20Mock, ERC20Mock]
}

export const bitrielFactoryFixture: Fixture<BitrielFactoryFixture> = async (wallets, provider) => {
  const { factory, wnative, router } = await swapRouterFixture(wallets, provider)
  const tokenFactory = await ethers.getContractFactory('ERC20Mock')
  const tokens: [ERC20Mock, ERC20Mock, ERC20Mock] = [
    (await tokenFactory.deploy("Token1", "TK1", constants.MaxUint256.div(2))) as ERC20Mock,
    (await tokenFactory.deploy("Token2", "TK2", constants.MaxUint256.div(2))) as ERC20Mock,
    (await tokenFactory.deploy("Token3", "TK3", constants.MaxUint256.div(2))) as ERC20Mock,
  ]

  const nftDescriptorLibrary = await nftDescriptorLibraryFixture(wallets, provider)
  const linkedBytecode = linkLibraries(
    {
      bytecode: NonfungibleTokenPositionDescriptor.bytecode,
      linkReferences: {
        'NFTDescriptor.sol': {
          NFTDescriptor: [
            {
              length: 20,
              start: 1261,
            },
          ],
        },
      },
    },
    {
      NFTDescriptor: nftDescriptorLibrary.address,
    }
  )
  const positionDescriptor = await waffle.deployContract(
    wallets[0],
    {
      bytecode: linkedBytecode,
      abi: NonfungibleTokenPositionDescriptor.abi,
    },
    [tokens[0].address]
  )

  const nftFactory = new ethers.ContractFactory(
    NonfungiblePositionManagerJson.abi,
    NonfungiblePositionManagerJson.bytecode,
    wallets[0]
  )
  const nft = (await nftFactory.deploy(
    factory.address,
    wnative.address,
    positionDescriptor.address
  )) as INonfungiblePositionManager

  tokens.sort((a, b) => (a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1))

  return {
    wnative,
    factory,
    router,
    tokens,
    nft,
  }
}

export const mintPosition = async (
  nft: INonfungiblePositionManager,
  mintParams: {
    token0: string
    token1: string
    fee: FeeAmount
    tickLower: number
    tickUpper: number
    recipient: string
    amount0Desired: any
    amount1Desired: any
    amount0Min: number
    amount1Min: number
    deadline: number
  }
): Promise<string> => {
  const transferFilter = nft.filters.Transfer(null, null, null)
  const transferTopic = nft.interface.getEventTopic('Transfer')

  let tokenId: BigNumber | undefined

  const receipt = await (
    await nft.mint(
      {
        token0: mintParams.token0,
        token1: mintParams.token1,
        fee: mintParams.fee,
        tickLower: mintParams.tickLower,
        tickUpper: mintParams.tickUpper,
        recipient: mintParams.recipient,
        amount0Desired: mintParams.amount0Desired,
        amount1Desired: mintParams.amount1Desired,
        amount0Min: mintParams.amount0Min,
        amount1Min: mintParams.amount1Min,
        deadline: mintParams.deadline,
      },
      {
        gasLimit: MAX_GAS_LIMIT,
      }
    )
  ).wait()

  for (let i = 0; i < receipt.logs.length; i++) {
    const log = receipt.logs[i]
    if (log.address === nft.address && log.topics.includes(transferTopic)) {
      // for some reason log.data is 0x so this hack just re-fetches it
      const events = await nft.queryFilter(transferFilter, log.blockHash)
      if (events.length === 1) {
        tokenId = events[0].args?.tokenId
      }
      break
    }
  }

  if (tokenId === undefined) {
    throw 'could not find tokenId after mint'
  } else {
    return tokenId.toString()
  }
}

export type BitrielFixtureType = {
  factory: IBitrielFactory
  fee: FeeAmount
  nft: INonfungiblePositionManager
  pool01: string
  pool12: string
  poolObj: IBitrielPool
  router: IBitrielSwapRouter
  farmer: BitrielFarmer
  yieldToken: BitrielToken
  farmIdMock: FarmIdMock
  tokens: [ERC20Mock, ERC20Mock, ERC20Mock]
  token0: ERC20Mock
  token1: ERC20Mock
}
export const bitrielFixture: Fixture<BitrielFixtureType> = async (wallets, provider) => {
  const { tokens, nft, factory, router } = await bitrielFactoryFixture(wallets, provider)
  const signer = new ActorFixture(wallets, provider).farmerDeployer()

  const farmerFactory = await ethers.getContractFactory('BitrielFarmer', signer)
  const farmer = (await farmerFactory.deploy(factory.address, nft.address, 2 ** 32, 2 ** 32)) as BitrielFarmer
  const yieldTokenFactory = await ethers.getContractFactory('BitrielToken')
  const yieldToken = (await yieldTokenFactory.deploy()) as BitrielToken
  const farmIdMockFactory = await ethers.getContractFactory('FarmIdMock', signer)
  const farmIdMock = (await farmIdMockFactory.deploy()) as FarmIdMock

  for (const token of tokens) {
    await token.approve(nft.address, constants.MaxUint256)
  }

  const fee = FeeAmount.MEDIUM
  await nft.createAndInitializePoolIfNecessary(tokens[0].address, tokens[1].address, fee, encodePriceSqrt(1, 1))

  await nft.createAndInitializePoolIfNecessary(tokens[1].address, tokens[2].address, fee, encodePriceSqrt(1, 1))

  const pool01 = await factory.getPool(tokens[0].address, tokens[1].address, fee)

  const pool12 = await factory.getPool(tokens[1].address, tokens[2].address, fee)

  const poolObj = poolFactory.attach(pool01) as IBitrielPool

  return {
    nft,
    router,
    tokens,
    farmer,
    yieldToken,
    farmIdMock,
    factory,
    pool01,
    pool12,
    fee,
    poolObj,
    token0: tokens[0],
    token1: tokens[1],
  }
}

export const poolFactory = new ethers.ContractFactory(BitrielPool.abi, BitrielPool.bytecode)