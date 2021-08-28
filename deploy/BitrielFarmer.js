import { WNATIVE, FACTORY_ADDRESS, NONFUNGIBLE_POSITION_MANAGER_ADDRESSES } from "@bitriel/bitrielswap-sdk";

module.exports = async function ({ getNamedAccounts, deployments, getChainId }) {
    const { deploy } = deployments
    const { deployer, dev } = await getNamedAccounts()
    const chainId = await getChainId()

    if(WNATIVE.has(chainId) && FACTORY_ADDRESS.has(chainId) 
    && NONFUNGIBLE_POSITION_MANAGER_ADDRESSES.has(chainId)) {
        const bitriel = await deployments.get("BitrielToken")
        const dayInSeconds = 60 * 60 * 24 // 86400
        const weekInDays = 7 
        const twoMonthsInDays = 2 * 30 // 60

        const bitrielFarmer = await deploy("BitrielFarmer", {
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

        const migrator = await deployments.get("Migrator");
        if(migrator.address != "0") {
            console.log("Set migrator address on BitrielFarmer contract")
            await bitrielFarmer.setMigrator(migrator.address)
        }

        if (await bitriel.owner() !== bitrielFarmer.address) {
            console.log("Transfer BitrielToken Ownership to BitrielFarmer contract for distributing stakers")
            await bitriel.transferOwnership(bitrielFarmer.address)
        }
        
          if (await bitrielFarmer.owner() !== dev) {
            console.log("Transfer BitrielFarmer Ownership to dev address for permission-actions")
            await bitrielFarmer.transferOwnership(dev)
        }
    }
}

module.exports.tags = ["BitrielFarmer"]
module.exports.dependencies = ["BitrielToken", "Migrator"]