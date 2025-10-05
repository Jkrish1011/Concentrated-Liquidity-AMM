# CLAMM - Concentrated liquidity AMM

CLAMM is a learning-oriented reimplementation of core ideas from Uniswap v3’s concentrated liquidity pools. It focuses on the mechanics of ticks, sqrt price math, liquidity accounting, and stepwise swap math—omitting production extras to keep the core clear.

---

## Overview
- A Uniswap v3–style pool with:
  - `slot0` state: `sqrtPriceX96`, `tick`, and a simple reentrancy lock.
  - Liquidity provisioning with ranges `[tickLower, tickUpper]` via `mint` and `burn`.
  - Position accounting and tick bookkeeping.
  - A minimal `collect` that pays out `tokensOwed0/1` after `burn`.
- Math libraries mirror the v3 approach for precise fixed‑point arithmetic and price/amount deltas.

> Reference production repos: 
> - v3-core: https://github.com/Uniswap/v3-core
> - v3-periphery: https://github.com/Uniswap/v3-periphery

### Reference pool
- ETH/USDC 0.05% on Arbitrum: `0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443`

---

## Project Status
- Core contracts and math helpers compiled with Foundry.
- `mint`, `burn`, and `collect` flows implemented at a basic level.
- `SwapMath` added to model single-step swaps toward a target sqrt price.
- Fees, full swap loop, and oracles are intentionally out of scope (see below).

---

## In Scope vs Omitted

### In Scope
- Pool core state and position/tick accounting.
- Tick <-> sqrt price conversions and amount delta math.
- Minimal collect flow for withdrawn liquidity.

### Omitted (by design)
- Factory
- Price oracle
- Protocol fee
- Flash swap
- NFT positions
- Advanced/third‑party math packages beyond what’s included
- Callbacks (e.g., periphery hooks)

---

## Architecture (High-level)
- `src/CLAMM.sol` — Pool state and user entry points (`initialize`, `mint`, `burn`, `collect`).
- `src/lib/` — Math and bookkeeping:
  - `TickMath.sol` — tick <-> sqrt price conversions.
  - `SqrtPriceMath.sol` — token amount deltas and next price helpers.
  - `FullMath.sol`, `FixedPoint96.sol` — 512‑bit mulDiv and Q96 constants.
  - `SwapMath.sol` — compute a single swap step toward a target sqrt price.
  - `Tick.sol`, `Position.sol` — tick and position accounting helpers.
  - `SafeCast.sol`, `LowGasSafeMath.sol`, `UnsafeMath.sol` — utilities.

---

## Math Primer (tl;dr)
- Price is represented as `sqrtPriceX96 = sqrt(P) * 2^96` for integer fixed‑point math.
- Ticks discretize price: `price(t) = 1.0001^t`.
- Ranges: below lower tick -> all token0; above upper tick -> all token1; inside -> split per sqrt price.
- Precise arithmetic uses `FullMath.mulDiv` (and rounding variants) to avoid 256‑bit overflow and rounding drift.

---

## Getting Started

Prereqs: Foundry (forge, cast). Install: https://book.getfoundry.sh/getting-started/installation

```bash
# format, build
forge fmt
forge build

# run tests (when present)
forge test -vv
```

---

## Development Notes
- Initialize a pool with `initialize(sqrtPriceX96)` before `mint`/`burn` (reentrancy lock depends on it).
- Ensure ERC20 approvals are set for `token0`/`token1` before `mint`.
- Ticks should respect `tickSpacing` (enforcement TBD in this learning build).

---

## Roadmap (Learning milestones)
- Wire `swap` loop using `SwapMath.computeSwapStep` and tick crossing.
- Track `feeGrowthGlobal{0,1}X128` and per‑position fee checkpoints.
- Enforce `tickSpacing` on `mint`/`burn` inputs.
- Expand tests to cover multi‑range swaps and crossing ticks.

---

## References
- Uniswap v3 Book: https://uniswapv3book.com/
- Uniswap v3 Math Primer: https://blog.uniswap.org/uniswap-v3-math-primer
- Uniswap v3 Math Primer (Part 2): https://blog.uniswap.org/uniswap-v3-math-primer-2
- Technical whitepaper deep dive: https://trapdoortech.medium.com/uniswap-deep-dive-into-v3-technical-white-paper-2fe2b5c90d2