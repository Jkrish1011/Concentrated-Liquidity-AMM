// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./TickMath.sol";

library Tick {
    struct Info {
        // the total position liquidity that references this tick
        uint128 liquidityGross;

        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
        int128 liquidityNet;

        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        
        // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
        // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
        bool initialized;

        /*
            // the cumulative tick value on the other side of the tick
            int56 tickCumulativeOutside;
            // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
            // only has relative meaning, not absolute — the value depends on when the tick is initialized
            uint160 secondsPerLiquidityOutsideX128;
            // the seconds spent on the other side of the tick (relative to the current tick)
            // only has relative meaning, not absolute — the value depends on when the tick is initialized
            uint32 secondsOutside;
        */
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed within the pool constructor
    /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
    ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return The max liquidity per tick
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        /*
            These bounds are derived from the limits of the 160‑bit sqrtPriceX96 representation:
        */
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;

        return type(uint128).max / numTicks;
    }

    /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tick The tick that will be updated
    /// @param tickCurrent The current tick
    /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
    /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
    /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
    /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
    /// @param maxLiquidity The maximum liquidity allocation for a single tick
    /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper,
        uint128 maxLiquidity        
        // related to the price oracle. TODO:
        // uint160 secondsPerLiquidityCumulativeX128,
        // int56 tickCumulative,
        // uint32 time,
    ) internal returns (bool flipped) {
        Info memory info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = liquidityDelta < 0 ? 
                                        liquidityGrossBefore - uint128(-liquidityDelta) :
                                        liquidityGrossBefore + uint128(liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, "Liquidity > Max");

        // flipped = (liquidityGrossBefore == 0 && liquidityGrossAfter > 0 ) ||
        //             (liquidityGrossBefore > 0 && liquidityGrossAfter == 0);
        
        flipped = (liquidityGrossAfter == 0 ) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // When the liquidity moves past either the lower or upper tick, it should be adjusted
        // to fallback within the lower & upper tick range.
        info.liquidityNet = upper ? info.liquidityNet - liquidityDelta : info.liquidityNet + liquidityDelta;
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clear(mapping(int24 => Info) storage self, int24 tick) internal {
        delete self[tick];
    }
}