// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ITradingVault, IDexRouter } from "./ITradingVault.sol";

/// @title TradingVault — Per-Job escrow + DEX execution surface
/// @notice Holds client funds per Job. Only the JobManager can open/close.
///         Only authorized Execution Agent(s) can call trade(). All trades route
///         through a Uniswap V2-compatible router (Merchant Moe, Agni Finance,
///         Fluxion all expose this surface on Mantle).
contract TradingVault is Ownable, ITradingVault {
    using SafeERC20 for IERC20;

    address public jobManager;
    address public dexRouter;
    mapping(address => bool) public executors;
    mapping(uint256 => JobBalance) private _balances;
    mapping(uint256 => bool) public isJobOpen;

    error OnlyJobManager();
    error OnlyExecutor();
    error JobAlreadyOpen();
    error JobNotOpen();
    error InvalidParams();

    modifier onlyJobManager() {
        if (msg.sender != jobManager) revert OnlyJobManager();
        _;
    }

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert OnlyExecutor();
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) { }

    // -------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------

    function setJobManager(address jobManager_) external onlyOwner {
        jobManager = jobManager_;
        emit JobManagerSet(jobManager_);
    }

    function setExecutor(address executor, bool allowed) external onlyOwner {
        executors[executor] = allowed;
        emit ExecutorSet(executor, allowed);
    }

    function setDexRouter(address router) external onlyOwner {
        dexRouter = router;
        emit DexRouterSet(router);
    }

    // -------------------------------------------------------------------
    // Job lifecycle (JobManager-only)
    // -------------------------------------------------------------------

    function openJob(
        uint256 jobId,
        address principalToken,
        uint256 amount,
        address baseToken
    )
        external
        onlyJobManager
    {
        if (isJobOpen[jobId]) revert JobAlreadyOpen();
        if (principalToken == address(0) || baseToken == address(0) || amount == 0) {
            revert InvalidParams();
        }

        IERC20(principalToken).safeTransferFrom(msg.sender, address(this), amount);

        _balances[jobId] = JobBalance({
            principalToken: principalToken,
            principalDeposit: amount,
            principalBalance: amount,
            baseToken: baseToken,
            baseBalance: 0,
            lastTradeAt: 0,
            tradeCount: 0
        });
        isJobOpen[jobId] = true;

        emit JobOpened(jobId, principalToken, amount);
    }

    function closeJob(uint256 jobId)
        external
        onlyJobManager
        returns (uint256 finalPrincipalBalance)
    {
        if (!isJobOpen[jobId]) revert JobNotOpen();

        JobBalance storage jb = _balances[jobId];

        // If any base token is left, flush back to principal via a final SELL.
        if (jb.baseBalance > 0) {
            _swap(jobId, jb.baseToken, jb.principalToken, jb.baseBalance, 0);
        }

        finalPrincipalBalance = jb.principalBalance;
        // Transfer all proceeds back to the JobManager for settlement payouts.
        IERC20(jb.principalToken).safeTransfer(jobManager, finalPrincipalBalance);

        isJobOpen[jobId] = false;
        emit JobClosed(jobId, finalPrincipalBalance);
    }

    // -------------------------------------------------------------------
    // Trading (executor-only)
    // -------------------------------------------------------------------

    function trade(
        uint256 jobId,
        TradeKind kind,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        onlyExecutor
        returns (uint256 amountOut)
    {
        if (!isJobOpen[jobId]) revert JobNotOpen();
        JobBalance storage jb = _balances[jobId];

        address tokenIn;
        address tokenOut;
        if (kind == TradeKind.Buy) {
            if (amountIn > jb.principalBalance) revert InvalidParams();
            tokenIn = jb.principalToken;
            tokenOut = jb.baseToken;
        } else {
            if (amountIn > jb.baseBalance) revert InvalidParams();
            tokenIn = jb.baseToken;
            tokenOut = jb.principalToken;
        }

        amountOut = _swap(jobId, tokenIn, tokenOut, amountIn, minAmountOut);

        jb.lastTradeAt = uint64(block.timestamp);
        jb.tradeCount += 1;

        emit TradeExecuted(jobId, kind, tokenIn, tokenOut, amountIn, amountOut);
    }

    // -------------------------------------------------------------------
    // Internal swap routing
    // -------------------------------------------------------------------

    function _swap(
        uint256 jobId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    )
        internal
        returns (uint256 amountOut)
    {
        JobBalance storage jb = _balances[jobId];
        IERC20(tokenIn).forceApprove(dexRouter, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = IDexRouter(dexRouter).swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp
        );
        amountOut = amounts[amounts.length - 1];

        if (tokenIn == jb.principalToken) {
            jb.principalBalance -= amountIn;
            jb.baseBalance += amountOut;
        } else {
            jb.baseBalance -= amountIn;
            jb.principalBalance += amountOut;
        }
    }

    // -------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------

    function getJobBalance(uint256 jobId) external view returns (JobBalance memory) {
        return _balances[jobId];
    }
}
