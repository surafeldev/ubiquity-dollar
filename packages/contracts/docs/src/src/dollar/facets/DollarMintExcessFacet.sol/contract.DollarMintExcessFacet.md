# DollarMintExcessFacet
[Git Source](https://github.com/ubiquity/ubiquity-dollar/blob/c4890e02aea7bcfd69c21e5e480e0b3a22e5e740/src/dollar/facets/DollarMintExcessFacet.sol)

**Inherits:**
[IDollarMintExcess](/src/dollar/interfaces/IDollarMintExcess.sol/interface.IDollarMintExcess.md)

Contract facet for distributing excess Dollars when `mintClaimableDollars()` is called

Excess Dollars are distributed this way:
- 50% goes to the treasury address
- 10% goes for burning Dollar-Governance LP tokens in a DEX pool
- 40% goes to the Staking contract


## Functions
### distributeDollars

Distributes excess Dollars:
- 50% goes to the treasury address
- 10% goes for burning Dollar-Governance LP tokens in a DEX pool
- 40% goes to the Staking contract


```solidity
function distributeDollars() external override;
```
