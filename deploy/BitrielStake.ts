import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'

const deploy: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  
  const bitriel = await deployments.get("BitrielToken")
  await deploy("BitrielStake", {
    from: deployer,
    args: [bitriel.address],
    log: true,
    deterministicDeployment: false
  })
}

deploy.tags = ['BitrielStake']
deploy.dependencies = ['BitrielToken']
export default deploy