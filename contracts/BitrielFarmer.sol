// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import '@bitriel/bitrielswap-core/contracts/libraries/FullMath.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMigrator.sol';
import '@bitriel/bitrielswap-periphery/contracts/base/Multicall.sol';
import '@bitriel/bitrielswap-periphery/contracts/libraries/TransferHelper.sol';

import "./interfaces/IBitrielFarmer.sol";
import "./interfaces/IBitrielToken.sol";
import "./libraries/NFTPositionInfo.sol";

contract BitrielFarmer is IBitrielFarmer, Multicall, Ownable {
  using FullMath for uint256;
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /// @notice Represents a yield farming incentive
  struct Farm {
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accBTRPerLiqX12;
    uint128 totalLiquidity;
  }

  /// @notice Represents the deposit of a liquidity NFT
  struct Deposit {
    address owner;
    int24 tickLower;
    int24 tickUpper;
  }

  /// @notice Represents the staking position of a liquidity NFT
  struct Stake {
    uint160 lastSecondsPerLiquidityInsideX128;
    uint256 lastRewardTime;
    uint128 liquidity;
    uint256 rewardClaimed;
  }

  /// @inheritdoc IBitrielFarmer
  IBitrielFactory public immutable override factory;
  /// @inheritdoc IBitrielFarmer
  INonfungiblePositionManager public immutable override nonfungiblePositionManager;
  /// @inheritdoc IBitrielFarmer
  IMigrator public override migrator;
  /// @inheritdoc IBitrielFarmer
  IBitrielToken public immutable override bitriel;

  /// @dev farms[pool] => Farm
  mapping(address => Farm) public override farms;
  /// @dev userTokens[pool][user] => User tokens
  mapping(address => mapping(address => uint256[])) private _userTokens;
  /// @dev deposits[tokenId] => Deposit
  mapping(uint256 => Deposit) public override deposits;
  /// @dev stakes[tokenId] => Stake
  mapping(uint256 => Stake) public override stakes;

  /// @dev Amount of BTRs produced per block for all farming pools in its decimals format
  uint256 public immutable BTRPerBlock;
  /// @dev Multiplier for bonusing to early BitrielFarm users
  uint256 public bonusMultiplier = 1;
  /// @dev Total allocation points from all the farms
  uint256 public totalAllocPoint = 0;
  /// @dev Total farming pools
  uint256 public totalFarm = 0;
  // The block number when BTR emitting starts.
  uint256 public startEmitBTR;

  /// @param _factory the BitrielSwap factory
  /// @param _nonfungiblePositionManager the NFT position manager contract address
  /// @param _bitriel the Bitriel token address
  /// @param _BTRPerBlock the amount of BTRs to be emitted per block (its decimal format)
  constructor(
    IBitrielFactory _factory,
    INonfungiblePositionManager _nonfungiblePositionManager,
    IBitrielToken _bitriel,
    uint256 _BTRPerBlock,
    uint256 _startEmitBTR
  ) {
    factory = _factory;
    nonfungiblePositionManager = _nonfungiblePositionManager;
    bitriel = _bitriel;
    BTRPerBlock = _BTRPerBlock;
    startEmitBTR = _startEmitBTR;
  }

  /// @inheritdoc IBitrielFarmer
  function userTokens(address _pool, address _user) external view override returns(uint256[] memory) {
    return _userTokens[_pool][_user];
  }

  /// @inheritdoc IBitrielFarmer
  function createFarm(address _pool, uint256 _allocPoint) public override onlyOwner {
    require(IBitrielPool(_pool).factory() == address(factory), "IPF"); // pool factory is not BitrielFactory
    require(farms[_pool].lastRewardBlock == 0, "FAE"); // farm is already exist
    
    farms[_pool] = Farm({
      allocPoint: _allocPoint,
      lastRewardBlock: Math.max(block.number, startEmitBTR),
      accBTRPerLiqX12: 0,
      totalLiquidity: 0
    });
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    totalFarm++;

    emit FarmCreated(IBitrielPool(_pool), _allocPoint);
  }

  /// @inheritdoc IBitrielFarmer
  function setFarm(address _pool, uint256 _allocPoint) public override onlyOwner {
    require(farms[_pool].lastRewardBlock != 0, "FNE"); // farm is not exist
    uint256 prevAllocPoint = farms[_pool].allocPoint;
    farms[_pool].allocPoint = _allocPoint;

    if(prevAllocPoint != _allocPoint) {
      totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
    }

    emit FarmUpdated(IBitrielPool(_pool), prevAllocPoint, _allocPoint);
  }

  /// @inheritdoc IBitrielFarmer
  function rewardToken(uint256 _tokenId) external view override returns(uint256) {
    (address pool, , , uint128 liquidity) =
      NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);
    Farm memory farm = farms[pool];
    uint256 accBTRPerLiqX12 = farm.accBTRPerLiqX12;

    if(block.number > farm.lastRewardBlock && farm.totalLiquidity > 0) {
      accBTRPerLiqX12 = _accumulateBTR(pool);
    }

    (uint160 secondsInsideX128, uint256 secondsStakedX128, ) = _secondsInsideStaked(pool, _tokenId);
    return uint256(liquidity).mulDiv(secondsInsideX128, secondsStakedX128).mulDiv(accBTRPerLiqX12, 1e12).sub(stakes[_tokenId].rewardClaimed);
  }

  /// @inheritdoc IBitrielFarmer
  function reward(address _pool, address _user) external view override returns(uint256 amount) {
    Farm memory farm = farms[_pool];
    uint256 accBTRPerLiqX12 = farm.accBTRPerLiqX12;

    if(block.number > farm.lastRewardBlock && farm.totalLiquidity > 0) {
      accBTRPerLiqX12 = _accumulateBTR(_pool);
      uint256[] memory tokens = _userTokens[_pool][_user];

      for(uint i=0; i<tokens.length; i++) {
        (uint160 secondsInsideX128, uint256 secondsStakedX128, ) = _secondsInsideStaked(_pool, tokens[i]);
        uint256 tokenReward = uint256(stakes[tokens[i]].liquidity).mulDiv(secondsInsideX128, secondsStakedX128).mulDiv(accBTRPerLiqX12, 1e12).sub(stakes[tokens[i]].rewardClaimed);
        amount = amount.add(tokenReward);
      }
    }
  }

  /// @inheritdoc IBitrielFarmer
  function updateFarm(address _pool) public override {
    Farm storage farm = farms[_pool];
    if(block.number <= farm.lastRewardBlock) return;

    if(farm.totalLiquidity == 0) {
      farm.lastRewardBlock = block.number;
      return;
    }

    uint256 multiplier = getMultiplier(farm.lastRewardBlock, block.number);
    uint256 farmReward = multiplier.mul(BTRPerBlock).mulDiv(farm.allocPoint, totalAllocPoint);
    farm.accBTRPerLiqX12 = farm.accBTRPerLiqX12.add(farmReward.mulDiv(1e12, farm.totalLiquidity));
    farm.lastRewardBlock = block.number;
  }

  /// @inheritdoc IERC721Receiver
  function onERC721Received(
    address,
    address from,
    uint256 tokenId,
    bytes calldata
  ) external override returns (bytes4) {
    require(msg.sender == address(nonfungiblePositionManager), 'NBNFT'); // not a Bitriel NFT address

    (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nonfungiblePositionManager.positions(tokenId);
    deposits[tokenId] = Deposit({
      owner: from, 
      tickLower: tickLower, 
      tickUpper: tickUpper
    });
    emit TokenDeposited(tokenId, from);

    // stake the tokenId if there are available farm
    _stake(tokenId, from);

    return this.onERC721Received.selector;
  }

  /// @inheritdoc IBitrielFarmer
  function stake(uint256 _tokenId) external override {
    require(deposits[_tokenId].owner == msg.sender, "NTO"); // msg.sender is not token owner

    _stake(_tokenId, msg.sender);
  }

  /// @inheritdoc IBitrielFarmer
  function claimToken(uint256 _tokenId, address _to) public override returns(uint256 amount) {
    require(deposits[_tokenId].owner == msg.sender, "NTO"); // msg.sender is not the token owner
    require(_to != address(0) && _to != address(this), "IRA"); // invalid recipient address

    (address pool, , , uint128 liquidity) =
        NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);
    require(liquidity > 0, "TNS"); // token is not yet staked
    updateFarm(pool);

    Farm memory farm = farms[pool];
    (uint160 secondsInsideX128, uint256 secondsStakedX128, uint160 secondsPerLiquidityInsideX128) = _secondsInsideStaked(pool, _tokenId);
    uint256 accReward = uint256(liquidity).mulDiv(secondsInsideX128, secondsStakedX128).mulDiv(farm.accBTRPerLiqX12, 1e12);

    amount = accReward.sub(stakes[_tokenId].rewardClaimed);
    stakes[_tokenId] = Stake({
      lastSecondsPerLiquidityInsideX128: secondsPerLiquidityInsideX128,
      lastRewardTime: block.timestamp,
      rewardClaimed: accReward,
      liquidity: liquidity
    });

    if(amount > 0) {
      bitriel.mint(_to, amount);
      bitriel.mint(owner(), amount.div(10));
    }

    emit Claimed(_to, amount);
  }

  /// @inheritdoc IBitrielFarmer
  function claim(address _pool, address _to) public override returns(uint256 amount) {
    require(_to != address(0) && _to != address(this), "IRA"); // invalid recipient address
    updateFarm(_pool);

    Farm memory farm = farms[_pool];
    uint256[] memory tokens = _userTokens[_pool][msg.sender];

    for(uint i=0; i<tokens.length; i++) {
      (uint160 secondsInsideX128, uint256 secondsStakedX128, uint160 secondsPerLiquidityInsideX128) = _secondsInsideStaked(_pool, tokens[i]);
      uint256 accReward = uint256(stakes[tokens[i]].liquidity).mulDiv(secondsInsideX128, secondsStakedX128).mulDiv(farm.accBTRPerLiqX12, 1e12);

      amount = amount.add(accReward.sub(stakes[tokens[i]].rewardClaimed));
      stakes[tokens[i]] = Stake({
        lastSecondsPerLiquidityInsideX128: secondsPerLiquidityInsideX128,
        lastRewardTime: block.timestamp,
        rewardClaimed: accReward,
        liquidity: stakes[tokens[i]].liquidity
      });
    }

    if(amount > 0) {
      bitriel.mint(_to, amount);
      bitriel.mint(owner(), amount.div(10));
    }

    emit Claimed(_to, amount);
  } 

  /// @inheritdoc IBitrielFarmer
  function withdrawToken(uint256 _tokenId, bytes memory data) public override {
    // claim reward before withdrawing token
    claimToken(_tokenId, msg.sender);

    (address pool, , , uint128 liquidity) =
      NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);

    // transfer LP-NFT tokenId from this contract to `to` address with `data`
    nonfungiblePositionManager.safeTransferFrom(address(this), deposits[_tokenId].owner, _tokenId, data);

    // delete deposit position after transfer liquidity NFT back to the owner
    delete stakes[_tokenId];
    delete deposits[_tokenId];
    farms[pool].totalLiquidity -= liquidity;

    emit TokenWithdrawn(_tokenId);
  }

  /// @inheritdoc IBitrielFarmer
  function withdraw(address _pool, bytes memory data) public override {
    // claim reward before withdrawing token
    claim(_pool, msg.sender);
    uint256[] memory tokens = _userTokens[_pool][msg.sender];

    uint128 liquidity;
    for(uint i=0; i<tokens.length; i++) {
      // transfer LP-NFT tokenId from this contract to `to` address with `data`
      nonfungiblePositionManager.safeTransferFrom(address(this), deposits[tokens[i]].owner, tokens[i], data);
      liquidity += stakes[tokens[i]].liquidity;

      // delete deposit position after transfer liquidity NFT back to the owner
      delete stakes[tokens[i]];
      delete deposits[tokens[i]];

      emit TokenWithdrawn(tokens[i]);
    }

    if(liquidity > 0) 
      farms[_pool].totalLiquidity -= liquidity;
  }

  /// @inheritdoc IBitrielFarmer
  function setMigrator(IMigrator _migrator) public override onlyOwner {
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
  }

  /// @inheritdoc IBitrielFarmer
  function getMultiplier(uint256 _from, uint256 _to) public view override
    returns (uint256)
  {
    return bonusMultiplier.mul(_to.sub(_from));
  }

  /// @inheritdoc IBitrielFarmer
  function updateMultiplier(uint256 _multiplier) public override onlyOwner {
    bonusMultiplier = _multiplier;
  }

  /// @dev calculate `secondsInsideX128`, `secondsStakedX128` and `secondsPerLiquidityInsideX128` of `tokenId` inside the `pool`
  function _secondsInsideStaked(address pool, uint256 tokenId) internal view 
    returns(uint160 secondsInsideX128, uint256 secondsStakedX128, uint160 secondsPerLiquidityInsideX128) {

    // get `secondsPerLiquidity` from the pool tick range
    (, secondsPerLiquidityInsideX128, ) = IBitrielPool(pool).snapshotCumulativesInside(deposits[tokenId].tickLower, deposits[tokenId].tickUpper);
    secondsInsideX128 = (secondsPerLiquidityInsideX128 - stakes[tokenId].lastSecondsPerLiquidityInsideX128) * stakes[tokenId].liquidity;
    secondsStakedX128 = (block.timestamp - stakes[tokenId].lastRewardTime) << 128;
  }

  /// @dev calculate `accBTRPerLiqX12` with `pool` address
  function _accumulateBTR(address pool) internal view returns(uint256) {
    uint256 multiplier = getMultiplier(farms[pool].lastRewardBlock, block.number);
    uint256 farmReward = multiplier.mul(BTRPerBlock).mulDiv(farms[pool].allocPoint, totalAllocPoint);
    return farms[pool].accBTRPerLiqX12.add(farmReward.mulDiv(1e12, uint256(farms[pool].totalLiquidity)));
  }

  /// @dev stake a deposited `_tokenId`
  function _stake(uint256 _tokenId, address _user) private {
    require(stakes[_tokenId].liquidity == 0, 'TAS'); // token is already staked

    // get/check if the liquidity and the pool is valid
    (address pool, int24 tickLower, int24 tickUpper, uint128 liquidity) =
        NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);
    require(liquidity > 0, 'ZL'); // cannot stake token with 0 liquidity
    // require(farms[pool].allocPoint > 0, 'NIF'); // non-existent or inactive farm
    if(farms[pool].allocPoint == 0) return;

    if(_userTokens[pool][_user].length > 0) 
      claim(pool, _user);
    else 
      updateFarm(pool);

    (, uint160 secondsPerLiquidityInsideX128, ) = IBitrielPool(pool).snapshotCumulativesInside(tickLower, tickUpper);
    stakes[_tokenId] = Stake({
      lastSecondsPerLiquidityInsideX128: secondsPerLiquidityInsideX128,
      lastRewardTime: block.timestamp,
      liquidity: liquidity,
      rewardClaimed: 0
    });
    _userTokens[pool][_user].push(_tokenId);
    farms[pool].totalLiquidity += liquidity;

    // emit TokenStaked event
    emit TokenStaked(_tokenId, liquidity);
  }
}