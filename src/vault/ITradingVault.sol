// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title ITradingVault — Holds client funds per Job and routes trades to Mantle DEXs
/// @notice Funds are isolated per jobId. Only the JobManager can deposit/withdraw.
///         Only authorized executor(s) can call trade().
interface ITradingVault {
    struct JobBalance {
        address principalToken;     // e.g. USDC
        uint256 principalDeposit;   // initial deposit
        uint256 principalBalance;   // current quote-token balance
        address baseToken;          // e.g. WMNT
        uint256 baseBalance;        // current base-token balance (after BUYs)
        uint64 lastTradeAt;
        uint64 tradeCount;
    }

    enum TradeKind { Buy, Sell }

    event JobOpened(uint256 indexed jobId, address principalToken, uint256 amount);
    event TradeExecuted(
        uint256 indexed jobId,
        TradeKind kind,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event JobClosed(uint256 indexed jobId, uint256 finalPrincipalBalance);

    event JobManagerSet(address indexed jobManager);
    event ExecutorSet(address indexed executor, bool allowed);
    event DexRouterSet(address indexed router);

    function openJob(
        uint256 jobId,
        address principalToken,
        uint256 amount,
        address baseToken
    ) external;

    function trade(
        uint256 jobId,
        TradeKind kind,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function closeJob(uint256 jobId) external returns (uint256 finalPrincipalBalance);
    function getJobBalance(uint256 jobId) external view returns (JobBalance memory);
}

/// @title IDexRouter — Minimal swap interface (Uniswap V2-compatible)
interface IDexRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
