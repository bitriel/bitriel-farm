// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import "@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol";
import "@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol";
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMulticall.sol';
import "@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import "./IMigrator.sol";

/// @title Bitriel Farmer Interface
/// @notice Allows staking nonfungible liquidity tokens in exchange for BTRs as reward tokens
interface IBitrielFarmer is IERC721Receiver, IMulticall {
    /// @param pool The BitrielSwap pool
    /// @param startTime The time when the yield farming program begins
    /// @param endTime The time when yielding stop accruing
    struct FarmKey {
        IBitrielPool pool;
        uint256 startTime;
        uint256 endTime;
    }
    
    /// @notice The BitrielFactory
    function factory() external view returns (IBitrielFactory);

    /// @notice The nonfungible position manager which this staking contract is compatible
    function nonfungiblePositionManager() external view returns (INonfungiblePositionManager);

    /// @notice The max duration of an yield farming incentive in seconds
    function maxFarmingDuration() external view returns (uint256);

    /// @notice The max amount of seconds into the future the yield farming incentive startTime can be set
    function maxFarmingStartLeadTime() external view returns (uint256);

    /// @notice The migrator contract. It has a lot of power
    /// @dev Can only be set through governance (owner).
    function migrator() external view returns (IMigrator);

    /// @notice Represents a yield farming incentive
    /// @param farmId The ID of the yield farming computed from its parameters
    /// @return totalYieldUnclaimed The amount of yield (reward token) not yet claimed by users
    /// @return totalSecondsClaimedX128 Total liquidity-seconds claimed, represented as a UQ32.128
    /// @return numberOfStakes The count of deposits that are currently staked for the yield farming incentive
    /// @return lastYieldBlock Last block number that BTRs distribution occurs
    // /// @return accBTRPerShare Accumulated BTRs per share, times 1e12
    function farms(bytes32 farmId) external view 
    returns (
        uint256 totalYieldUnclaimed,
        uint160 totalSecondsClaimedX128,
        uint96 numberOfStakes,
        uint256 lastYieldBlock
        // uint256 accBTRPerShare
    );

    /// @notice Returns information about a deposited NFT
    /// @return owner The owner of the deposited NFT
    /// @return numberOfStakes Counter of how many incentives for which the liquidity is staked
    /// @return tickLower The lower tick of the range
    /// @return tickUpper The upper tick of the range
    function deposits(uint256 tokenId) external view 
    returns (
        address owner,
        uint48 numberOfStakes,
        int24 tickLower,
        int24 tickUpper
    );

    /// @notice Returns information about a staked liquidity NFT
    /// @param tokenId The ID of the staked token
    /// @param farmId The ID of the yield farming incentive for which the token is staked
    /// @return secondsPerLiquidityInsideInitialX128 secondsPerLiquidity represented as a UQ32.128
    /// @return liquidity The amount of liquidity in the NFT as of the last time the rewards were computed
    function stakes(bytes32 farmId, uint256 tokenId) external view 
    returns (
        uint160 secondsPerLiquidityInsideInitialX128, 
        uint128 liquidity
    );

    /// @notice Returns amounts of yield (reward tokens) owed to a given address according to the last time all stakes were updated
    /// @param owner The owner for which the yield owed are checked
    /// @return yieldOwed The amount of the yield claimable by the owner
    function yield(address owner) external view returns (uint256 yieldOwed);

    /// @notice Start a new yield farming incentive. 
    /// @dev Can only be called by the owner.
    /// @param key Details of the yield farming to create
    /// @param allocYield The amount of allocation yield (reward tokens) to be distributed
    function createFarm(FarmKey memory key, uint256 allocYield) external;

    /// @notice Update a yield farming incentive. 
    /// @dev Can only be called by the owner.
    /// @param key Details of the yield farming to create
    /// @param allocYield The amount of allocation yield (reward tokens) to be distributed
    function updateFarm(FarmKey memory key, uint256 allocYield) external;

    /// @notice Ends an yield farming incentive after the yielding end time has passed and all stakes have been withdrawn
    /// @dev Can only be called by the owner.
    /// @param key Details of the yield farming to end
    /// @return remainingYield The remaining yield (reward tokens) when the yield farming is ended
    function endFarm(FarmKey memory key) external returns (uint256 remainingYield);

    /// @notice Stakes a BitrielSwap LP token
    /// @param key Details of the yield farming for which to stake the NFT
    /// @param tokenId The ID of the token to stake
    function stakeToken(FarmKey memory key, uint256 tokenId) external;

    /// @notice Unstakes a BitrielSwap LP token
    /// @param key Details of the yield farming for which to unstake the NFT
    /// @param tokenId The ID of the token to unstake
    function unstakeToken(FarmKey memory key, uint256 tokenId) external;

    /// @notice Transfers ownership of a deposit from the sender to the given recipient
    /// @param tokenId The ID of the token (and the deposit) to transfer
    /// @param to The new owner of the deposit
    function transferDeposit(uint256 tokenId, address to) external;

    /// @notice Withdraws a BitrielSwap LP token `tokenId` from this contract to the recipient `to`
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    /// @param to The address where the LP token will be sent
    /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
    function withdrawToken(uint256 tokenId, address to, bytes memory data) external;

    /// @notice Transfers `amountRequested` of accrued BTRs yield (reward tokens) from the contract to the recipient `to`
    /// @param to The address where harvest yield will be sent to
    /// @param yieldRequested The amount of yield to harvest. Claims entire yield amount if set to 0.
    /// @return yieldHarvested The amount of yield harvested
    function harvest(address to, uint256 yieldRequested) external returns (uint256 yieldHarvested);

    /// @notice Withdraw a BitrielSwap LP token `tokenId` and Transfers `amountRequested` of accrued BTRs yield (reward tokens) from the contract to the recipient `to`
    /// @param to The address where harvest yield will be sent to
    /// @param tokenId The unique identifier of an BitrielSwap liquidity NFT token
    /// @param amountRequested The amount of yield to harvest. Claims entire yield amount if set to 0.
    /// @param data An optional data array that will be passed along to the `to` address via the NFT safeTransferFrom
    /// @return yieldHarvested The amount of yield harvested
    function withdrawAndHarvest(
        address to, 
        uint256 tokenId, 
        uint256 amountRequested, 
        bytes memory data
    ) external returns (uint256 yieldHarvested);

    /// @notice Calculates the yield (reward) amount that will be received for the given stake
    /// @param key The key of the yield farming incentive
    /// @param tokenId The ID of the token
    /// @return yieldAmount The yield produced from the NFT for the given incentive thus far
    function getYieldInfo(FarmKey memory key, uint256 tokenId) external returns (
        uint256 yieldAmount, 
        uint160 secondsInsideX128
    );

    /// @notice Set the migrator contract. Can only be called by the owner.
    /// @param _migrator The migrator contract address 
    function setMigrator(IMigrator _migrator) external;

    /// @notice Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    /// @param params The params necessary to migrate v2 liquidity, encoded as `MigrateParams` in calldata
    function migrate(IMigrator.MigrateParams calldata params) external;

    /// @notice Event emitted when a yield farming incentive has been created
    /// @param pool The BitrielSwap pool
    /// @param startTime The time when the yield farming incentive program begins
    /// @param endTime The time when rewards stop accruing
    /// @param reward The amount of reward tokens to be distributed
    event YieldFarmingCreated(
        IBitrielPool indexed pool,
        uint256 startTime,
        uint256 endTime,
        uint256 reward
    );

    /// @notice Event emitted when a yield farming incentive has been created
    /// @param farmId The yield farming incentive which is ending
    /// @param oldReward The old amount of reward tokens
    /// @param newReward The new updated amount of reward tokens to be distributed
    event YieldFarmingUpdated(
        bytes32 indexed farmId,
        uint256 oldReward,
        uint256 newReward
    );

    /// @notice Event that can be emitted when a yield farming incentive has ended
    /// @param farmId The yield farming incentive which is ending
    /// @param remainingYield The amount of reward tokens remaining after farm has been ended
    event YieldFarmingEnded(bytes32 indexed farmId, uint256 remainingYield);

    /// @notice Event emitted when a BitrielSwap LP token has been staked
    /// @param farmId The yield farming incentive in which the token is staking
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    /// @param liquidity The amount of liquidity staked
    event TokenStaked(bytes32 indexed farmId, uint256 indexed tokenId, uint128 liquidity);

    /// @notice Event emitted when a BitrielSwap LP token has been unstaked
    /// @param tokenId The unique identifier of an BitrielSwap LP token
    /// @param farmId The yield farming incentive in which the token is staking
    event TokenUnstaked(bytes32 indexed farmId, uint256 indexed tokenId);

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