// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SimpleSwap - A basic ERC20 token swap and liquidity pool contract
/// @notice Enables users to add/remove liquidity and swap tokens in a two-token pool
contract SimpleSwap is ReentrancyGuard {
    /// @notice Emitted when liquidity is added to a pool
    /// @param provider The address adding liquidity
    /// @param tokenA The first token in the pool
    /// @param tokenB The second token in the pool
    /// @param amountA The amount of tokenA added
    /// @param amountB The amount of tokenB added
    /// @param liquidityMinted The amount of liquidity tokens minted to the provider
    /// @param timestamp The timestamp when liquidity was added
    event LiquidityAdded(
        address indexed provider,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidityMinted,
        uint256 timestamp
    );

    /// @notice Emitted when liquidity is removed from a pool
    /// @param provider The address removing liquidity
    /// @param amountA The amount of tokenA withdrawn
    /// @param amountB The amount of tokenB withdrawn
    event LiquidityRemoved(
        address indexed provider,
        uint256 amountA,
        uint256 amountB
    );

    /// @notice Emitted when tokens are swapped
    /// @param swapper The address performing the swap
    /// @param tokenIn The token address sent to the contract
    /// @param tokenOut The token address received from the contract
    /// @param amountIn The amount of tokenIn sent
    /// @param amountOut The amount of tokenOut received
    /// @param timestamp The timestamp when the swap occurred
    event TokensSwapped(
        address indexed swapper,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    /// @notice Represents a liquidity pool between two tokens
    struct Pool {
        uint256 reserveA;              // Current amount of token A in the pool
        uint256 reserveB;              // Current amount of token B in the pool
        uint256 totalLiquidity;       // Total liquidity tokens issued for this pool
        mapping(address => uint256) liquidityProvided; // Tracks liquidity tokens owned by each provider
    }

    /// @dev Mapping from pair hash to Pool struct
    mapping(bytes32 => Pool) internal pools;

    /// @notice Calculates a unique hash for a token pair (order independent)
    /// @param tokenA The address of the first token
    /// @param tokenB The address of the second token
    /// @return A bytes32 hash representing the token pair
    function _getPairHash(address tokenA, address tokenB)
        internal
        pure
        returns (bytes32)
    {
        // Ensure consistent ordering of tokens before hashing
        return
            tokenA < tokenB
                ? keccak256(abi.encodePacked(tokenA, tokenB))
                : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    /// @notice Sorts two token addresses to enforce a canonical order
    /// @param tokenA The first token address
    /// @param tokenB The second token address
    /// @return token0 The lower address
    /// @return token1 The higher address
    function _sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address, address)
    {
        require(tokenA != tokenB, "Must be different");
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Returns reserves of the pool ordered to match token0 and token1
    /// @param tokenA The token address for which reserves are requested
    /// @param token0 The first token address in sorted order
    /// @param pool The liquidity pool struct
    /// @return currentReserve0 Reserve of token0
    /// @return currentReserve1 Reserve of the other token
    function _getOrderedReserves(
        address tokenA,
        address token0,
        Pool storage pool
    ) internal view returns (uint256 currentReserve0, uint256 currentReserve1) {
        if (tokenA == token0) {
            currentReserve0 = pool.reserveA;
            currentReserve1 = pool.reserveB;
        } else {
            currentReserve0 = pool.reserveB;
            currentReserve1 = pool.reserveA;
        }
    }

    /// @notice Calculates the actual token amounts and liquidity tokens minted when adding liquidity
    /// @param tokenA The token address provided by user
    /// @param token0 The first token in sorted order
    /// @param amountADesired The amount of tokenA desired to add
    /// @param amountBDesired The amount of tokenB desired to add
    /// @param amountAMin Minimum acceptable amount of tokenA to protect against slippage
    /// @param amountBMin Minimum acceptable amount of tokenB to protect against slippage
    /// @param pool The liquidity pool struct
    /// @return amountA The final amount of tokenA to add
    /// @return amountB The final amount of tokenB to add
    /// @return liquidity The liquidity tokens to mint
    function _calculateAddLiquidityAmountsAndLiquidity(
        address tokenA,
        address token0,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        Pool storage pool
    )
        internal
        view
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (uint256 currentReserve0, uint256 currentReserve1) = _getOrderedReserves(tokenA, token0, pool);

        if (pool.totalLiquidity == 0) {
            // Initial liquidity: just accept the amounts user wants to add
            amountA = amountADesired;
            amountB = amountBDesired;
            require(amountA > 0 && amountB > 0, "Amounts must be > 0");
            // Mint liquidity proportional to geometric mean of amounts
            liquidity = Math.sqrt(amountA * amountB);
        } else {
            // Calculate optimal amount of tokenB given amountADesired based on current reserves ratio
            uint256 amountBOptimal = (amountADesired * currentReserve1) / currentReserve0;

            if (amountBOptimal <= amountBDesired) {
                // amountBOptimal fits user's max amount, check slippage protection
                require(amountBOptimal >= amountBMin, "TokenB slippage error");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                // Otherwise calculate optimal amount of tokenA given amountBDesired
                uint256 amountAOptimal = (amountBDesired * currentReserve0) / currentReserve1;
                require(amountAOptimal >= amountAMin, "TokenA slippage error");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
            // Calculate liquidity tokens to mint proportional to the smallest relative increase in reserves
            liquidity = Math.min(
                (amountA * pool.totalLiquidity) / currentReserve0,
                (amountB * pool.totalLiquidity) / currentReserve1
            );
        }
        require(liquidity > 0, "Liquidity must be > 0");
    }

    /// @notice Updates the pool reserves after liquidity is added
    /// @param tokenA The token address provided by user
    /// @param token0 The first token in sorted order
    /// @param pool The liquidity pool struct
    /// @param amountA The amount of tokenA added
    /// @param amountB The amount of tokenB added
    function _updateAddLiquidityPoolReserves(
        address tokenA,
        address token0,
        Pool storage pool,
        uint256 amountA,
        uint256 amountB
    ) internal {
        if (tokenA == token0) {
            pool.reserveA += amountA;
            pool.reserveB += amountB;
        } else {
            // If tokenA is second in order, reverse amounts when adding reserves
            pool.reserveA += amountB;
            pool.reserveB += amountA;
        }
    }

    /// @notice Adds liquidity to a token pair pool
    /// @param tokenA Address of the first token
    /// @param tokenB Address of the second token
    /// @param amountADesired Max amount of tokenA to add
    /// @param amountBDesired Max amount of tokenB to add
    /// @param amountAMin Min acceptable amount of tokenA (slippage protection)
    /// @param amountBMin Min acceptable amount of tokenB (slippage protection)
    /// @param to Address to receive liquidity tokens (LP tokens)
    /// @param deadline Timestamp after which transaction is invalid
    /// @return amountA Actual amount of tokenA added
    /// @return amountB Actual amount of tokenB added
    /// @return liquidity Amount of liquidity tokens minted
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(block.timestamp <= deadline, "Transaction expired");
        require(to != address(0), "Invalid 'to' address");

        (address token0, ) = _sortTokens(tokenA, tokenB);
        bytes32 pairHash = _getPairHash(tokenA, tokenB);
        Pool storage pool = pools[pairHash];

        (amountA, amountB, liquidity) = _calculateAddLiquidityAmountsAndLiquidity(
            tokenA,
            token0,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            pool
        );

        // Transfer tokens from user to contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // Update reserves in pool
        _updateAddLiquidityPoolReserves(tokenA, token0, pool, amountA, amountB);

        // Update liquidity tracking
        pool.totalLiquidity += liquidity;
        pool.liquidityProvided[to] += liquidity;

        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity, block.timestamp);

        return (amountA, amountB, liquidity);
    }

    /// @notice Removes liquidity from a token pair pool
    /// @param tokenA Address of the first token
    /// @param tokenB Address of the second token
    /// @param liquidity Amount of liquidity tokens to burn
    /// @param amountAMin Minimum amount of tokenA to receive (slippage protection)
    /// @param amountBMin Minimum amount of tokenB to receive (slippage protection)
    /// @param to Address to receive withdrawn tokens
    /// @param deadline Timestamp after which transaction is invalid
    /// @return amountA Amount of tokenA withdrawn
    /// @return amountB Amount of tokenB withdrawn
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(to != address(0), "Invalid 'to' address");
        require(liquidity > 0, "Liquidity must be > 0");

        (address token0, ) = _sortTokens(tokenA, tokenB);
        bytes32 pairHash = _getPairHash(tokenA, tokenB);
        Pool storage pool = pools[pairHash];

        // Ensure sender has enough liquidity tokens
        require(pool.liquidityProvided[msg.sender] >= liquidity, "Insufficient liquidity");
        require(pool.totalLiquidity > 0, "Empty liquidity pool");

        uint256 currentReserve0 = tokenA == token0 ? pool.reserveA : pool.reserveB;
        uint256 currentReserve1 = tokenA == token0 ? pool.reserveB : pool.reserveA;

        // Calculate amounts to withdraw proportional to liquidity tokens burned
        amountA = (liquidity * currentReserve0) / pool.totalLiquidity;
        amountB = (liquidity * currentReserve1) / pool.totalLiquidity;

        // Check slippage limits
        require(amountA >= amountAMin, "TokenA slippage error");
        require(amountB >= amountBMin, "TokenB slippage error");

        // Update pool liquidity and provider balances
        pool.totalLiquidity -= liquidity;
        pool.liquidityProvided[msg.sender] -= liquidity;

        // Update reserves removing withdrawn tokens
        if (tokenA == token0) {
            pool.reserveA -= amountA;
            pool.reserveB -= amountB;
        } else {
            pool.reserveA -= amountB;
            pool.reserveB -= amountA;
        }

        // Transfer tokens back to user
        IERC20(tokenA).transfer(to, amountA);
        IERC20(tokenB).transfer(to, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB);

        return (amountA, amountB);
    }

    /// @notice Returns reserves ordered by tokenIn and tokenOut for swapping
    /// @param tokenIn Token address sent in swap
    /// @param tokenOut Token address received in swap
    /// @param pool The liquidity pool struct
    /// @return reserveIn Reserve of tokenIn in pool
    /// @return reserveOut Reserve of tokenOut in pool
    function _getReservesForSwap(
        address tokenIn,
        address tokenOut,
        Pool storage pool
    ) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (address token0, ) = _sortTokens(tokenIn, tokenOut);
        if (tokenIn == token0) {
            reserveIn = pool.reserveA;
            reserveOut = pool.reserveB;
        } else {
            reserveIn = pool.reserveB;
            reserveOut = pool.reserveA;
        }
    }

    /// @notice Updates pool reserves after a swap
    /// @param tokenIn Token address sent in swap
    /// @param tokenOut Token address received in swap
    /// @param pool The liquidity pool struct
    /// @param amountIn Amount of tokenIn added to the pool
    /// @param amountOut Amount of tokenOut removed from the pool
    function _updatePoolReserves(
        address tokenIn,
        address tokenOut,
        Pool storage pool,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        (address token0, ) = _sortTokens(tokenIn, tokenOut);
        if (tokenIn == token0) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }
    }

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible (1 hop only)
    /// @param amountIn Exact amount of input tokens to swap
    /// @param amountOutMin Minimum acceptable amount of output tokens (slippage protection)
    /// @param path Array of token addresses [tokenIn, tokenOut]
    /// @param to Address to receive output tokens
    /// @param deadline Timestamp after which transaction is invalid
    /// @return amounts Array with amounts [amountIn, amountOut]
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(path.length == 2, "Only 1 hop allowed");
        require(to != address(0), "Invalid 'to' address");
        require(amountIn > 0, "Input must be > 0");

        bytes32 pairHash = _getPairHash(path[0], path[1]);
        Pool storage pool = pools[pairHash];

        (uint256 reserveIn, uint256 reserveOut) = _getReservesForSwap(path[0], path[1], pool);

        require(reserveIn > 0 && reserveOut > 0, "Empty pool");

        // Calculate output amount according to constant product formula with fee
        uint256 amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut >= amountOutMin, "Excessive slippage");

        // Transfer input tokens from sender to contract
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // Transfer output tokens from contract to recipient
        IERC20(path[1]).transfer(to, amountOut);

        // Update reserves reflecting the swap
        _updatePoolReserves(path[0], path[1], pool, amountIn, amountOut);

        emit TokensSwapped(msg.sender, path[0], path[1], amountIn, amountOut, block.timestamp);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    /// @notice Returns the price of tokenA in terms of tokenB (scaled by 1e18)
    /// @param tokenA The first token address
    /// @param tokenB The second token address
    /// @return price The price of one unit of tokenA in tokenB, scaled by 1e18
    function getPrice(address tokenA, address tokenB)
        external
        view
        returns (uint256 price)
    {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");

        bytes32 pairHash = _getPairHash(tokenA, tokenB);
        Pool storage pool = pools[pairHash];

        require(pool.reserveA > 0 && pool.reserveB > 0, "No liquidity in pool");

        if (tokenA < tokenB) {
            // price = reserveB / reserveA scaled by 1e18
            return (pool.reserveB * 1e18) / pool.reserveA;
        } else {
            // price = reserveA / reserveB scaled by 1e18
            return (pool.reserveA * 1e18) / pool.reserveB;
        }
    }

    /// @notice Calculates the output token amount given an input amount and reserves using Uniswap's formula with 0.3% fee
    /// @param amountIn Amount of input token being swapped
    /// @param reserveIn Reserve of input token in pool
    /// @param reserveOut Reserve of output token in pool
    /// @return amountOut The calculated output amount of token
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        uint256 amountInWithFee = (amountIn * 997) / 1000; // 0.3% fee
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
