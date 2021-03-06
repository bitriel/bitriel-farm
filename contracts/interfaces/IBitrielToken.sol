//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBitrielToken is IERC20 {
  function mint(address _to, uint256 _amount) external;
}