import { FACTORY_ADDRESS, NONFUNGIBLE_POSITION_MANAGER_ADDRESSES, MIGRATOR_ADDRESS } from "@bitriel/bitrielswap-sdk"
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre;
  const { deploy } = deployments
  const { deployer, dev } = await getNamedAccounts()
  const chainId = ethers.BigNumber.from(await getChainId()).toNumber()
  
  if(chainId in FACTORY_ADDRESS && chainId in NONFUNGIBLE_POSITION_MANAGER_ADDRESSES) {
    const bitriel = await ethers.getContract("BitrielToken")
    const dayInSeconds = 60 * 60 * 24 // 86400
    const weekInDays = 7 
    const twoMonthsInDays = 2 * 30 // 60

    await deploy("BitrielFarmer", {
      from: deployer,
      args: [
        FACTORY_ADDRESS[chainId],
        NONFUNGIBLE_POSITION_MANAGER_ADDRESSES[chainId],
        bitriel.address,
        dev, 
        weekInDays * dayInSeconds,
        twoMonthsInDays * dayInSeconds
      ],
      log: true,
      deterministicDeployment: false
    })

    const bitrielFarmer = await ethers.getContract("BitrielFarmer")
    if(chainId in MIGRATOR_ADDRESS) {
      console.log("Set migrator address on BitrielFarmer contract")
      await (await bitrielFarmer.setMigrator(MIGRATOR_ADDRESS[chainId])).wait()
    }

    if (await bitriel.owner() !== bitrielFarmer.address) {
      console.log("Transfer BitrielToken Ownership to BitrielFarmer contract for distributing stakers")
      await( await bitriel.transferOwnership(bitrielFarmer.address)).wait()
    }
    
    if (await bitrielFarmer.owner() !== dev) {
      console.log("Transfer BitrielFarmer Ownership to dev address for permission-actions")
      await( await bitrielFarmer.transferOwnership(dev)).wait()
    }
  }
}

deploy.tags = ['BitrielFarmer']
deploy.dependencies = ['BitrielToken']
export default deploy