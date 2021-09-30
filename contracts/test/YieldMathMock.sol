// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;
pragma abicoder v2;

import '../libraries/YieldMath.sol';

/// @dev Test contract for YieldMath
contract YieldMathMock {
    function computeYieldAmount(
        uint256 totalYieldUnclaimed,
        uint160 totalSecondsClaimedX128,
        uint128 liquidity,
        uint160 secondsPerLiquidityInsideInitialX128,
        uint160 secondsPerLiquidityInsideX128,
        uint256 startTime,
        uint256 currentTime
    ) public pure returns (uint256 yield, uint160 secondsInsideX128) {
        (yield, secondsInsideX128) = YieldMath.computeYieldAmount(
            totalYieldUnclaimed,
            totalSecondsClaimedX128,
            liquidity,
            secondsPerLiquidityInsideInitialX128,
            secondsPerLiquidityInsideX128,
            startTime,
            currentTime
        );
    }
}