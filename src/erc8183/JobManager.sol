// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IIdentityRegistry } from "../erc8004/IIdentityRegistry.sol";
import { IReputationRegistry } from "../erc8004/IReputationRegistry.sol";
import { IValidationRegistry } from "../erc8004/IValidationRegistry.sol";
import { ITradingVault } from "../vault/ITradingVault.sol";
import { IJobManager } from "./IJobManager.sol";

/// @title JobManager — ERC-8183 Job escrow & settlement for AI trading firm engagements
/// @notice Settlement formula (deterministic, on-chain):
///           if finalBalance >= principal:
///             firmFee   = (finalBalance - principal) * perfFeeBps / 10_000
///             client    = finalBalance - firmFee
///           else:
///             firmFee   = 0
///             client    = finalBalance
contract JobManager is Ownable, IJobManager {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_PERF_FEE_BPS = 3_000; // 30%

    IIdentityRegistry public immutable identityRegistry;
    IReputationRegistry public immutable reputationRegistry;
    IValidationRegistry public immutable validationRegistry;
    ITradingVault public immutable vault;

    uint256 private _nextJobId = 1;
    mapping(uint256 => Job) private _jobs;
    mapping(address => uint256[]) private _jobsByClient;
    mapping(uint256 => uint256[]) private _jobsByFirm;

    error InvalidFirm();
    error InvalidDuration();
    error InvalidPerfFee();
    error InvalidAmount();
    error UnknownJob();
    error JobNotActive();
    error JobNotMature();

    constructor(
        address initialOwner,
        address identityRegistry_,
        address reputationRegistry_,
        address validationRegistry_,
        address vault_
    ) Ownable(initialOwner) {
        identityRegistry = IIdentityRegistry(identityRegistry_);
        reputationRegistry = IReputationRegistry(reputationRegistry_);
        validationRegistry = IValidationRegistry(validationRegistry_);
        vault = ITradingVault(vault_);
    }

    // -------------------------------------------------------------------
    // Job creation
    // -------------------------------------------------------------------

    function createJob(
        uint256 firmTokenId,
        address principalToken,
        uint256 amount,
        address baseToken,
        uint64 duration,
        uint16 perfFeeBps
    )
        external
        returns (uint256 jobId)
    {
        if (amount == 0) revert InvalidAmount();
        if (duration == 0) revert InvalidDuration();
        if (perfFeeBps > MAX_PERF_FEE_BPS) revert InvalidPerfFee();

        IIdentityRegistry.Identity memory firm = identityRegistry.getIdentity(firmTokenId);
        if (firm.kind != IIdentityRegistry.AgentKind.Firm) revert InvalidFirm();

        jobId = _nextJobId++;
        _jobs[jobId] = Job({
            jobId: jobId,
            client: msg.sender,
            firmTokenId: firmTokenId,
            principalToken: principalToken,
            principalAmount: amount,
            baseToken: baseToken,
            startTime: uint64(block.timestamp),
            duration: duration,
            perfFeeBps: perfFeeBps,
            state: JobState.Active,
            finalPrincipalBalance: 0,
            finalPnL: 0
        });

        _jobsByClient[msg.sender].push(jobId);
        _jobsByFirm[firmTokenId].push(jobId);

        // Pull principal from client, then approve & forward to vault.
        IERC20(principalToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(principalToken).forceApprove(address(vault), amount);
        vault.openJob(jobId, principalToken, amount, baseToken);

        emit JobCreated(jobId, msg.sender, firmTokenId, amount, duration, perfFeeBps);
    }

    // -------------------------------------------------------------------
    // Settlement
    // -------------------------------------------------------------------

    function settleJob(uint256 jobId) external {
        Job storage job = _jobs[jobId];
        if (job.state != JobState.Active) revert JobNotActive();
        if (block.timestamp < uint256(job.startTime) + uint256(job.duration)) {
            revert JobNotMature();
        }

        uint256 finalBalance = vault.closeJob(jobId);

        int256 pnl = int256(finalBalance) - int256(job.principalAmount);

        uint256 firmFee = 0;
        uint256 clientPayout = finalBalance;

        if (pnl > 0) {
            firmFee = (uint256(pnl) * uint256(job.perfFeeBps)) / 10_000;
            clientPayout = finalBalance - firmFee;
        }

        job.state = JobState.Settled;
        job.finalPrincipalBalance = finalBalance;
        job.finalPnL = pnl;

        IERC20 principal = IERC20(job.principalToken);
        if (clientPayout > 0) {
            principal.safeTransfer(job.client, clientPayout);
        }
        if (firmFee > 0) {
            // Pay the firm fee to whoever currently owns the firm identity NFT
            address firmOwner = identityRegistry.ownerOfAgent(job.firmTokenId);
            principal.safeTransfer(firmOwner, firmFee);
        }

        // Update reputation + validation
        reputationRegistry.recordJobOutcome(
            job.firmTokenId,
            jobId,
            pnl,
            job.principalAmount, // volume proxy = principal at risk
            finalBalance
        );
        bytes32 proofHash = keccak256(
            abi.encode(jobId, finalBalance, pnl, block.timestamp)
        );
        validationRegistry.recordCredential(
            job.firmTokenId,
            jobId,
            IValidationRegistry.ProofKind.OnchainStateCheck,
            proofHash,
            address(0)
        );

        emit JobSettled(jobId, pnl, clientPayout, firmFee);
    }

    // -------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------

    function getJob(uint256 jobId) external view returns (Job memory) {
        Job memory j = _jobs[jobId];
        if (j.startTime == 0) revert UnknownJob();
        return j;
    }

    function jobsByClient(address client) external view returns (uint256[] memory) {
        return _jobsByClient[client];
    }

    function jobsByFirm(uint256 firmTokenId) external view returns (uint256[] memory) {
        return _jobsByFirm[firmTokenId];
    }
}
