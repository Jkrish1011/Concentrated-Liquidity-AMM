# CLAMM - Concentrated liquidity AMM

https://github.com/Uniswap/v3-core

https://github.com/Uniswap/v3-periphery

## Uni V3 pool
ETH / USDC 0.05% pool Arbitrum

0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443

## Omit
- Factory

- Price oracle

- Protocol fee

- Flash swap

- NFT

- Solidity advanced math libraries

- Callbacks

## Setup
forge init clamm
forge build
forge fmt

## Test
- sqrtPriceX96
- get tick from sqrt price x 96
- get price from sqrt price x 96

- tick bitmap

- getSqrtRatioAtTick

- getTickAtSqrtRatio

- getAmount0Delta, getAmount1Delta

- liquidity delta

- tick, liquidity, price directions and token 0 token 1

- getNextSqrtPriceFromAmount0RoundingUp

- getNextSqrtPriceFromAmount1RoundingDown

- why fee = amountIN * fee / (1 - fee)

- nextInitializedTickWithinOneWord

- liquidityNet

- fee growth (per liquidity)

- how does burn update tokensOwed

## Links
https://uniswapv3book.com/

https://blog.uniswap.org/uniswap-v3-math-primer

https://blog.uniswap.org/uniswap-v3-math-primer-2

https://trapdoortech.medium.com/uniswap-deep-dive-into-v3-technical-white-paper-2fe2b5c90d2