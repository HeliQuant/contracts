// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IdentityRegistry } from "../src/erc8004/IdentityRegistry.sol";
import { ReputationRegistry } from "../src/erc8004/ReputationRegistry.sol";
import { ValidationRegistry } from "../src/erc8004/ValidationRegistry.sol";
import { TradingVault } from "../src/vault/TradingVault.sol";
import { JobManager } from "../src/erc8183/JobManager.sol";
import { IIdentityRegistry } from "../src/erc8004/IIdentityRegistry.sol";
import { IJobManager } from "../src/erc8183/IJobManager.sol";
import { ITradingVault } from "../src/vault/ITradingVault.sol";
import { IReputationRegistry } from "../src/erc8004/IReputationRegistry.sol";
// IMPORTANT: import the DEPLOYABLE mocks from src/ (not test/mocks) so this test
// proves the exact artifacts DeployTestnet.s.sol ships to Mantle Sepolia.
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockDexRouter } from "../src/mocks/MockDexRouter.sol";

/// @title TestnetFlowTest — proves the "hire the firm" HOLD->settle MVP end-to-end.
/// @notice Mirrors the real wiring (Deploy.s.sol + DeployTestnet.s.sol) on a fresh
///         local stack, then runs a client deposit -> mature -> settle with no trades,
///         asserting the client is fully refunded and reputation/validation recorded.
contract TestnetFlowTest is Test {
    IdentityRegistry internal identity;
    ReputationRegistry internal reputation;
    ValidationRegistry internal validation;
    TradingVault internal vault;
    JobManager internal jobs;
    MockERC20 internal usdc;
    MockERC20 internal wmnt;

    address internal deployer = address(this); // owner of registries + vault
    // Firm identity is minted via ERC721 _safeMint, which rejects non-receiver
    // contracts. On testnet the firm registers from the deployer EOA (an EOA passes
    // _safeMint); here we use a dedicated EOA to mirror that and avoid the test
    // contract failing the onERC721Received check.
    address internal firmOwner = address(0xF14);
    address internal client = address(0xC11E);
    address internal executor = address(0xE5E);

    uint256 internal firmTokenId;
    uint64 internal constant DURATION = 1 hours;
    uint16 internal constant PERF_FEE_BPS = 2_000; // 20%
    uint256 internal constant PRINCIPAL = 1_000e6; // 1,000 mUSDC (6dp)

    function setUp() public {
        // --- Deploy the full core stack fresh (mirrors Deploy.s.sol) ---
        identity = new IdentityRegistry();
        reputation = new ReputationRegistry(address(identity), deployer);
        validation = new ValidationRegistry(address(identity), deployer);
        vault = new TradingVault(deployer);
        jobs = new JobManager(
            deployer,
            address(identity),
            address(reputation),
            address(validation),
            address(vault)
        );

        // --- Wiring required for settleJob() to succeed (mirrors DeployTestnet) ---
        reputation.setAuthorizedReporter(address(jobs), true);
        validation.setAuthorizedSubmitter(address(jobs), true);
        vault.setJobManager(address(jobs));

        // --- Mock tokens (the src/ deployable faucet variant) ---
        usdc = new MockERC20("Mock USD Coin", "mUSDC", 6);
        wmnt = new MockERC20("Mock Wrapped Mantle", "mWMNT", 18);

        // --- Register the HeliQuant Firm (AgentKind.Firm, parentTokenId 0) ---
        // Registered from an EOA (firmOwner) so _safeMint succeeds; firmOwner becomes
        // ownerOfAgent(firmTokenId) and would receive any performance fee.
        vm.prank(firmOwner);
        firmTokenId = identity.register(IIdentityRegistry.AgentKind.Firm, 0, "ipfs://heliquant-firm", "");
    }

    /// @notice Sanity: the deployable faucet token mints and reports decimals correctly.
    function test_mockToken_faucetAndDecimals() public {
        assertEq(usdc.decimals(), 6);
        assertEq(wmnt.decimals(), 18);

        usdc.mint(client, 123e6);
        assertEq(usdc.balanceOf(client), 123e6);
    }

    /// @notice Firm registration uses IdentityRegistry.register(AgentKind.Firm, 0, ...).
    function test_firmRegistration() public view {
        IIdentityRegistry.Identity memory firm = identity.getIdentity(firmTokenId);
        assertEq(uint8(firm.kind), uint8(IIdentityRegistry.AgentKind.Firm));
        assertEq(firm.parentTokenId, 0);
        assertEq(firm.owner, firmOwner);
        assertEq(identity.ownerOfAgent(firmTokenId), firmOwner);
    }

    /// @notice CORE MVP: client hires the firm (deposit), waits, settles with NO trades.
    ///         No trades => final balance == principal => PnL == 0 => firmFee == 0 =>
    ///         client refunded in full. Reputation + validation recorded (no revert).
    function test_holdThenSettle_refundsClientInFull() public {
        // 1) Client self-funds via the public faucet, approves JobManager, hires firm.
        usdc.mint(client, PRINCIPAL); // open faucet — anyone can mint to the client

        vm.startPrank(client);
        usdc.approve(address(jobs), PRINCIPAL);
        uint256 jobId = jobs.createJob(
            firmTokenId,
            address(usdc),
            PRINCIPAL,
            address(wmnt),
            DURATION,
            PERF_FEE_BPS
        );
        vm.stopPrank();

        // 2) Assert job is Active and principal escrowed in the vault.
        IJobManager.Job memory j = jobs.getJob(jobId);
        assertEq(uint8(j.state), uint8(IJobManager.JobState.Active));
        assertEq(j.client, client);
        assertEq(j.firmTokenId, firmTokenId);
        assertEq(j.principalAmount, PRINCIPAL);

        ITradingVault.JobBalance memory jb = vault.getJobBalance(jobId);
        assertEq(jb.principalToken, address(usdc));
        assertEq(jb.principalDeposit, PRINCIPAL);
        assertEq(jb.principalBalance, PRINCIPAL);
        assertEq(jb.baseBalance, 0);
        assertEq(usdc.balanceOf(address(vault)), PRINCIPAL);
        assertEq(usdc.balanceOf(client), 0);

        // jobsByClient returns this job.
        uint256[] memory clientJobs = jobs.jobsByClient(client);
        assertEq(clientJobs.length, 1);
        assertEq(clientJobs[0], jobId);

        // 3) Cannot settle before maturity.
        vm.expectRevert(JobManager.JobNotMature.selector);
        jobs.settleJob(jobId);

        // 4) Warp past startTime + duration, then settle.
        vm.warp(uint256(j.startTime) + uint256(DURATION) + 1);
        jobs.settleJob(jobId);

        // 5) Assertions: full refund, no fee, Settled, registries recorded.
        IJobManager.Job memory settled = jobs.getJob(jobId);
        assertEq(uint8(settled.state), uint8(IJobManager.JobState.Settled));
        assertEq(settled.finalPrincipalBalance, PRINCIPAL);
        assertEq(settled.finalPnL, int256(0));

        assertEq(usdc.balanceOf(client), PRINCIPAL, "client fully refunded");
        // firmFee == 0 -> firm owner (deployer) received nothing extra from this job.
        assertEq(usdc.balanceOf(address(vault)), 0, "vault drained");
        assertEq(usdc.balanceOf(address(jobs)), 0, "jobmanager holds no residual");

        // Reputation recorded: 1 job, 0 successful (PnL == 0 is not > 0), cumulativePnL 0.
        IReputationRegistry.Reputation memory rep = reputation.getReputation(firmTokenId);
        assertEq(rep.totalJobs, 1);
        assertEq(rep.successfulJobs, 0);
        assertEq(rep.cumulativePnL, int256(0));

        // Validation credential recorded.
        assertEq(validation.credentialCountFor(firmTokenId), 1);
    }

    /// @notice OPTIONAL B-full DEX path: wire the src/ MockDexRouter, do a real
    ///         BUY then SELL round-trip at a flat price (PnL 0), settle, full refund.
    ///         Proves DeployTestnet's DEPLOY_DEX_PATH block produces a working router.
    function test_dexPath_buySellRoundTripThenSettle() public {
        // Deploy + seed + wire the router exactly as DeployTestnet does.
        MockDexRouter router = new MockDexRouter();
        usdc.mint(address(router), 1_000_000e6);
        wmnt.mint(address(router), 1_000_000e18);
        router.setPrice(address(usdc), address(wmnt), 0.5e30); // 1 USDC -> 0.5 WMNT (MNT=2 USDC)
        router.setPrice(address(wmnt), address(usdc), 2e6); // 1 WMNT -> 2 USDC

        vault.setDexRouter(address(router));
        vault.setExecutor(executor, true);

        // Client hires firm.
        usdc.mint(client, PRINCIPAL);
        vm.startPrank(client);
        usdc.approve(address(jobs), PRINCIPAL);
        uint256 jobId = jobs.createJob(
            firmTokenId,
            address(usdc),
            PRINCIPAL,
            address(wmnt),
            DURATION,
            PERF_FEE_BPS
        );
        vm.stopPrank();

        // Executor trades: BUY 500 USDC -> 250 WMNT, then SELL back -> 500 USDC.
        vm.prank(executor);
        uint256 wmntOut = vault.trade(jobId, ITradingVault.TradeKind.Buy, 500e6, 0);
        assertEq(wmntOut, 250e18);

        vm.prank(executor);
        uint256 usdcOut = vault.trade(jobId, ITradingVault.TradeKind.Sell, 250e18, 0);
        assertEq(usdcOut, 500e6);

        ITradingVault.JobBalance memory jb = vault.getJobBalance(jobId);
        assertEq(jb.principalBalance, PRINCIPAL); // flat price -> back to 1000 USDC
        assertEq(jb.baseBalance, 0);
        assertEq(jb.tradeCount, 2);

        // Settle: flat round-trip -> PnL 0 -> full refund.
        vm.warp(block.timestamp + DURATION + 1);
        jobs.settleJob(jobId);

        IJobManager.Job memory settled = jobs.getJob(jobId);
        assertEq(uint8(settled.state), uint8(IJobManager.JobState.Settled));
        assertEq(settled.finalPnL, int256(0));
        assertEq(usdc.balanceOf(client), PRINCIPAL);
        assertEq(validation.credentialCountFor(firmTokenId), 1);
    }
}
