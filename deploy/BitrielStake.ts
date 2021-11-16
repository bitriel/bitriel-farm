import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { BTR_ADDRESS } from '@bitriel/bitrielswap-sdk'

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = ethers.BigNumber.from(await getChainId()).toNumber()
  
  if (chainId in BTR_ADDRESS)
    await deploy("BitrielStake", {
      from: deployer,
      args: [BTR_ADDRESS[chainId]],
      log: true,
      deterministicDeployment: false
    })
}

deploy.tags = ['BitrielStake']
export default deploy