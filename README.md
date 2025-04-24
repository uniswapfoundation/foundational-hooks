## Foundational Hooks

# :construction: UNDER CONSTRUCTION :construction: 

> *Minimal Uniswap v4 Hooks for supporting targetted asset pairs*

*requires [foundry](https://book.getfoundry.sh/)*

---

Uniswap Foundation's *foundational hooks* serve as an opinioniated extension to OpenZeppelin's Uniswap Hooks Library to better support particular asset pairs. The repo identifies the following the asset pairs where Uniswap v4 Hooks can improve liquidity profitability, liquidity depth, and/or price-execution:

* Blue chip (volatile pairs): ETH/USD, BTC/USD
* Stable Pairs: USDa/USDb
* Correlated Pairs: ETH/LST, USD/yield-bearing USD

---

# Table of Contents

```
src
├── PegStabilityHook.sol         // abstract implementation where dynamic fees are used to incentivize peg stability
├── examples
│   └── peg-stability
│       └── ParityStability.sol  // an example implementation of PegStabilityHook, where an exchange rate of 1 is incentivized via swap fees
└── libraries
    └── SqrtPriceLibrary.sol     // a helper library for performing sqrtPriceX96 arithmetic
```
