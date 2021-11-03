// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMulticall.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

interface IBitrielFarmerV3 is IERC721Receiver, IMulticall {

  /// @notice The Uniswap V3 Factory
  function factory() external view returns (IBitrielFactory);

  /// @notice The nonfungible position manager with which this staking contract is compatible
  function nonfungiblePositionManager() external view returns (INonfungiblePositionManager);
}