// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./lib/Tick.sol";

contract CLAMM {
    // Tokens which will be under consideration in this pool
    address public immutable token0;
    address public immutable token1;
    // Fee of the pool
    uint24 public immutable fee;
    // Spacing between ticks
    int24 public immutable tickSpacing;

    uint128 public immutable maxLiquidityPerTick;

    constructor(address _token0, address _token1, uint24 _fee, int24 _tickSpacing) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }


}