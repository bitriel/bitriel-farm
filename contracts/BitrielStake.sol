// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IBitrielStake.sol";
import "./BitrielToken.sol";

// BitrielStake is the staking contract for Bitriel Token. You come in with some BTR, and leave with more! The longer you stay, the more BTR you get.
//
// This contract handles swapping to and from xBTR, BitrielSwap's staking token.
contract BitrielStake is IBitrielStake, ERC20("BitrielStake", "xBTR"){
    using SafeMath for uint256;
    BitrielToken public bitriel;

    // Define the Bitriel token contract
    constructor(BitrielToken _bitriel) {
        bitriel = _bitriel;
    }

    /// @inheritdoc IBitrielStake
    function enter(uint256 _amount) public override {
        // Gets the amount of BTR locked in the contract
        uint256 totalBTR = bitriel.balanceOf(address(this));
        // Gets the amount of xBTR in existence
        uint256 totalShares = totalSupply();
        // If no xBTR exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalBTR == 0) {
            _mint(msg.sender, _amount);
        } 
        // Calculate and mint the amount of xBTR the BTR is worth. The ratio will change overtime, as xBTR is burned/minted and BTR deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalBTR);
            _mint(msg.sender, what);
        }
        // Lock the BTR in the contract
        bitriel.transferFrom(msg.sender, address(this), _amount);
    }

    /// @inheritdoc IBitrielStake
    function leave(uint256 amount) public override {
        // Gets the amount of BTR locked in the contract
        uint256 totalBTR = bitriel.balanceOf(address(this));
        // Gets the amount of xBTR in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of BTR the xBTR is worth
        uint256 what = amount.mul(totalBTR).div(totalShares);
        _burn(msg.sender, amount);
        bitriel.transfer(msg.sender, what);
    }
}