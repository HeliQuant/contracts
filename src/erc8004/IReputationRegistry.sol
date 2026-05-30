// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IReputationRegistry — ERC-8004 Reputation Registry interface
/// @notice Portable, on-chain performance reputation per agent
interface IReputationRegistry {
    struct Reputation {
        uint64 totalJobs;
        uint64 successfulJobs;
        int256 cumulativePnL;       // signed, in pnlToken decimals
        uint256 totalVolume;        // sum of |trade notional|, pnlToken decimals
        uint256 peakBalance;        // for drawdown tracking
        uint256 maxDrawdownBps;     // in basis points (10000 = 100%)
        uint64 lastUpdateAt;
    }

    event JobOutcomeRecorded(
        uint256 indexed agentTokenId,
        uint256 indexed jobId,
        int256 pnl,
        uint256 volume,
        bool success
    );

    event AuthorizedReporterUpdated(address indexed reporter, bool allowed);

    /// @notice Called by an authorized reporter (typically JobManager) after a job settles
    function recordJobOutcome(
        uint256 agentTokenId,
        uint256 jobId,
        int256 pnl,
        uint256 volume,
        uint256 currentBalance
    ) external;

    function getReputation(uint256 agentTokenId) external view returns (Reputation memory);

    /// @notice Win-rate in basis points (0-10000)
    function winRateBps(uint256 agentTokenId) external view returns (uint256);
}
