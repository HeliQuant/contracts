// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IIdentityRegistry } from "./IIdentityRegistry.sol";
import { IReputationRegistry } from "./IReputationRegistry.sol";

/// @title ReputationRegistry — ERC-8004 Reputation Registry
/// @notice Tracks per-agent performance metrics. Updated only by authorized reporters
///         (typically the JobManager after a Job settles).
contract ReputationRegistry is Ownable, IReputationRegistry {
    IIdentityRegistry public immutable identityRegistry;

    mapping(uint256 => Reputation) private _reputations;
    mapping(address => bool) public authorizedReporters;

    error NotAuthorized();
    error UnknownAgent();
    error InvalidIdentityRegistry();

    modifier onlyAuthorized() {
        if (!authorizedReporters[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address identityRegistry_, address initialOwner) Ownable(initialOwner) {
        if (identityRegistry_ == address(0)) revert InvalidIdentityRegistry();
        identityRegistry = IIdentityRegistry(identityRegistry_);
    }

    // -------------------------------------------------------------------
    // Authorization
    // -------------------------------------------------------------------

    function setAuthorizedReporter(address reporter, bool allowed) external onlyOwner {
        authorizedReporters[reporter] = allowed;
        emit AuthorizedReporterUpdated(reporter, allowed);
    }

    // -------------------------------------------------------------------
    // Recording
    // -------------------------------------------------------------------

    function recordJobOutcome(
        uint256 agentTokenId,
        uint256 jobId,
        int256 pnl,
        uint256 volume,
        uint256 currentBalance
    )
        external
        onlyAuthorized
    {
        // Verify the agent exists (will revert with NonexistentToken if not).
        identityRegistry.getIdentity(agentTokenId);

        Reputation storage rep = _reputations[agentTokenId];

        rep.totalJobs += 1;
        if (pnl > 0) rep.successfulJobs += 1;
        rep.cumulativePnL += pnl;
        rep.totalVolume += volume;

        if (currentBalance > rep.peakBalance) {
            rep.peakBalance = currentBalance;
        } else if (rep.peakBalance > 0) {
            uint256 drawdownBps = ((rep.peakBalance - currentBalance) * 10_000) / rep.peakBalance;
            if (drawdownBps > rep.maxDrawdownBps) {
                rep.maxDrawdownBps = drawdownBps;
            }
        }

        rep.lastUpdateAt = uint64(block.timestamp);

        emit JobOutcomeRecorded(agentTokenId, jobId, pnl, volume, pnl > 0);
    }

    // -------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------

    function getReputation(uint256 agentTokenId) external view returns (Reputation memory) {
        return _reputations[agentTokenId];
    }

    function winRateBps(uint256 agentTokenId) external view returns (uint256) {
        Reputation memory rep = _reputations[agentTokenId];
        if (rep.totalJobs == 0) return 0;
        return (uint256(rep.successfulJobs) * 10_000) / uint256(rep.totalJobs);
    }
}
