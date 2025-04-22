# Custom Fee Uniswap V4 Hook
Custom fee hook for Uniswap V4 pool to charge dynamic fee according to the current `poolPrice` and `referencePrice`.

`referencePrice` => True exchange rate of ezETH from the `rateProvider`

`poolPrice` => price of ezETH in the Uniswap Pool.

- If pool is moving towards peg price. Then users will be charged `minFee%` configured.
- If pool is depegged by `depeg%` then users will be charged the fee as -

```
  Fee => |  minFee  | if depeg% < minFee%
         |  maxFee  | if depeg% > maxFee%
         |  depeg%  | if minFee% <= depeg% <= maxFee%
```

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

