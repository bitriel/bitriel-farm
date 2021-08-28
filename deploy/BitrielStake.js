module.exports = async function ({ getNamedAccounts, deployments }) {
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

module.exports.tags = ["BitrielStake"]
module.exports.dependencies = ["BitrielToken"]