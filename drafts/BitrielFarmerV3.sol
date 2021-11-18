// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielFactory.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IBitrielPool.sol';
import '@bitriel/bitrielswap-core/contracts/interfaces/IERC20Minimal.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@bitriel/bitrielswap-periphery/contracts/interfaces/IMigrator.sol';
import '@bitriel/bitrielswap-periphery/contracts/base/Multicall.sol';

import "./BitrielToken.sol";
import "./interfaces/IBitrielFarmerV3.sol";
import "./libraries/ArrayUtil.sol";
import "./libraries/NFTPositionInfo.sol";

contract BitrielFarmerV3 is IBitrielFarmerV3, Multicall, Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20Minimal;

  struct Farm {
    uint160 totalSecondsClaimedX128;
    uint96 numberOfStakes;
    uint128 totalLiquidity;
  }

  struct TokenReward {
    IERC20Minimal reward;
    uint256 totalRewardUnclaimed;
    uint256 startTime;
    uint256 endTime;
    address refundee;
    uint256 rewardRate;
    uint256 lastUpdateTime;
    uint256 rewardPerShare;
  }

  /// @notice Represents the deposit of a liquidity NFT
  struct Deposit {
    address owner;
    int24 tickLower;
    int24 tickUpper;
  }

  struct Stake {
    uint256 rewardPerSharePaid;
    uint256 reward;
  }

  /// @inheritdoc IBitrielFarmerV3
  IBitrielFactory public immutable override factory;
  /// @inheritdoc IBitrielFarmerV3
  INonfungiblePositionManager public immutable override nonfungiblePositionManager;

  mapping(address => Farm) public farms;
  mapping(address => TokenReward[]) public tokenRewards;
  mapping(uint256 => Deposit) public deposits;
  mapping(address => mapping(IERC20Minimal => mapping(uint256 => User))) public users;

  modifier updateReward(IBitrielPool pool, address user) {
    address poolAddress = address(pool);
    uint256 len = tokenRewards[poolAddress].length;
    for(uint i=0; i<len; i++) {
      TokenReward storage tr = tokenRewards[poolAddress][i];
      uint256 newRewardPerShare = rewardPerShare(pool, i);
      tr.rewardPerShare = newRewardPerShare;
      tr.lastUpdateTime = lastUpdateTimeApplicable(pool, i);

      if(user != address(0)) {
        User storage user = users[poolAddress][tr.reward][user];
        user.rewardPerSharePaid = newRewardPerShare;
        user.reward = _reward(pool, i, user, newRewardPerShare);
      }
    }
    _;
  }

  modifier onlyRewardRefundee(IBitrielPool pool, uint i) {
    require(msg.sender == tokenRewards[address(pool)][i].refundee, "Access denied");
    _;
  }

  function lastUpdateTimeApplicable(IBitrielPool pool, uint i) public view returns(uint256) {
    return Math.min(block.timestamp, tokenRewards[address(pool)][i].endTime);
  }

  function rewardPerShare(IBitrielPool pool, uint i) public view returns(uint256) {
    TokenReward memory tr = tokenRewards[address(pool)][i];
    uint256 totalSupply = farms[address(pool)].totalLiquidity;

    if(totalSupply == 0) {
      return tr.rewardPerShare;
    } 
    return tr.rewardPerShare.add(
      lastUpdateTimeApplicable(pool, i).sub(tr.lastUpdateTime).mul(tr.rewardRate).div(totalSupply)
    );
  }

  function reward(IBitrielPool pool, uint i, address user) public view returns(uint256) {
    return _reward(pool, i, user, rewardPerShare(pool, i));
  }

  function _claim(IBitrielPool pool, uint i) internal {
    TokenReward storage tr = tokenRewards[address(pool)][i];
    User storage user = users[address(pool)][tr.reward][msg.sender];
    uint256 reward = user.reward;
    if(reward > 0) {
      tr.reward.safeTransfer(msg.sender, reward);
      user.reward = 0;
      emit Claimed(pool, i, msg.sender, reward);
    }
  }

  function claim(IBitrielPool pool) public updateReward(pool, msg.sender) {
    uint256 len = tokenRewards[address(pool)].length;
    for(uint i=0; i<len; i++) {
      _claim(pool, i);
    }
  }

  function setReward(IBitrielPool pool, uint i, uint256 reward) external onlyRewardRefundee(pool, i) updateReward(pool, address(0)) {
    TokenReward storage tr = tokenRewards[address(pool)][i];

    if(block.timestamp < tr.endTime) {
      uint256 remainTime = tr.endTime - block.timestamp;
      uint256 remaining = remainTime.mul(tr.rewardRate);
      reward = reward.add(remaining);
    }
    uint256 duration = tr.endTime - tr.startTime;
    require(reward >= duration, "Reward is too small");
    tr.rewardRate = reward.div(duration);
    require(tr.rewardRate <= tr.reward.balanceOf(address(this)).div(duration), "Reward is too big");
    tr.lastUpdateTime = block.timestamp;
    tr.startTime = block.timestamp;
    tr.endTime = block.timestamp.add(duration);

    emit RewardUpdated(pool, i, reward);
  }

  function _reward(IBitrielPool pool, uint i, uint256 tokenId, uint256 _rewardPerLiquidity) private view returns (uint256) {
    TokenRewards storage tr = tokenRewards[address(pool)][i];
    return balanceOf(user)
      .mul(_rewardPerLiquidity.sub(tr.userRewardPerLiquidityPaid[user]))
      .add(tr.rewards[user]);
  }
}