// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./TickMath.sol";

library Tick {
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        /*
            These bounds are derived from the limits of the 160‑bit sqrtPriceX96 representation:
        */
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;

        return type(uint128).max / numTicks;
    }
}