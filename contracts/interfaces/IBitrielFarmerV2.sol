// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMigrator.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMulticall.sol';

import '../BitrielToken.sol';

interface IBitrielFarmerV2 is IERC721Receiver, IMulticall {
  /// @notice The BitrielSwap Factory
  function factory() external view returns (IBitrielFactory);

  /// @notice The nonfungible position manager
  function nonfungiblePositionManager() external view returns (INonfungiblePositionManager);

  /// @notice The migrator to perform LP token migration
  function migrator() external view returns(IMigrator);

  /// @notice The token use to reward users for paticipantion and governance token
  function bitriel() external view returns(BitrielToken);

  /// @notice Represents a farming incentive
  /// @param pool The pool contract address 
  /// @return allocPoint How many allocation points assigned to this pool. BTRs to distribute per block
  /// @return lastRewardBlock Last block number that BTRs distribution occurs
  /// @return accBTRPerShareX12 Accumulated BTRs per share, times 1e12.
  /// @return totalLiquidity Total liquidity has been staked in the farm
  function farms(address pool) external view 
    returns(
      uint256 allocPoint,
      uint256 lastRewardBlock, 
      uint256 accBTRPerShareX12,
      uint128 totalLiquidity
    );

  /// @notice Represents a list of staked token of the farming pool incentive
  /// @param pool The liquidity pool contract address
  /// @param user The user who paticipated in the farming pool 
  /// @return tokens a list of staked token ID
  function userTokens(address pool, address user) external view returns(uint256[] memory tokens);
  
  /// @notice Returns information about a deposited NFT
  /// @param tokenId The unique identifier of an LP token
  /// @return owner The owner of the deposited NFT
  /// @return tickLower The lower tick of the range
  /// @return tickUpper The upper tick of the range
  function deposits(uint256 tokenId) external view
    returns(
      address owner,
      int24 tickLower,
      int24 tickUpper
    );

  /// @notice Returns information about a staked liquidity NFT
  /// @param tokenId The ID of the staked token
  /// @return liquidity The amount of liquidity in the NFT
  /// @return rewardClaimed The amount of reward has been claimed
  function stakes(uint256 tokenId) external view
    returns(
      uint128 liquidity,
      uint256 rewardClaimed
    );

  /// @notice Creates a new farming pool to incentivise LP providers
  /// @param pool The pool contract address
  /// @param allocPoint The allocation points for the farm
  function createFarm(address pool, uint256 allocPoint) external;

  /// @notice Set allocation points for existing farming pool
  /// @param pool The pool contract address
  /// @param allocPoint The new allocation points for the farm
  function setFarm(address pool, uint256 allocPoint) external;

  /// @notice Get the amount of reward ready for harvest from staking the `tokenId`
  /// @param tokenId The unique identifier of an LP token
  /// @return amount The amount of reward
  function rewardToken(uint256 tokenId) external view returns(uint256 amount);

  /// @notice Get the amount of reward ready for harvest of `user` staking inside the farming pool
  /// @param pool The pool contract 
  /// @param user The user address
  /// @return amount The amount of reward
  function reward(address pool, address user) external view returns(uint256 amount);

  /// @notice Update reward variables of the farming pool to be up-to-date.
  /// @param pool The pool contract address
  function updateFarm(address pool) external;

  /// @notice Stakes a deposited LP token
  /// @param tokenId The ID of the token to stake
  function stake(uint256 tokenId) external;

  /// @notice Transfers amount of reward ready to harvest from the contract to the recipient `to` of `tokenId`
  /// @param tokenId The ID of the token has been staked
  /// @param to The address where claimed rewards will be sent to
  /// @return amount The amount of reward tokens claimed
  function claimToken(uint256 tokenId, address to) external returns(uint256 amount);

  /// @notice Transfers amount of reward ready to harvest from the contract to the recipient `to`
  /// @param pool The pool contract address
  /// @param to The address where claimed rewards will be sent to
  /// @return amount The amount of reward tokens claimed
  function claim(address pool, address to) external returns(uint256 amount);

  /// @notice Unstake and Withdraws a LP token `tokenId` from this contract to the owner
  /// @param tokenId The unique identifier of a LP token
  /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
  function withdrawToken(uint256 tokenId, bytes memory data) external;

  /// @notice Unstake and Withdraws a LP token `tokenId` from this contract to the owner
  /// @param pool The pool contract address
  /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
  function withdraw(address pool, bytes memory data) external;

  /// @notice Set migrator contract address
  /// @param _migrator The migrator address
  function setMigrator(IMigrator _migrator) external;

  /// @notice Migrate LP token migration
  /// @param params The parameters for migrator contract
  /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
  function migrate(IMigrator.MigrateParams calldata params, bytes memory data) external;

  /// @notice Bonus multiplier over the given `from` to `to` block.
  /// @param from The from block number
  /// @param to The to block number
  function getMultiplier(uint256 from, uint256 to) external returns(uint256);

  /// @notice Update multiplier
  /// @param multiplier The new multiplier
  function updateMultiplier(uint256 multiplier) external;

  /// @notice Event emitted when a farming pool incentive has been created
  /// @param pool The Bitriel pool
  /// @param reward The amount of reward tokens to be distributed
  event FarmCreated(
    IBitrielPool indexed pool,
    uint256 reward
  );

  /// @notice Event that can be emitted when a farming pool incentive's allocation point has been updated
  /// @param pool The Bitriel pool
  /// @param oldAllocPoint The old allocation points for the farm
  /// @param newAllocPoint The new allocation points for the farm
  event FarmUpdated(
    IBitrielPool indexed pool,
    uint256 oldAllocPoint,
    uint256 newAllocPoint
  );

  /// @notice Emitted when ownership of a deposit changes
  /// @param tokenId The ID of the deposit (and token) that is being transferred
  /// @param owner The owner of the deposit tokenId
  event TokenDeposited(uint256 indexed tokenId, address indexed owner);

  /// @notice Event emitted when a LP token has been staked
  /// @param tokenId The unique identifier of an LP token
  /// @param liquidity The amount of liquidity staked
  event TokenStaked(uint256 indexed tokenId, uint128 liquidity);

  /// @notice Event emitted when a reward token has been claimed
  /// @param to The address where claimed rewards were sent to
  /// @param reward The amount of BTRs tokens claimed
  event Claimed(address indexed to, uint256 reward);

  /// @notice Event emitted when a LP token has been withdrawn
  /// @param tokenId The unique identifier of an LP token
  event TokenWithdrawn(uint256 indexed tokenId);
}