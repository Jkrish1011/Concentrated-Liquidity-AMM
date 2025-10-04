// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./interfaces/IERC20.sol";

import "./lib/Tick.sol";
import "./lib/Position.sol";
import "./lib/SafeCast.sol";
import "./lib/TickMath.sol";
import "./lib/SqrtPriceMath.sol";

contract CLAMM {
    using SafeCast for int256;
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Tick for mapping(int24 => Tick.Info);


    // Tokens which will be under consideration in this pool
    address public immutable token0;
    address public immutable token1;
    // Fee of the pool
    uint24 public immutable fee;
    // Spacing between ticks
    int24 public immutable tickSpacing;

    uint128 public immutable maxLiquidityPerTick;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    struct Slot0 {
        /*
            X = token0
            Y = token1
            P = Price of X in terms of Y ,i.e., Y = Y / X;

            Q96 = 2^96;
            sqrtPriceX96 = sqrt(P) * Q96;
            
            P = (sqrtPriceX96 / Q96)^2 = 1.0001 ^ tick
            tick = ( 2 * log(P)) / log(1.0001)
            sqrtPriceX96 is mostly a CONSTANT defined in all the Chains, i.e., in Arbitrum it is 3443439269043970780644209.

            after we get P, we need to multiply and divide it with the decimals of token0 and token1.
            eg: if token0 = ETH, decimals_0 = 1e18 and token2 = USDC, decimals_1 = 1e6
        */
        uint160 sqrtPriceX96;

        /*
            A tick represents a discrete price level in a Uniswap V3 pool. 
            Prices are encoded as the square‑root of the token‑to‑token ratio (sqrtPriceX96). 
            Each tick corresponds to a fixed multiplicative change in that price:

            price at tick t=(1.0001) ^ t
 
            Because the price is stored as a square‑root, the tick step is chosen so that moving one tick changes the price by exactly 0.01% (1.0001). 
            This granularity lets liquidity providers (LPs) concentrate their capital within very narrow price ranges.
        */
        int24 tick;

        // whether the pool is locked - used for reentrancy protection
        bool unlocked;

        /*
        /// Related to price Oracle - NOT UNDER CONSIDERATION FOR NOW

        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        */

        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        // uint8 feeProtocol;
    }

    struct SwapCache {
        /*
        // NOT UNDER CONSIDERATION NOW.
        // the protocol fee for the input token
        uint8 feeProtocol;
        */
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        /*
        // RELATED TO PRICE ORACLE, NOT UNDER CONSIDERATION NOW.
        // the timestamp of the current block
        uint32 blockTimestamp;
        // the current value of the tick accumulator, computed only if we cross an initialized tick
        int56 tickCumulative;
        // the current value of seconds per liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerLiquidityCumulativeX128;
        // whether we've computed and cached the above two accumulators
        bool computedLatestObservation;
        */
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // the current liquidity in range
        uint128 liquidity;
        /*
        // NOT UNDER CONSIDERATION
        // amount of input token paid as protocol fee
        uint128 protocolFee;
        */
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    Slot0 public slot0;
    uint128 public liquidity;
    mapping(bytes32 => Position.Info) public positions;

    // For each tick, there is some form of information stored
    mapping(int24 => Tick.Info) public ticks;

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    function checkTicks(int24 tickLower, int24 tickUpper) pure internal {
        require(tickLower < tickUpper, "Invalid tick range");
        require(tickLower >= TickMath.MIN_TICK, "TickLower too low");
        require(tickUpper <= TickMath.MAX_TICK, "TickUpper too high");
        
    }

    function _updatePosition(address owner, int24 tickLower, int24 tickUpper, int128 liquidityDelta, int24 tick) private returns (Position.Info storage position) {
        position = positions.get(owner, tickLower, tickUpper);

        // TODO: Fees
        uint256 _feeGrowthGlobal0X128 = 0;
        uint256 _feeGrowthGlobal1X128 = 0;

        bool flippedLower;
        bool flippedUpper;

        if (liquidityDelta != 0) {
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                false,
                maxLiquidityPerTick
            );

            flippedUpper = ticks.update(
                tickUpper, 
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                true,
                maxLiquidityPerTick
            );
        }

        position.update(liquidityDelta, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);

        /*
            if liquidityDelta < 0, it means liquidity is being removed
            if liquidity is removed and the tick is flipped, we need to clear the tick
            because it's value is 0
        */
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }

        return position;
    }

    function _modifyPosition(ModifyPositionParams memory params) private returns (Position.Info storage position, int256 amount0, int256 amount1) {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0;
        
        // params.liquidityDelta can be liquidity added or liquidity removed
        position = _updatePosition(params.owner, params.tickLower, params.tickUpper, params.liquidityDelta, _slot0.tick);

        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );

            } else if (_slot0.tick < params.tickUpper) {
                // _slot0.tick is in the range of params.tickLower and params.tickUpper
                 amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );

                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );
                liquidity = params.liquidityDelta < 0 ?
                                liquidity - uint128(-params.liquidityDelta) :
                                liquidity + uint128(params.liquidityDelta);

            } else {
                // _slot0.tick > params.tickUpper
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    /// @dev Mutually exclusive reentrancy protection into the pool to/from a method. This method also prevents entrance
    /// to a function before the pool is initialized. The reentrancy guard is required throughout the contract because
    /// we use balance checks to determine the payment status of interactions such as mint, swap and flash.
    modifier lock() {
        require(slot0.unlocked, "locked");
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    constructor(address _token0, address _token1, uint24 _fee, int24 _tickSpacing) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    function initialize(uint160 sqrtPriceX96) external {
        require(slot0.sqrtPriceX96 == 0, "Already initialized");

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            unlocked: true
        });
    }

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount) external lock returns(uint256 amount0, uint256 amount1) {
        require(amount > 0, "amount is 0");

        /*
            It calculates the amount of token0 and token1 that are required to mint the given amount of liquidity.
            So amount0Int would require amount0Int amount of token0 and amount1Int amount of token1 to raise a liquidy worth amount.
        */

        (, int256 amount0Int, int256 amount1Int) = 
            _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(uint256(amount)).toInt128()
                })
            );
        
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        if ( amount0 > 0 ) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if ( amount1 > 0 ) {
            IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        }
    }
    function collect(address receipient, int24 tickLower, int24 tickUpper, uint128 amount0Requested, uint128 amount1Requested) 
                external lock
                    returns (uint128 amount0, uint128 amount1) {
        
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(receipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(receipient, amount1);
        }
    } 

    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external lock returns(uint256 amount0, uint256 amount1) {
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(ModifyPositionParams({
            owner: msg.sender,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: -int256(uint256(amount)).toInt128()
        }));

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (position.tokensOwed0 + uint128(amount0), position.tokensOwed1 + uint128(amount1));
        }
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external lock returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "amountSpecified is 0");
        Slot0 memory slot0Start = slot0; 

        require(zeroForOne ? 
                sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO : 
                sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
                "Invalid square root price limit"
            );

        SwapCache memory cache = SwapCache({
            liquidityStart: liquidity
        });

        bool exactInput = amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: sqrtPriceLimitX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: zeroForOne? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            liquidity: cache.liquidityStart
        });

        // Update sqrtPriceX96 and tick
        if(slot0Start.tick != state.tick) {
            (slot0Start.sqrtPriceX96, slot0Start.tick) = (state.sqrtPriceX96, state.tick);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // Update the liquidity
        if (cache.liquidityStart != state.liquidity) {
            liquidity = state.liquidity;
        }

        // Update fee growth
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        (amount0, amount1) = zeroForOne == exactInput ? 
                            (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated) : 
                            (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        if (zeroForOne) {
            if (amount1 < 0) {
                IERC20(token1).transfer(recipient, uint256(-amount1));
                IERC20(token0).transferFrom(msg.sender, address(this), uint256(amount0));
            }
        } else {
               if (amount0 < 0) {
                IERC20(token0).transfer(recipient, uint256(-amount0));
                IERC20(token1).transferFrom(msg.sender, address(this), uint256(amount1));
            }
        }
    }
}