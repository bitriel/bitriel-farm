import { FACTORY_ADDRESS, NONFUNGIBLE_POSITION_MANAGER_ADDRESSES, MIGRATOR_ADDRESS } from "@bitriel/bitrielswap-sdk"
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre;
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = ethers.BigNumber.from(await getChainId()).toNumber()
  
  if(chainId in FACTORY_ADDRESS && chainId in NONFUNGIBLE_POSITION_MANAGER_ADDRESSES) {
    const bitriel = await ethers.getContract("BitrielToken")

    await deploy("BitrielFarmerV2", {
      from: deployer,
      args: [
        FACTORY_ADDRESS[chainId],
        NONFUNGIBLE_POSITION_MANAGER_ADDRESSES[chainId],
        bitriel.address,
        "200000000000000000", // 0.2 BTRs
        "13813500"
      ],
      log: true
    })

    const bitrielFarmer = await ethers.getContract("BitrielFarmerV2")
    if(chainId in MIGRATOR_ADDRESS) {
      console.log("Set migrator address on BitrielFarmer contract")
      await (await bitrielFarmer.setMigrator(MIGRATOR_ADDRESS[chainId])).wait()
    }

    if (await bitriel.owner() !== bitrielFarmer.address) {
      console.log("Transfer BitrielToken Ownership to BitrielFarmer contract for distributing stakers")
      await( await bitriel.transferOwnership(bitrielFarmer.address)).wait()
    }
  }
}

deploy.tags = ['BitrielFarmerV2']
deploy.dependencies = ['BitrielToken']
export default deploy