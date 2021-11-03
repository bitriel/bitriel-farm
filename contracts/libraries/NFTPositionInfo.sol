// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@bitriel/bitrielswap-periphery/contracts/libraries/PoolAddress.sol';

/// @notice Encapsulates the logic for getting info about a NFT token ID
library NFTPositionInfo {
    /// @param factory The address of the BitrielSwap Factory used in computing the pool address
    /// @param nonfungiblePositionManager The address of the nonfungible position manager to query
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    /// @return pool The address of the BitrielSwap pool
    /// @return tickLower The lower tick of the BitrielSwap position
    /// @return tickUpper The upper tick of the BitrielSwap position
    /// @return liquidity The amount of liquidity staked
    function getPositionInfo(
        IBitrielFactory factory,
        INonfungiblePositionManager nonfungiblePositionManager,
        uint256 tokenId
    ) internal view returns (
        address pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) {
        address token0;
        address token1;
        uint24 fee;
        (, , token0, token1, fee, tickLower, tickUpper, liquidity, , , , ) = nonfungiblePositionManager.positions(
            tokenId
        );

        pool = PoolAddress.computeAddress(
            address(factory),
            PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
        );
    }
}