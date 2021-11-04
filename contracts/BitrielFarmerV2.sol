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

import "./BitrielToken.sol";
import "./interfaces/IBitrielFarmerV2.sol";
import "./libraries/NFTPositionInfo.sol";

contract BitrielFarmerV2 is IBitrielFarmerV2, Multicall, Ownable {
  using FullMath for uint256;
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using SafeERC20 for BitrielToken;

  /// @notice Represents a yield farming incentive
  struct Farm {
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accBTRPerShareX12;
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
    uint128 liquidity;
    uint256 rewardClaimed;
  }

  /// @inheritdoc IBitrielFarmerV2
  IBitrielFactory public immutable override factory;
  /// @inheritdoc IBitrielFarmerV2
  INonfungiblePositionManager public immutable override nonfungiblePositionManager;
  /// @inheritdoc IBitrielFarmerV2
  IMigrator public override migrator;
  /// @inheritdoc IBitrielFarmerV2
  BitrielToken public immutable override bitriel;

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
    BitrielToken _bitriel,
    uint256 _BTRPerBlock,
    uint256 _startEmitBTR
  ) {
    factory = _factory;
    nonfungiblePositionManager = _nonfungiblePositionManager;
    bitriel = _bitriel;
    BTRPerBlock = _BTRPerBlock;
    startEmitBTR = _startEmitBTR;
  }

  /// @inheritdoc IBitrielFarmerV2
  function userTokens(address _pool, address _user) external view override returns(uint256[] memory) {
    return _userTokens[_pool][_user];
  }

  /// @inheritdoc IBitrielFarmerV2
  function createFarm(address _pool, uint256 _allocPoint) public override onlyOwner {
    require(IBitrielPool(_pool).factory() == address(factory), "IPF"); // pool factory is not BitrielFactory
    require(farms[_pool].lastRewardBlock == 0, "FAE"); // farm is already exist
    
    farms[_pool] = Farm({
      allocPoint: _allocPoint,
      lastRewardBlock: Math.max(block.number, startEmitBTR),
      accBTRPerShareX12: 0,
      totalLiquidity: 0
    });
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    totalFarm++;

    emit FarmCreated(IBitrielPool(_pool), _allocPoint);
  }

  /// @inheritdoc IBitrielFarmerV2
  function setFarm(address _pool, uint256 _allocPoint) public override onlyOwner {
    require(farms[_pool].lastRewardBlock != 0, "FNE"); // farm is not exist
    uint256 prevAllocPoint = farms[_pool].allocPoint;
    farms[_pool].allocPoint = _allocPoint;

    if(prevAllocPoint != _allocPoint) {
      totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
    }

    emit FarmUpdated(IBitrielPool(_pool), prevAllocPoint, _allocPoint);
  }

  /// @inheritdoc IBitrielFarmerV2
  function rewardToken(uint256 _tokenId) external view override returns(uint256) {
    (address pool, , , ) =
      NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);
    Farm memory farm = farms[pool];
    Stake memory stakeInfo = stakes[_tokenId];
    uint256 accBTRPerShareX12 = farm.accBTRPerShareX12;

    if(block.number > farm.lastRewardBlock && farm.totalLiquidity > 0) {
      accBTRPerShareX12 = _reward(accBTRPerShareX12, farm.lastRewardBlock, farm.allocPoint, farm.totalLiquidity);
    }

    return uint256(stakeInfo.liquidity).mulDiv(accBTRPerShareX12, 1e12).sub(stakeInfo.rewardClaimed);
  }

  /// @inheritdoc IBitrielFarmerV2
  function reward(address _pool, address _user) external view override returns(uint256 amount) {
    Farm memory farm = farms[_pool];
    uint256 accBTRPerShareX12 = farm.accBTRPerShareX12;

    if(block.number > farm.lastRewardBlock && farm.totalLiquidity > 0) {
      accBTRPerShareX12 = _reward(accBTRPerShareX12, farm.lastRewardBlock, farm.allocPoint, farm.totalLiquidity);
      uint256[] memory tokens = _userTokens[_pool][_user];
      for(uint i=0; i<tokens.length; i++) 
        amount = amount.add(uint256(stakes[tokens[i]].liquidity).mulDiv(accBTRPerShareX12, 1e12).sub(stakes[tokens[i]].rewardClaimed));
    }
  }

  /// @inheritdoc IBitrielFarmerV2
  function updateFarm(address _pool) public override {
    Farm storage farm = farms[_pool];
    if(block.number <= farm.lastRewardBlock) return;

    if(farm.totalLiquidity == 0) {
      farm.lastRewardBlock = block.number;
      return;
    }

    uint256 multiplier = getMultiplier(farm.lastRewardBlock, block.number);
    uint256 farmReward = multiplier.mul(BTRPerBlock).mulDiv(farm.allocPoint, totalAllocPoint);
    bitriel.mint(address(this), farmReward);
    bitriel.mint(owner(), farmReward.div(10));
    farm.accBTRPerShareX12 = farm.accBTRPerShareX12.add(farmReward.mulDiv(1e12, farm.totalLiquidity));
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

  /// @inheritdoc IBitrielFarmerV2
  function stake(uint256 _tokenId) external override {
    require(deposits[_tokenId].owner == msg.sender, "NTO"); // msg.sender is not token owner

    _stake(_tokenId, msg.sender);
  }

  /// @inheritdoc IBitrielFarmerV2
  function claimToken(uint256 _tokenId, address _to) public override returns(uint256 amount) {
    require(deposits[_tokenId].owner == msg.sender, "NTO"); // msg.sender is not the token owner
    require(_to != address(0) && _to != address(this), "IRA"); // invalid recipient address
    require(stakes[_tokenId].liquidity > 0, "TNS"); // token is not yet staked

    (address pool, , , ) =
        NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);
    updateFarm(pool);

    Farm memory farm = farms[pool];
    Stake memory stakeInfo = stakes[_tokenId];

    uint256 accReward = uint256(stakeInfo.liquidity).mulDiv(farm.accBTRPerShareX12, 1e12);
    amount = accReward.sub(stakeInfo.rewardClaimed);
    stakes[_tokenId].rewardClaimed = accReward;

    if(amount > 0) 
      safeBTRTransfer(_to, amount);

    emit Claimed(_to, amount);
  }

  /// @inheritdoc IBitrielFarmerV2
  function claim(address _pool, address _to) public override returns(uint256 amount) {
    require(_to != address(0) && _to != address(this), "IRA"); // invalid recipient address
    updateFarm(_pool);

    Farm memory farm = farms[_pool];
    uint256[] memory tokens = _userTokens[_pool][msg.sender];

    for(uint i=0; i<tokens.length; i++) {
      uint256 accReward = uint256(stakes[tokens[i]].liquidity).mulDiv(farm.accBTRPerShareX12, 1e12);
      amount = amount.add(accReward.sub(stakes[tokens[i]].rewardClaimed));
      stakes[tokens[i]].rewardClaimed = accReward;
    }

    if(amount > 0) 
      safeBTRTransfer(_to, amount);

    emit Claimed(_to, amount);
  } 

  /// @inheritdoc IBitrielFarmerV2
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

  /// @inheritdoc IBitrielFarmerV2
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

  /// @inheritdoc IBitrielFarmerV2
  function setMigrator(IMigrator _migrator) public override onlyOwner {
    migrator = _migrator;
  }

  /// @inheritdoc IBitrielFarmerV2
  function migrate(IMigrator.MigrateParams calldata params, bytes memory data) external override {
    require(address(migrator) != address(0), "NM"); // no migrator
        
    // get tokenId from Migrator.migrate() contract
    TransferHelper.safeApprove(params.pair, address(this), params.liquidityToMigrate);
    uint256 tokenId = migrator.migrate(params);
    // transfer the token from recipient to this contract 
    // for deposit and staking position on BitrielFarm
    nonfungiblePositionManager.safeTransferFrom(params.recipient, address(this), tokenId, data);
  }

  /// @inheritdoc IBitrielFarmerV2
  function getMultiplier(uint256 _from, uint256 _to) public view override
    returns (uint256)
  {
    return bonusMultiplier.mul(_to.sub(_from));
  }

  /// @inheritdoc IBitrielFarmerV2
  function updateMultiplier(uint256 _multiplier) public override onlyOwner {
    bonusMultiplier = _multiplier;
  }

  /// @dev transfer `_amount` of BTRs to `_to` address with SafeMode 
  function safeBTRTransfer(address _to, uint256 _amount) internal {
    uint256 bal = bitriel.balanceOf(address(this));
    if (_amount > bal) {
      bitriel.transfer(_to, bal);
    } else {
      bitriel.transfer(_to, _amount);
    }
  }

  /// @dev calculate `accBTRPerShareX12` with given params
  function _reward(uint256 _accBTRPerShareX12, uint256 _lastRewardBlock, uint256 _allocPoint, uint128 _totalLiquidity) internal view returns(uint256) {
    uint256 multiplier = getMultiplier(_lastRewardBlock, block.number);
    uint256 farmReward = multiplier.mul(BTRPerBlock).mulDiv(_allocPoint, totalAllocPoint);
    return _accBTRPerShareX12.add(farmReward.mulDiv(1e12, uint256(_totalLiquidity)));
  }

  /// @dev stake a deposited `_tokenId`
  function _stake(uint256 _tokenId, address _user) private {
    require(stakes[_tokenId].liquidity == 0, 'TAS'); // token is already staked

    // get/check if the liquidity and the pool is valid
    (address pool, , , uint128 liquidity) =
        NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, _tokenId);
    require(liquidity > 0, 'ZL'); // cannot stake token with 0 liquidity
    // require(farms[pool].allocPoint > 0, 'NIF'); // non-existent or inactive farm
    if(farms[pool].allocPoint == 0) return;

    if(_userTokens[pool][_user].length > 0) {
      claim(pool, _user);
    }

    stakes[_tokenId].liquidity = liquidity;
    _userTokens[pool][_user].push(_tokenId);
    farms[pool].totalLiquidity += liquidity;

    // emit TokenStaked event
    emit TokenStaked(_tokenId, liquidity);
  }
}