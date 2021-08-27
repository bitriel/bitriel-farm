// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@bitriel/bitrielswap-periphery/contracts/libraries/TransferHelper.sol';
import '@bitriel/bitrielswap-periphery/contracts/base/Multicall.sol';

import "./interfaces/IBitrielFarmer.sol";
import "./interfaces/IMigrator.sol";
import "./libraries/NFTPositionInfo.sol";
import "./libraries/YieldMath.sol";
import "./libraries/FarmId.sol";
import "./BitrielToken.sol";

/// @title BitrielFarmer is the master of Bitriel. He can make BTR and he is a fair guy.
/// @dev that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once BTR is sufficiently
/// distributed and the community can show to govern itself.
contract BitrielFarmer is IBitrielFarmer, Multicall, Ownable {
    using SafeMath for uint256;

    /// @notice Represents a yield farming incentive
    struct Farm {
        uint256 totalYieldUnclaimed;
        uint160 totalSecondsClaimedX128;
        uint96 numberOfStakes;
        uint256 lastYieldBlock;
    }

    /// @notice Represents the deposit of a liquidity NFT
    struct Deposit {
        address owner;
        uint48 numberOfStakes;
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Represents a staked liquidity NFT
    struct Stake {
        uint160 secondsPerLiquidityInsideInitialX128;
        uint96 liquidityNoOverflow;
        uint128 liquidityIfOverflow;
    }

    /// @inheritdoc IBitrielFarmer
    IBitrielFactory public immutable override factory;
    /// @inheritdoc IBitrielFarmer
    INonfungiblePositionManager public immutable override nonfungiblePositionManager;
    /// @inheritdoc IBitrielFarmer
    uint256 public immutable override maxFarmingStartLeadTime;
    /// @inheritdoc IBitrielFarmer
    uint256 public immutable override maxFarmingDuration;

    /// @notice The Bitriel TOKEN!
    /// @dev use as yield (reward tokens) and governance token
    BitrielToken public immutable bitriel;
    /// @notice Dev address.
    address public dev;
    // /// @notice BTR tokens created per block.
    // uint256 public immutable BTRPerBlock;
    // /// @notice The block number when BTR mining starts.
    // uint256 public immutable startBlock;
    // /// @notice Block number when bonus BTR period ends.
    // uint256 public immutable bonusEndBlock;
    // /// @dev Bonus muliplier for early bitriel makers.
    // uint256 private constant BONUS_MULTIPLIER = 1;
    // uint256 private constant ACC_BTR_PRECISION = 1e12;

    /// @dev bytes32 refers to the return value of FarmId.compute
    /// @inheritdoc IBitrielFarmer
    mapping(bytes32 => Farm) public override farms;
    /// @dev deposits[tokenId] => Deposit
    /// @inheritdoc IBitrielFarmer
    mapping(uint256 => Deposit) public override deposits;
    /// @dev stakes[farmId][tokenId] => Stake
    mapping(bytes32 => mapping(uint256 => Stake)) private _stakes;
    /// @dev yield[user] => yieldOwed
    /// @inheritdoc IBitrielFarmer
    mapping(address => uint256) public override yield;
    /// @inheritdoc IBitrielFarmer
    IMigrator public override migrator;

    constructor(
        IBitrielFactory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        BitrielToken _bitriel,
        address _devaddr,
        // uint256 _BTRPerBlock,
        uint256 _maxFarmingStartLeadTime,
        uint256 _maxFarmingDuration
        // uint256 _startBlock,
        // uint256 _bonusEndBlock
    ) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        bitriel = _bitriel;
        dev = _devaddr;
        // BTRPerBlock = _BTRPerBlock;
        maxFarmingStartLeadTime = _maxFarmingStartLeadTime;
        maxFarmingDuration = _maxFarmingDuration;
        // startBlock = _startBlock;
        // bonusEndBlock = _bonusEndBlock;
    }

    /// @inheritdoc IBitrielFarmer
    function stakes(bytes32 farmId, uint256 tokenId) public view override returns (
        uint160 secondsPerLiquidityInsideInitialX128, 
        uint128 liquidity
    ) {
        Stake memory stake = _stakes[farmId][tokenId];
        secondsPerLiquidityInsideInitialX128 = stake.secondsPerLiquidityInsideInitialX128;
        liquidity = stake.liquidityNoOverflow;

        // check if liquidity is over the maximum which uint96 can handle (2^96)
        if (liquidity == type(uint96).max) {
            liquidity = stake.liquidityIfOverflow;
        }
    }

    /// @inheritdoc IBitrielFarmer
    function createFarm(FarmKey memory key, uint256 allocYield) external override onlyOwner {
        require(allocYield > 0, 'MBP'); // allocation yield must be positive
        require(block.timestamp <= key.startTime, 'STNoF'); // start time must be now or in the future
        require(key.startTime - block.timestamp <= maxFarmingStartLeadTime, 'STTF'); // start time too far into future
        require(key.startTime < key.endTime, 'SBE'); // start time must be before end time
        require(key.endTime - key.startTime <= maxFarmingDuration, 'DTL'); // farmimg duration is too long

        // get last yield distributed block and generate a unique id for farm from `FarmKey` key
        // uint256 lastYieldBlock = Math.max(block.number, startBlock);
        bytes32 farmId = FarmId.compute(key);
        require(farms[farmId].totalYieldUnclaimed == 0, "FAE"); // farm is already exist
        // update allocation yield for the new farm
        farms[farmId].totalYieldUnclaimed = allocYield;
        // farms[farmId].lastYieldBlock = lastYieldBlock;

        // issue/locked BTRs in this contract 
        // incentivise 10% of total allocation yield to dev address
        // modifyFarm(farmId);
        bitriel.mint(address(this), allocYield);
        bitriel.mint(dev, allocYield.div(10));

        // emit YieldFarmingCreated event
        emit YieldFarmingCreated(key.pool, key.startTime, key.endTime, allocYield);
    }

    /// @inheritdoc IBitrielFarmer
    function updateFarm(FarmKey memory key, uint256 allocYield) external override onlyOwner {
        require(allocYield > 0, 'MBP'); // allocation yield must be positive
        require(block.timestamp <= key.startTime, 'FAS'); // farm has been started, can not update

        // check if farm already exist
        bytes32 farmId = FarmId.compute(key);
        require(farms[farmId].totalYieldUnclaimed > 0, 'FNE'); // farm not exist

        // update allocation yield for the farm
        Farm storage farm = farms[farmId];
        uint256 oldYield = farm.totalYieldUnclaimed;
        farm.totalYieldUnclaimed = allocYield;

        // if(block.number > farm.lastYieldBlock) {
        //     modifyFarm(farmId);
        // }
        // issue/locked new allocation BTRs in this contract and burn old allocation BTRs
        safeBTRTransfer(address(this), oldYield);
        bitriel.mint(address(this), allocYield);
        // incentivise 10% of total allocation yield to dev address and burn old allocation BTRs
        bitriel.transferFrom(dev, address(bitriel), oldYield.div(10));
        bitriel.mint(dev, allocYield.div(10));

        // emit YieldFarmingUpdated event
        emit YieldFarmingUpdated(farmId, oldYield, allocYield);
    }

    /// @inheritdoc IBitrielFarmer
    function endFarm(FarmKey memory key) external override onlyOwner returns(uint256 remainingYield) {
        require(block.timestamp >= key.endTime, 'EBET'); // cannot end farm before end time

        // get remaining allocation yield
        bytes32 farmId = FarmId.compute(key);
        Farm storage farm = farms[farmId];
        remainingYield = farm.totalYieldUnclaimed;

        require(remainingYield > 0, 'NRY'); // no remaining yield
        require(farm.numberOfStakes == 0, 'DS'); // cannot end farm while deposits are staked

        // reset total allocation yield and transfer to dev address
        farm.totalYieldUnclaimed = 0;
        safeBTRTransfer(dev, remainingYield);

        // note we never clear totalSecondsClaimedX128
        // emit YieldFarmingEnded event
        emit YieldFarmingEnded(farmId, remainingYield);
    }

    /// @inheritdoc IBitrielFarmer
    function stakeToken(FarmKey memory key, uint256 tokenId) external override {
        require(msg.sender == deposits[tokenId].owner, "OO"); // only owner can stake their token

        _stakeToken(key, tokenId);
    }

    /// @inheritdoc IBitrielFarmer
    function unstakeToken(FarmKey memory key, uint256 tokenId) external override {
        Deposit memory deposit = deposits[tokenId];
        require(msg.sender == deposit.owner, "OO"); // only owner can stake their token
        bytes32 farmId = FarmId.compute(key);
        // get staked liquidity for computing yield amount
        (uint160 secondsPerLiquidityInsideInitialX128, uint128 liquidity) = stakes(farmId, tokenId);
        require(liquidity > 0, "TNS"); // token is not yet stakes

        // compute yield (BTRs) amount for distributing to the staker
        Farm storage farm = farms[farmId];
        (, uint160 secondsPerLiquidityInsideX128, ) = key.pool.snapshotCumulativesInside(deposit.tickLower, deposit.tickUpper);
        (uint256 yieldAmount, uint160 secondsInsideX128) = YieldMath.computeYieldAmount(
            farm.totalYieldUnclaimed,
            farm.totalSecondsClaimedX128,
            key.startTime,
            key.endTime,
            liquidity,
            secondsPerLiquidityInsideInitialX128,
            secondsPerLiquidityInsideX128,
            block.timestamp
        );

        // update states of deposits, farms and yield based computed yield amount
        deposits[tokenId].numberOfStakes--;
        farm.numberOfStakes--;
        farm.totalSecondsClaimedX128 += secondsInsideX128;
        farm.totalYieldUnclaimed = farm.totalYieldUnclaimed.sub(yieldAmount);
        yield[msg.sender] = yield[msg.sender].add(yieldAmount);

        // delete stake that represent staking position in the farm
        delete _stakes[farmId][tokenId];

        // emit TokenUnstaked event
        emit TokenUnstaked(farmId, tokenId);
    }

    /// @notice Upon receiving a BitrielSwap Liquidity NFT, creates the token deposit setting owner to `from`. Also stakes token
    /// in one or more incentives if properly formatted `data` has a length > 0.
    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), 'NBNFT'); // not a Bitriel NFT address

        // get tick range from NFT positions of the tokenId
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);
        // create a deposit object represent deposited LP-NFT token to this contract
        deposits[tokenId] = Deposit({owner: from, numberOfStakes: 0, tickLower: tickLower, tickUpper: tickUpper});

        // emit DepositTransferred event
        emit DepositTransferred(tokenId, address(0), from);

        if (data.length > 0) {
            if (data.length == 160) {
                // stake the token with given params
                _stakeToken(abi.decode(data, (FarmKey)), tokenId);
            } 
            // else {
            //     FarmKey[] memory keys = abi.decode(data, (FarmKey[]));
            //     for (uint256 i = 0; i < keys.length; i++) {
            //         _stakeToken(keys[i], tokenId);
            //     }
            // }
        }
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IBitrielFarmer
    function transferDeposit(uint256 tokenId, address to) external override {
        require(to != address(0), "IRA"); // invalid recipient address
        address currentOwner = deposits[tokenId].owner;
        // check if `msg.sender` is deposit position owner
        require(msg.sender == currentOwner, "OO"); // only owner of the token can transfer ownership
        Deposit storage deposit = deposits[tokenId];
        // set owner to `to` address
        deposit.owner = to;

        // emit DepositTransferred event
        emit DepositTransferred(tokenId, currentOwner, to);
    }

    /// @inheritdoc IBitrielFarmer
    function withdrawToken(uint256 tokenId, address to, bytes calldata data) external override {
        require(to != address(0) && to != address(this), "IRA"); // invalid recipient address or is this contract address
        
        Deposit memory deposit = deposits[tokenId];
        require(msg.sender == deposit.owner, "OO"); // only owner can withdraw their token
        require(deposit.numberOfStakes == 0, "WWS"); // can not withdraw while staked, need to unstake first

        // delete deposit position of the tokenId
        delete deposits[tokenId];
        // emit DepositTransferred event
        emit DepositTransferred(tokenId, deposit.owner, address(0));

        // transfer LP-NFT tokenId from this contract to `to` address with `data`
        nonfungiblePositionManager.safeTransferFrom(address(this), to, tokenId, data);

        // emit TokenWithdrawn event
        emit TokenWithdrawn(tokenId, to);
    }

    /// @inheritdoc IBitrielFarmer
    function harvest(address to, uint256 yieldRequested) external override 
    returns (uint256 yieldHarvested) {
        require(to != address(0) && to != address(this), "IRA"); // invalid recipient address
        require(yieldRequested > 0, "YLZ"); // yield requested must be greater than zero

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
    function getYieldInfo(FarmKey memory key, uint256 tokenId) public view override 
    returns (
        uint256 yieldAmount, 
        uint160 secondsInsideX128
    ) {
        bytes32 farmId = FarmId.compute(key);
        // get and check staked liquidity of the token on the farm
        (uint160 secondsPerLiquidityInsideInitialX128, uint128 liquidity) = stakes(farmId, tokenId);
        require(liquidity > 0, 'SNE'); // stake does not exist

        Deposit memory deposit = deposits[tokenId];
        Farm memory farm = farms[farmId];

        // get `secondsPerLiquidity` from the pool tick range
        (, uint160 secondsPerLiquidityInsideX128, ) =
            key.pool.snapshotCumulativesInside(deposit.tickLower, deposit.tickUpper);
        // compute allocation yield amount to be distributed from the given liquidity and secondsPerLiquidity
        (yieldAmount, secondsInsideX128) = YieldMath.computeYieldAmount(
            farm.totalYieldUnclaimed,
            farm.totalSecondsClaimedX128,
            key.startTime,
            key.endTime,
            liquidity,
            secondsPerLiquidityInsideInitialX128,
            secondsPerLiquidityInsideX128,
            block.timestamp
        );
    }

    /// @inheritdoc IBitrielFarmer
    function setMigrator(IMigrator _migrator) public override onlyOwner {
        migrator = _migrator;
    }

    /// @inheritdoc IBitrielFarmer
    function migrate(IMigrator.MigrateParams calldata params) public override {
        require(address(migrator) != address(0), "NM"); // no migrator
        
        // get tokenId from Migrator.migrate() contract
        uint256 tokenId = migrator.migrate(params);
        // transfer the token from recipient to this contract 
        // for deposit and staking position on BitrielFarm
        nonfungiblePositionManager.safeTransferFrom(params.recipient, address(this), tokenId);
        // transfer some BTRs based on liquidity provided to the pool as reward for migration
        safeBTRTransfer(msg.sender, 1e18);
    }

    /// @notice Update dev address by the previous dev.
    function setDev(address _devaddr) external {
        require(msg.sender == dev, "ODA"); // only dev address can change
        dev = _devaddr;
    }

    // /// @notice Return reward multiplier over the given _from to _to block.
    // function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
    //     if (_to <= bonusEndBlock) {
    //         return _to.sub(_from).mul(BONUS_MULTIPLIER);
    //     } else if (_from >= bonusEndBlock) {
    //         return _to.sub(_from);
    //     } else {
    //         return
    //             bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
    //                 _to.sub(bonusEndBlock)
    //             );
    //     }
    // }

    // /// @dev Update reward variables of the given farm to be up-to-date
    // function modifyFarm(bytes32 farmId) private {
    //     Farm storage farm = farms[farmId];
    //     uint256 yieldSupply = bitriel.balanceOf(address(this));
    //     uint128 lpSupply = farm.pool.liquidity();
    //     if (yieldSupply == 0) {
    //         farm.lastYieldBlock = block.number;
    //         return;
    //     }

    //     uint256 multiplier = getMultiplier(farm.lastYieldBlock, block.number);
    //     uint256 BTRReward =
    //         multiplier.mul(BTRPerBlock).mul(farm.totalYieldUnclaimed).div(
    //             yieldSupply
    //         );
        
    //     bitriel.mint(dev, BTRReward.div(10));
    //     bitriel.mint(address(this), BTRReward);
    //     // farm.accBTRPerShare = farm.accBTRPerShare.add(
    //     //     BTRReward.mul(ACC_BTR_PRECISION).div(lpSupply)
    //     // );
    //     farm.lastRewardBlock = block.number;
    // }

    /// @dev Stakes a deposited token without doing an ownership check
    function _stakeToken(FarmKey memory key, uint256 tokenId) private {
        // check start/end time with current block timestamp
        require(block.timestamp >= key.startTime, 'FNS'); // farm not started
        require(block.timestamp < key.endTime, 'FEN'); // farm is end now

        // check if farm is generate some incentive for staking
        bytes32 farmId = FarmId.compute(key);
        require(farms[farmId].totalYieldUnclaimed > 0, 'NEI'); // non-existent incentive
        require(_stakes[farmId][tokenId].liquidityNoOverflow == 0, 'TAS'); // token is already staked
        // get/check if the liquidity and the pool is valid
        (IBitrielPool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);
        require(pool == key.pool, 'PNIP'); // token pool is not the incentive pool
        require(liquidity > 0, 'ZL'); // cannot stake token with 0 liquidity

        // increase number of stakes in deposits/farms
        deposits[tokenId].numberOfStakes++;
        farms[farmId].numberOfStakes++;

        (, uint160 secondsPerLiquidityInsideX128, ) = pool.snapshotCumulativesInside(tickLower, tickUpper);

        // check if provided liquidity pool is over the maximum (2^96) to handle
        // store new stake object with liquidity
        if (liquidity >= type(uint96).max) {
            _stakes[farmId][tokenId] = Stake({
                secondsPerLiquidityInsideInitialX128: secondsPerLiquidityInsideX128,
                liquidityNoOverflow: type(uint96).max,
                liquidityIfOverflow: liquidity
            });
        } else {
            Stake storage stake = _stakes[farmId][tokenId];
            stake.secondsPerLiquidityInsideInitialX128 = secondsPerLiquidityInsideX128;
            stake.liquidityNoOverflow = uint96(liquidity);
        }

        // emit TokenStaked event
        emit TokenStaked(farmId, tokenId, liquidity);
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