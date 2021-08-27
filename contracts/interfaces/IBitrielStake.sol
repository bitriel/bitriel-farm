// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

/// @title BitrielStake is the staking contract for Bitriel Token. 
/// @notice This contract handles swapping to and from xBTR, BitrielSwap's staking token.
/// @dev You come in with some BTR, and leave with more! The longer you stay, the more BTR you get.
interface IBitrielStake {
    /// @notice Enter the staking. Pay some BTRs. Earn some shares.
    /// @dev Locks BTR and mints xBTR
    /// @param amount The amount of BTRs to be staked
    function enter(uint256 amount) external;

    /// @notice Leave the staking. Claim back your BTRs.
    /// @dev Unlocks the staked + gained BTR and burns xBTR
    /// @param amount The amount of xBTRs (share in the liquidity mining program)
    function leave(uint256 amount) external;
}