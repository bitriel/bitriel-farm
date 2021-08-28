import { WNATIVE, FACTORY_ADDRESS, NONFUNGIBLE_POSITION_MANAGER_ADDRESSES } from "@bitriel/bitrielswap-sdk";
const BASE_FACTORY_MAP = {
    "1": "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
    "56": "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73",
}

module.exports = async function ({ getNamedAccounts, deployments, getChainId }) {
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()
    const chainId = await getChainId()

    if(BASE_FACTORY_MAP.has(chainId) && WNATIVE.has(chainId) && FACTORY_ADDRESS.has(chainId) 
    && NONFUNGIBLE_POSITION_MANAGER_ADDRESSES.has(chainId)) {
        await deploy("Migrator", {
            from: deployer,
            args: [
                BASE_FACTORY_MAP[chainId], 
                FACTORY_ADDRESS[chainId],
                WNATIVE[chainId],
                NONFUNGIBLE_POSITION_MANAGER_ADDRESSES[chainId],
                "latest_block"
            ],
            log: true,
            deterministicDeployment: false
        })
    }
}

module.exports.tags = ["Migrator"]