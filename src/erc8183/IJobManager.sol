// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IJobManager — ERC-8183 Job primitive for AI trading firm engagements
/// @notice Client deposits principal → Firm (ERC-8004 identity) trades via TradingVault →
///         deterministic on-chain settlement based on final PnL with performance fee.
interface IJobManager {
    enum JobState {
        None,
        Active,    // funds in vault, firm trading
        Settled    // closed out, payouts complete
    }

    struct Job {
        uint256 jobId;
        address client;
        uint256 firmTokenId;            // ERC-8004 identity of the firm
        address principalToken;         // e.g. USDC
        uint256 principalAmount;        // initial deposit
        address baseToken;              // e.g. WMNT — the token traded against principal
        uint64 startTime;
        uint64 duration;                // seconds; settlement allowed after start + duration
        uint16 perfFeeBps;              // performance fee on profit, basis points (0-3000)
        JobState state;
        uint256 finalPrincipalBalance;  // set on settle
        int256 finalPnL;                // signed PnL
    }

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        uint256 indexed firmTokenId,
        uint256 principalAmount,
        uint64 duration,
        uint16 perfFeeBps
    );
    event JobSettled(
        uint256 indexed jobId,
        int256 pnl,
        uint256 clientPayout,
        uint256 firmFee
    );

    function createJob(
        uint256 firmTokenId,
        address principalToken,
        uint256 amount,
        address baseToken,
        uint64 duration,
        uint16 perfFeeBps
    ) external returns (uint256 jobId);

    function settleJob(uint256 jobId) external;
    function getJob(uint256 jobId) external view returns (Job memory);
}
