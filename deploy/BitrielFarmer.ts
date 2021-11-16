import { FACTORY_ADDRESS, NONFUNGIBLE_POSITION_MANAGER_ADDRESSES, MIGRATOR_ADDRESS, BTR_ADDRESS } from "@bitriel/bitrielswap-sdk"
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre;
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = ethers.BigNumber.from(await getChainId()).toNumber()
  
  if(chainId in FACTORY_ADDRESS && chainId in BTR_ADDRESS
    && chainId in NONFUNGIBLE_POSITION_MANAGER_ADDRESSES) {
    await deploy("BitrielFarmer", {
      from: deployer,
      args: [
        FACTORY_ADDRESS[chainId],
        NONFUNGIBLE_POSITION_MANAGER_ADDRESSES[chainId],
        BTR_ADDRESS[chainId],
        "200000000000000000", // 0.2 BTRs
        "14170000"
      ],
      log: true
    })

    const bitrielFarmer = await ethers.getContract("BitrielFarmer")
    if(chainId in MIGRATOR_ADDRESS) {
      console.log("Set migrator address on BitrielFarmer contract")
      await (await bitrielFarmer.setMigrator(MIGRATOR_ADDRESS[chainId])).wait()
    }

    // const bitriel = await ethers.getContractAt('BitrielToken', BTR_ADDRESS[chainId])
    // const bitrielOwner = await bitriel.owner();
    // if (bitrielOwner == deployer && bitrielOwner !== bitrielFarmer.address) {
    //   console.log("Transfer BitrielToken Ownership to BitrielFarmer contract for distributing stakers")
    //   await( await bitriel.transferOwnership(bitrielFarmer.address)).wait()
    // }
  }
}

deploy.tags = ['BitrielFarmer']
export default deploy