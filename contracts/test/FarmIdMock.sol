// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;
pragma abicoder v2;

import '../interfaces/IBitrielFarmer.sol';
import '../libraries/FarmId.sol';

/// @dev Test contract for FarmId
contract FarmIdMock {
    function compute(IBitrielFarmer.FarmKey memory key) public pure returns (bytes32) {
        return FarmId.compute(key);
    }
}