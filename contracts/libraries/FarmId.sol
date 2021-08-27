// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;
pragma abicoder v2;

import '../interfaces/IBitrielFarmer.sol';

library FarmId {
    /// @notice Calculate the key for a yield farming
    /// @param key The components used to compute the farm identifier
    /// @return farmId The identifier for the yield farming
    function compute(IBitrielFarmer.FarmKey memory key) internal pure returns (bytes32 farmId) {
        farmId = keccak256(abi.encode(key));
    }
}