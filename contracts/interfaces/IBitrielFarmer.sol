// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

import "@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol";
import "@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol";
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMulticall.sol';
import "@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@bitriel/bitrielswap-periphery/contracts/interfaces/IMigrator.sol";


/// @title Bitriel Farmer Interface
/// @notice Allows staking nonfungible liquidity tokens in exchange for BTRs as reward tokens
interface IBitrielFarmer is IERC721Receiver, IMulticall {
    /// @notice The BitrielFactory
    function factory() external view returns (IBitrielFactory);

    /// @notice The nonfungible position manager which this staking contract is compatible
    function nonfungiblePositionManager() external view returns (INonfungiblePositionManager);

    /// @notice The migrator contract. It has a lot of power
    /// @dev Can only be set through governance (owner).
    function migrator() external view returns (IMigrator);

    /// @notice Represents a yield farming incentive
    /// @param poolAddress The pool address
    /// @return totalYieldUnclaimed The amount of yield (reward token) not yet claimed by users
    /// @return totalSecondsClaimedX128 Total liquidity-seconds claimed, represented as a UQ32.128
    /// @return numberOfStakes The count of deposits that are currently staked for the yield farming incentive
    function farms(address poolAddress) external view 
    returns (
        uint256 totalYieldUnclaimed,
        uint160 totalSecondsClaimedX128,
        uint96 numberOfStakes
    );

    /// @notice Returns information about a deposited NFT
    /// @return owner The owner of the deposited NFT
    /// @return tickLower The lower tick of the range
    /// @return tickUpper The upper tick of the range
    function deposits(uint256 tokenId) external view 
    returns (
        address owner,
        int24 tickLower,
        int24 tickUpper
    );

    /// @notice Returns information about a staked liquidity NFT
    /// @param tokenId The ID of the staked token
    /// @return secondsPerLiquidityInsideInitialX128 secondsPerLiquidity represented as a UQ32.128
    /// @return liquidity The amount of liquidity in the NFT as of the last time the rewards were computed
    /// @return startTime The timestamp when user start staking the `tokenId` in the farm
    function stakes(uint256 tokenId) external view 
    returns (
        uint160 secondsPerLiquidityInsideInitialX128, 
        uint128 liquidity,
        uint256 startTime
    );

    /// @notice Returns amounts of yield (reward tokens) owed to a given address according to the last time all stakes were updated
    /// @param owner The owner for which the yield owed are checked
    /// @return yieldOwed The amount of the yield claimable by the owner
    function yield(address owner) external view returns (uint256 yieldOwed);

    /// @notice Start a new yield farming incentive. 
    /// @dev Can only be called by the owner.
    /// @param pool The liquidity pool for this yield farming
    /// @param allocYield The amount of allocation yield (reward tokens) to be distributed
    function createFarm(IBitrielPool pool, uint256 allocYield) external;

    /// @notice Update a yield farming incentive. 
    /// @dev Can only be called by the owner.
    /// @param pool The liquidity pool for this yield farming
    /// @param allocYield The amount of allocation yield (reward tokens) to be distributed
    function updateFarm(IBitrielPool pool, uint256 allocYield) external;

    /// @notice Stakes a BitrielSwap LP token
    /// @param tokenId The ID of the token to stake
    function stake(uint256 tokenId) external;

    /// @notice Unstakes a BitrielSwap LP token
    /// @param tokenId The ID of the token to unstake
    function unstake(uint256 tokenId) external;

    /// @notice Transfers ownership of a deposit from the sender to the given recipient
    /// @param tokenId The ID of the token (and the deposit) to transfer
    /// @param to The new owner of the deposit
    function transferDeposit(uint256 tokenId, address to) external;

    /// @notice Withdraws a BitrielSwap LP token `tokenId` from this contract to the recipient `to`
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    /// @param to The address where the LP token will be sent
    /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
    function withdraw(uint256 tokenId, address to, bytes memory data) external;

    /// @notice Transfers `amountRequested` of accrued BTRs yield (reward tokens) from the contract to the recipient `to`
    /// @param to The address where harvest yield will be sent to
    /// @param yieldRequested The amount of yield to harvest. Claims entire yield amount if set to 0.
    /// @return yieldHarvested The amount of yield harvested
    function harvest(address to, uint256 yieldRequested) external returns (uint256 yieldHarvested);

    /// @notice Calculates the yield (reward) amount that will be received for the given stake
    /// @param tokenId The ID of the token
    /// @return yieldAmount The yield produced from the NFT for the given incentive thus far
    function getYieldInfo(uint256 tokenId) external returns (
        uint256 yieldAmount, 
        uint160 secondsInsideX128
    );

    /// @notice Set the migrator contract. Can only be called by the owner.
    /// @param _migrator The migrator contract address 
    function setMigrator(IMigrator _migrator) external;

    /// @notice Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    /// @param params The params necessary to migrate v2 liquidity, encoded as `MigrateParams` in calldata
    /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
    function migrate(IMigrator.MigrateParams calldata params, bytes calldata data) external;

    /// @notice Event emitted when a yield farming incentive has been created
    /// @param pool The BitrielSwap pool
    /// @param reward The amount of reward tokens to be distributed
    event YieldFarmingCreated(
        IBitrielPool indexed pool,
        uint256 reward
    );

    /// @notice Event emitted when a yield farming incentive has been updated
    /// @param pool The BitrielSwap pool for the yield farming being updated
    /// @param oldReward The old amount of reward tokens
    /// @param newReward The new updated amount of reward tokens to be distributed
    event YieldFarmingUpdated(
        IBitrielPool indexed pool,
        uint256 oldReward,
        uint256 newReward
    );

    /// @notice Event emitted when a BitrielSwap LP token has been staked
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    /// @param liquidity The amount of liquidity staked
    event TokenStaked(uint256 indexed tokenId, uint128 liquidity);

    /// @notice Event emitted when a BitrielSwap LP token has been unstaked
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    event TokenUnstaked(uint256 indexed tokenId);

    /// @notice Emitted when ownership of a deposit changes
    /// @param tokenId The ID of the deposit (and token) that is being transferred
    /// @param oldOwner The owner before the deposit was transferred
    /// @param newOwner The owner after the deposit was transferred
    event DepositTransferred(uint256 indexed tokenId, address indexed oldOwner, address indexed newOwner);

    /// @notice Emitted when a BitrielSwap LP token has been withdrawn to recipient `to`
    /// @param tokenId The ID of the deposit (and token) that is being transferred
    /// @param to The address where the LP token were sent to
    event TokenWithdrawn(uint256 indexed tokenId, address indexed to);

    /// @notice Event emitted when a yield (reward token) has been claimed
    /// @param to The address where harvested yield were sent to
    /// @param yield The amount of yield harvested
    event YieldHarvested(address indexed to, uint256 yield);
}