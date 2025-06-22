# module3-tp3
SimpleSwap Implementation

SimpleSwap

A basic decentralized token swap and liquidity pool smart contract, allowing users to add/remove liquidity and swap ERC20 tokens.

Overview

SimpleSwap is a straightforward AMM (Automated Market Maker) inspired by Uniswap's constant product formula. It supports:

- Adding liquidity to token pairs
- Removing liquidity proportionally
- Swapping tokens with slippage protection
- Querying token prices from the pool reserves

It handles two ERC20 tokens per pool and tracks liquidity shares for providers.

Features

- Liquidity pools identified by token pairs (order-independent)
- Liquidity tokens minted proportionally to liquidity provided
- Swap fees of 0.3% applied on swaps
- Slippage checks on add/remove liquidity and swaps
- Reentrancy protection via OpenZeppelin's ReentrancyGuard

Usage

Adding Liquidity

function addLiquidity( address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

- Adds liquidity to the pool for tokenA and tokenB.
- Returns actual amounts added and liquidity tokens minted.
- Slippage is prevented by amountAMin and amountBMin.
- to receives liquidity tokens.
- Must be called before deadline timestamp.

Removing Liquidity

function removeLiquidity( address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline ) external returns (uint256 amountA, uint256 amountB);

- Burns liquidity tokens to withdraw proportional token amounts.
- Slippage protection via amountAMin and amountBMin.
- Tokens sent to to.
- Must be called before deadline.

Swapping Tokens

function swapExactTokensForTokens( uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline ) external returns (uint256[] memory amounts);

- Swaps an exact amountIn of path[0] token for at least amountOutMin of path[1] token.
- Only single-hop swaps supported (path length = 2).
- Output tokens sent to to.
- Must be called before deadline.

Query Price

function getPrice(address tokenA, address tokenB) external view returns (uint256 price);

- Returns the current price of tokenA in terms of tokenB, scaled by 1e18.
- Price is based on the pool’s current reserves.

Events

LiquidityAdded(address provider, address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 liquidityMinted, uint256 timestamp)
LiquidityRemoved(address provider, uint256 amountA, uint256 amountB)
TokensSwapped(address swapper, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 timestamp)

Requirements

Solidity 0.8.27 or higher
OpenZeppelin Contracts (IERC20, Math, ReentrancyGuard)

Notes

- No support for multi-hop swaps or liquidity token transfers outside this contract.
- The contract assumes ERC20 tokens with standard transferFrom and transfer behavior.

License

MIT License

