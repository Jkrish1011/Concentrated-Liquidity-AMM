// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import './FullMath.sol';
import './SqrtPriceMath.sol';

/// @title Computes the result of a swap within ticks
/// @notice Contains methods for computing the result of a swap within a single tick price range, i.e., a single tick.
library SwapMath {
    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
    /// @param sqrtRatioCurrentX96 The current sqrt price of the pool
    /// @param sqrtRatioTargetX96 The price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    /// @param amountRemaining How much input or output amount is remaining to be swapped in/out
    /// @param feePips The fee taken from the input amount, expressed in hundredths of a bip
    /// @return sqrtRatioNextX96 The price after swapping the amount in/out, not to exceed the price target
    /// @return amountIn The amount to be swapped in, of either token0 or token1, based on the direction of the swap
    /// @return amountOut The amount to be received, of either token0 or token1, based on the direction of the swap
    /// @return feeAmount The amount of input that will be taken as a fee
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining, // value positive or negative according to the deposit(+) or withdrawal(-) of the liquidity
        /*
            1 bip = 1/100 x 1% = 1/1e4
            1e6 = 100%, 1/100 of a bip
        */
        uint24 feePips
    )
        internal
        pure
        returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        // zero for one - token0 in, token1 out
        // one for zero - token1 in, token0 out
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioNextX96;
        bool exactIn = amountRemaining >= 0;

        if (exactIn) {
            // calculate the amount remaining subtracting the fee
            uint amountInRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);

            // calculate the max amount n, round up amount in for safety measures
            amountIn = zeroForOne ?
                        SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true) :
                        SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);
            // calculate next.sqrt.ratio
            if(amountInRemainingLessFee < amountIn) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountInRemainingLessFee,
                    zeroForOne
                );
            }
        } else {
            // calculate max amount out, round down amount out.
             amountOut = zeroForOne ?
                        SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false) :
                        SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);

            //calculate next sqrt ratio
            if (uint256(-amountRemaining) >= amountOut) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                 sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
            }
        }
        // Calculate amount in and out between sqrt current and next
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;
        // max and exactIn --> in = amountIn
        //                     out = need to calculate
        // max and !exactOut --> out = amountOut
        //                     in = need to calculate
        // !min and exactIn --> in = need to calculate
        //                     out = need to calculate
        // !min and !exactOut --> out = need to calculate
        //                     in = need to calculate
        if (zeroForOne) {
            amountIn = max && exactIn ? amountIn : SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
            amountOut = max && !exactIn ? amountOut : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
        } else {
            amountIn = max && exactIn ? amountIn : SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
            amountOut = max && !exactIn ? amountOut : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
        }

        // Cap the output amount to not exceed the remaining output amount
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }
        // Calculate fee on amount in
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            // fee = amountIn * feePercentage / (1e6 - feePercentage)
            // Not exact in or sqrt ratio next = target
            // not exact input
            // exact input and sqrt ratio next = target
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }

    }
}