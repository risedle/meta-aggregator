# Risedle's Meta DEX Aggregator

Risedle's Meta DEX Aggregator smart contract is a on-chain settlement layer that
aggregates liquidity from multiple dex aggregator to provide users with the best
possible price for their trades. It does this by aggregating liquidity from
multiple dex aggregator, which means that it can find the best available price
for a given trade across all of the connected DEXs.

Key features:

1. **Always get the best price**: isedle's Meta DEX Aggregator aggregate
   liquidity from multiple DEX aggregators to provide users with the best
   possible price for their trades.
2. **Save money on fees and slippage**: Risedle's Meta DEX Aggregator can often
   find significantly better prices than what would be available on a single DEX.
3. **Easy to use**: Risedle's Meta DEX Aggregator are very easy to use.
   Simply enter the tokens you want to trade and the amount you want to trade,
   and the Risedle's Meta DEX Aggregator will find and execute the best price
   for you.
4. **Wide range of liquidity**: Risedle's Meta DEX Aggregator connect to a
   wider range of liquidity pools than a single DEX. This means that you
   can often find liquidity for less popular tokens.

## Installation

To install with Foundry:

```
forge install risedle/meta-aggregator
```

## Local development

This project uses Foundry as the development framework.

Use the following command to install dependencies:

```
forge install
```

Create new `.env` file with the following content:

```
ETHERSCAN_API_KEY="UPDATE_HERE"
ETH_RPC_URL="UPDATE_HERE"
```

You can build the smart contract using the following command:

```
forge build
```

To run the test, use the following command:

```
forge test
```

## Deployments

Create `.env` with the following contents:

```
ARBITRUM_RPC_URL=https://rpc.ankr.com/arbitrum
PRIVATE_KEY=
ETHERSCAN_API_KEY=
```

Then run the following command:

```
# To load the variables in the .env file
source .env

# To deploy and verify our contract
forge script script/DeployMetaAggregator.s.sol:DeployMetaAggregator --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -vvvv
```

| Chain    | Address                                      | Explorer                                                                       |
| -------- | -------------------------------------------- | ------------------------------------------------------------------------------ |
| Arbitrum | `0x1843b412cfffcae9593232135e7564959509867a` | [link](https://arbiscan.io/address/0x1843b412cfffcae9593232135e7564959509867a) |
