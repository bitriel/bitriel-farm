// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMigrator.sol';
import '@bitriel/bitrielswap-periphery/contracts/libraries/TransferHelper.sol';
import '@bitriel/bitrielswap-periphery/contracts/base/Multicall.sol';

import "./interfaces/IBitrielFarmer.sol";
import "./libraries/NFTPositionInfo.sol";
import "./libraries/YieldMath.sol";
import "./BitrielToken.sol";

/// @title BitrielFarmer is the master of Bitriel. He can make BTR and he is a fair guy.
/// @notice that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once BTR is sufficiently
/// distributed and the community can show to govern itself.
contract BitrielFarmer is IBitrielFarmer, Multicall, Ownable {
    using SafeMath for uint256;

    /// @notice Represents a yield farming incentive
    struct Farm {
        uint256 totalYieldUnclaimed;
        uint160 totalSecondsClaimedX128;
        uint96 numberOfStakes;
    }

    /// @notice Represents the deposit of a liquidity NFT
    struct Deposit {
        address owner;
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Represents a staked liquidity NFT
    struct Stake {
        uint160 secondsPerLiquidityInsideInitialX128;
        uint256 startTime;
        uint96 liquidityNoOverflow;
        uint128 liquidityIfOverflow;
    }

    /// @inheritdoc IBitrielFarmer
    IBitrielFactory public immutable override factory;
    /// @inheritdoc IBitrielFarmer
    INonfungiblePositionManager public immutable override nonfungiblePositionManager;
    /// @notice The Bitriel TOKEN!
    /// @dev use as yield (reward tokens) and governance token
    BitrielToken public immutable bitriel;
    /// @inheritdoc IBitrielFarmer
    IMigrator public override migrator;

    /// @dev bytes32 refers to the return value of FarmId.compute
    mapping(address => Farm) public override farms;
    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public override deposits;
    /// @dev stakes[poolAddress][tokenId] => Stake
    mapping(uint256 => Stake) private _stakes;
    /// @dev yield[owner] => uint256
    /// @inheritdoc IBitrielFarmer
    mapping(address => uint256) public override yield;

    /// @param _factory the Uniswap V3 factory
    /// @param _nonfungiblePositionManager the NFT position manager contract address
    /// @param _bitriel the Bitriel token address
    constructor(
        IBitrielFactory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        BitrielToken _bitriel
    ) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        bitriel = _bitriel;
    }

    /// @inheritdoc IBitrielFarmer
    function createFarm(IBitrielPool pool, uint256 allocYield) external override onlyOwner {
        require(allocYield > 0, 'MBP'); // allocation yield must be positive

        // update allocation yield for the new farm
        address poolAddress = address(pool);
        farms[poolAddress].totalYieldUnclaimed = farms[poolAddress].totalYieldUnclaimed.add(allocYield);

        // issue/locked BTRs in this contract 
        // incentivise 10% of total allocation yield to dev address
        bitriel.mint(address(this), allocYield);
        bitriel.mint(owner(), allocYield.div(10));

        // emit YieldFarmingCreated event
        emit YieldFarmingCreated(pool, allocYield);
    }

    /// @inheritdoc IBitrielFarmer
    function updateFarm(IBitrielPool pool, uint256 allocYield) external override onlyOwner {
        require(allocYield > 0, 'MBP'); // allocation yield must be positive

        // check if farm already exist
        address poolAddress = address(pool);
        require(farms[poolAddress].totalYieldUnclaimed > 0, 'FNE'); // farm not exist

        // update allocation yield for the farm
        Farm storage farm = farms[poolAddress];
        uint256 oldYield = farm.totalYieldUnclaimed;
        farm.totalYieldUnclaimed = allocYield;

        // burn old allocation BTRs
        safeBTRTransfer(address(bitriel), oldYield);

        // issue/locked new allocation BTRs in this contract
        // incentivise 10% of total allocation yield to dev address
        bitriel.mint(address(this), allocYield);
        bitriel.mint(owner(), allocYield.div(10));

        // emit YieldFarmingUpdated event
        emit YieldFarmingUpdated(pool, oldYield, allocYield);
    }

    /// @notice Upon receiving a BitrielSwap Liquidity NFT, creates the token deposit setting owner to `from`. Also stakes token
    /// in one or more incentives if properly formatted `data` has a length > 0.
    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), 'NBNFT'); // not a Bitriel NFT address

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);
        deposits[tokenId] = Deposit({owner: from, tickLower: tickLower, tickUpper: tickUpper});

        // stake the tokenId if there are available farm
        _stake(tokenId);

        return this.onERC721Received.selector;
    }

    /// @inheritdoc IBitrielFarmer
    /// @dev At any point between start/end time period of yield farming, 
    /// users can stake their deposit position to paticipate to earn in the farming 
    function stake(uint256 tokenId) external override {
        require(msg.sender == deposits[tokenId].owner, "OO"); // only owner can stake their token

        _stake(tokenId);
    }

    /// @inheritdoc IBitrielFarmer
    /// @dev At any point of yield farming duration, 
    /// users can unstake to get yield return from farming of their position
    function unstake(uint256 tokenId, bytes memory data) external override {
        Deposit memory deposit = deposits[tokenId];
        harvest(tokenId, deposit.owner, 0);

        // get NFT position info from `tokenId` and farm info from BitrielSwap pool address
        (address pool, , , ) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);
        farms[pool].numberOfStakes--;

        // delete stake that represent staking position in the farm
        delete _stakes[tokenId];

        // transfer LP-NFT tokenId from this contract to `to` address with `data`
        nonfungiblePositionManager.safeTransferFrom(address(this), deposit.owner, tokenId, data);

        // delete deposit position after transfer liquidity NFT back to the owner
        delete deposits[tokenId];

        // emit TokenUnstaked event
        emit TokenUnstaked(tokenId);
    }

    /// @inheritdoc IBitrielFarmer
    function harvest(uint256 tokenId, address to, uint256 yieldRequested) public override 
    returns (uint256 yieldHarvested) {
        require(msg.sender == deposits[tokenId].owner, "OO"); // only owner can stake their token
        require(to != address(0) && to != address(this), "IRA"); // invalid recipient address

        // get NFT position info from `tokenId` and farm info from BitrielSwap pool address
        (address pool, , , ) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);

        (uint256 yieldAmount, uint160 secondsInsideX128) = getYieldInfo(tokenId);

        // update states of deposits, farms and yield based computed yield amount
        farms[pool].totalSecondsClaimedX128 += secondsInsideX128;
        farms[pool].totalYieldUnclaimed = farms[pool].totalYieldUnclaimed.sub(yieldAmount);
        yield[msg.sender] = yield[msg.sender].add(yieldAmount);

        // get available yield to harvest for distributing to `msg.sender`
        yieldHarvested = yield[msg.sender];
        if (yieldRequested != 0 && yieldRequested < yieldHarvested) {
            yieldHarvested = yieldRequested;
        }

        // update state to decrease available yield for `msg.sender` 
        yield[msg.sender] = yield[msg.sender].sub(yieldHarvested);
        // transfer BTRs as reward for `yieldHarvested` amount to `to` address
        safeBTRTransfer(to, yieldHarvested);

        // emit YieldHarvested event
        emit YieldHarvested(to, yieldHarvested);
    }

    /// @inheritdoc IBitrielFarmer
    function stakes(uint256 tokenId) public view override returns (
        uint160 secondsPerLiquidityInsideInitialX128, 
        uint128 liquidity,
        uint256 startTime
    ) {
        Stake memory stakeInfo = _stakes[tokenId];
        secondsPerLiquidityInsideInitialX128 = stakeInfo.secondsPerLiquidityInsideInitialX128;
        liquidity = stakeInfo.liquidityNoOverflow;
        startTime = stakeInfo.startTime;

        // check if liquidity is over the maximum which uint96 can handle (2^96)
        if (liquidity == type(uint96).max) {
            liquidity = stakeInfo.liquidityIfOverflow;
        }
    }

    /// @inheritdoc IBitrielFarmer
    function getYieldInfo(uint256 tokenId) public view override 
    returns (
        uint256 yieldAmount, 
        uint160 secondsInsideX128
    ) {
        // get and check staked liquidity of the token on the farm
        (uint160 secondsPerLiquidityInsideInitialX128, uint128 liquidity, uint256 startTime) = stakes(tokenId);
        require(liquidity > 0, 'SNE'); // stake does not exist

        // get NFT position info from `tokenId` and farm info from BitrielSwap pool address
        (address pool, int24 tickLower, int24 tickUpper, ) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);
        Farm memory farm = farms[pool];

        // get `secondsPerLiquidity` from the pool tick range
        (, uint160 secondsPerLiquidityInsideX128, ) = IBitrielPool(pool).snapshotCumulativesInside(tickLower, tickUpper);
        // compute allocation yield amount to be distributed from the given liquidity and secondsPerLiquidity
        (yieldAmount, secondsInsideX128) = YieldMath.computeYieldAmount(
            farm.totalYieldUnclaimed,
            farm.totalSecondsClaimedX128,
            liquidity,
            secondsPerLiquidityInsideInitialX128,
            secondsPerLiquidityInsideX128,
            startTime,
            block.timestamp
        );

        return (yieldAmount, secondsInsideX128);
    }

    /// @inheritdoc IBitrielFarmer
    function setMigrator(IMigrator _migrator) external override onlyOwner {
        require(address(_migrator) != address(0), "IMA"); // invalid migrator contract address
        migrator = _migrator;
    }

    /// @inheritdoc IBitrielFarmer
    function migrate(IMigrator.MigrateParams calldata params, bytes memory data) external override {
        require(address(migrator) != address(0), "NM"); // no migrator
        
        // get tokenId from Migrator.migrate() contract
        TransferHelper.safeApprove(params.pair, address(this), params.liquidityToMigrate);
        uint256 tokenId = migrator.migrate(params);
        // transfer the token from recipient to this contract 
        // for deposit and staking position on BitrielFarm
        nonfungiblePositionManager.safeTransferFrom(params.recipient, address(this), tokenId, data);
        // mint some BTRs based on liquidity provided to the pool as reward for migration
        bitriel.mint(msg.sender, params.liquidityToMigrate.div(10));
    }

    /// @dev Stakes a deposited token without doing an ownership check
    function _stake(uint256 tokenId) private {
        require(_stakes[tokenId].liquidityNoOverflow == 0, 'TAS'); // token is already staked

        // get/check if the liquidity and the pool is valid
        (address pool, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);
        require(liquidity > 0, 'ZL'); // cannot stake token with 0 liquidity

        require(farms[pool].totalYieldUnclaimed > 0, 'NEI'); // non-existent farm

        (, uint160 secondsPerLiquidityInsideX128, ) = IBitrielPool(pool).snapshotCumulativesInside(tickLower, tickUpper);

        // check if provided liquidity pool is over the maximum (2^96) to handle
        // store new stake object with liquidity
        if (liquidity >= type(uint96).max) {
            _stakes[tokenId] = Stake({
                secondsPerLiquidityInsideInitialX128: secondsPerLiquidityInsideX128,
                liquidityNoOverflow: type(uint96).max,
                liquidityIfOverflow: liquidity,
                startTime: block.timestamp
            });
        } else {
            _stakes[tokenId] = Stake({
                secondsPerLiquidityInsideInitialX128: secondsPerLiquidityInsideX128,
                liquidityNoOverflow: uint96(liquidity),
                liquidityIfOverflow: 0,
                startTime: block.timestamp
            });
        }

        // increase number of stakes in the farm
        farms[pool].numberOfStakes++;

        // emit TokenStaked event
        emit TokenStaked(tokenId, liquidity);
    }

    /// @dev Safe bitriel transfer function, just in case if rounding error causes farm to not have enough BTRs.
    function safeBTRTransfer(address _to, uint256 _amount) private {
        uint256 bal = bitriel.balanceOf(address(this));

        // check if requested amount is greater than available amount for distributed
        if (_amount > bal) {
            TransferHelper.safeTransfer(address(bitriel), _to, bal);
        } else {
            TransferHelper.safeTransfer(address(bitriel), _to, _amount);
        }
    }
}