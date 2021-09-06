import { waffle } from 'hardhat'
import { BitrielFixtureType } from './fixtures'

export type LoadFixtureFunction = ReturnType<typeof waffle.createFixtureLoader>

export type TestContext = BitrielFixtureType & {
  subject?: Function
}