// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMasterChef {
    function poolInfo(uint256 pid) external view returns (
        IERC20 lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accBTRPerShare
    );
    function userInfo(uint256 pid, address user) external view returns (
        uint256 amount, 
        uint256 rewardDebt
    );
    function totalAllocPoint() external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
}