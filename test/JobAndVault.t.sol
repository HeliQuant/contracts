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
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockDexRouter } from "./mocks/MockDexRouter.sol";

contract JobAndVaultTest is Test {
    IdentityRegistry internal identity;
    ReputationRegistry internal reputation;
    ValidationRegistry internal validation;
    TradingVault internal vault;
    JobManager internal jobs;
    MockERC20 internal usdc;
    MockERC20 internal wmnt;
    MockDexRouter internal router;

    address internal owner = address(this);
    address internal firmOwner = address(0xF14);
    address internal client = address(0xC11E);
    address internal executor = address(0xE5E);

    uint256 internal firmId;
    uint256 internal constant PRINCIPAL = 1_000e6; // 1,000 USDC

    function setUp() public {
        identity = new IdentityRegistry();
        reputation = new ReputationRegistry(address(identity), owner);
        validation = new ValidationRegistry(address(identity), owner);
        vault = new TradingVault(owner);

        jobs = new JobManager(
            owner,
            address(identity),
            address(reputation),
            address(validation),
            address(vault)
        );

        reputation.setAuthorizedReporter(address(jobs), true);
        validation.setAuthorizedSubmitter(address(jobs), true);

        vault.setJobManager(address(jobs));
        vault.setExecutor(executor, true);

        usdc = new MockERC20("USD Coin", "USDC", 6);
        wmnt = new MockERC20("Wrapped Mantle", "WMNT", 18);
        router = new MockDexRouter();
        vault.setDexRouter(address(router));

        // Seed the router with liquidity so it can complete swaps.
        usdc.mint(address(router), 1_000_000e6);
        wmnt.mint(address(router), 1_000_000e18);

        // Initial price 1 USDC -> 1 WMNT (in 1e18 scale, but USDC is 6 decimals so this is
        // intentionally a notional unit price for the test). We will increase to simulate profit.
        // Actually, since USDC has 6 decimals and WMNT has 18, "1 USDC -> 1 WMNT" means
        // 1e6 USDC -> 1e18 WMNT, so price (out/in) = 1e30 / 1e6 = 1e24... Let's use a clean
        // notional: 1e6 USDC in -> 0.5e18 WMNT out at MNT=2 USDC, so price = 0.5e30 / 1e6 = 0.5e24.
        // For brevity, define:
        //   BUY price = WMNT_out / USDC_in in 1e18 = (5e17) means 1 USDC -> 0.5 WMNT
        //   But scale-aware: with USDC having 6 decimals and WMNT 18, we want
        //   amountOut(WMNT, 1e18-scaled) = amountIn(USDC, 1e6-scaled) * priceX18 / 1e18
        //   For "1 USDC -> 0.5 WMNT" => 1e6 * price / 1e18 = 0.5e18 => price = 0.5e30
        router.setPrice(address(usdc), address(wmnt), 0.5e30); // MNT = 2 USDC
        router.setPrice(address(wmnt), address(usdc), 2e6);    // 1 WMNT -> 2 USDC (1e18 * 2e6 / 1e18 = 2e6)

        // Register firm
        vm.prank(firmOwner);
        firmId = identity.register(IIdentityRegistry.AgentKind.Firm, 0, "ipfs://firm", "");

        // Fund client
        usdc.mint(client, PRINCIPAL);
        vm.prank(client);
        usdc.approve(address(jobs), PRINCIPAL);
    }

    function _createJob() internal returns (uint256 jobId) {
        vm.prank(client);
        jobId = jobs.createJob(
            firmId,
            address(usdc),
            PRINCIPAL,
            address(wmnt),
            1 hours,
            2_000 // 20% perf fee
        );
    }

    function test_createJobMovesPrincipalToVault() public {
        uint256 jobId = _createJob();

        ITradingVault.JobBalance memory jb = vault.getJobBalance(jobId);
        assertEq(jb.principalToken, address(usdc));
        assertEq(jb.principalDeposit, PRINCIPAL);
        assertEq(jb.principalBalance, PRINCIPAL);
        assertEq(jb.baseBalance, 0);
        assertEq(usdc.balanceOf(address(vault)), PRINCIPAL);
        assertEq(usdc.balanceOf(client), 0);

        IJobManager.Job memory j = jobs.getJob(jobId);
        assertEq(uint8(j.state), uint8(IJobManager.JobState.Active));
    }

    function test_executeBuyAndSell() public {
        uint256 jobId = _createJob();

        vm.prank(executor);
        uint256 wmntOut = vault.trade(jobId, ITradingVault.TradeKind.Buy, 500e6, 0);
        // 500 USDC at MNT=2 USDC => 250 WMNT
        assertEq(wmntOut, 250e18);

        ITradingVault.JobBalance memory jb = vault.getJobBalance(jobId);
        assertEq(jb.principalBalance, 500e6);
        assertEq(jb.baseBalance, 250e18);

        // Now sell back at 2 USDC/MNT => 500 USDC out
        vm.prank(executor);
        uint256 usdcOut = vault.trade(jobId, ITradingVault.TradeKind.Sell, 250e18, 0);
        assertEq(usdcOut, 500e6);

        jb = vault.getJobBalance(jobId);
        assertEq(jb.principalBalance, 1_000e6);
        assertEq(jb.baseBalance, 0);
    }

    function test_settleProfit() public {
        uint256 jobId = _createJob();

        // Buy at MNT=2 USDC: 500 USDC -> 250 WMNT
        vm.prank(executor);
        vault.trade(jobId, ITradingVault.TradeKind.Buy, 500e6, 0);

        // Price pumps to MNT=3 USDC
        router.setPrice(address(wmnt), address(usdc), 3e6);
        // Top up router USDC liquidity for the bigger payout.
        usdc.mint(address(router), 1_000e6);

        // Sell 250 WMNT -> 750 USDC
        vm.prank(executor);
        vault.trade(jobId, ITradingVault.TradeKind.Sell, 250e18, 0);

        ITradingVault.JobBalance memory jb = vault.getJobBalance(jobId);
        // Started with 1000, after sell back at higher price: 500 + 750 = 1250 USDC
        assertEq(jb.principalBalance, 1_250e6);

        // Skip past duration and settle.
        vm.warp(block.timestamp + 1 hours + 1);
        jobs.settleJob(jobId);

        IJobManager.Job memory j = jobs.getJob(jobId);
        assertEq(uint8(j.state), uint8(IJobManager.JobState.Settled));
        assertEq(j.finalPrincipalBalance, 1_250e6);
        assertEq(j.finalPnL, int256(250e6));

        // 20% perf fee on 250 profit = 50 USDC to firm owner, 1200 to client
        assertEq(usdc.balanceOf(firmOwner), 50e6);
        assertEq(usdc.balanceOf(client), 1_200e6);

        // Reputation updated
        IReputationRegistry.Reputation memory r = reputation.getReputation(firmId);
        assertEq(r.totalJobs, 1);
        assertEq(r.successfulJobs, 1);

        // Validation credential recorded
        assertEq(validation.credentialCountFor(firmId), 1);
    }

    function test_settleLossNoFee() public {
        uint256 jobId = _createJob();

        // Buy at MNT=2 USDC: 1000 USDC -> 500 WMNT
        vm.prank(executor);
        vault.trade(jobId, ITradingVault.TradeKind.Buy, 1_000e6, 0);

        // Price dumps to MNT=1.5 USDC
        router.setPrice(address(wmnt), address(usdc), 1.5e6);

        vm.warp(block.timestamp + 1 hours + 1);
        // Settling auto-closes any remaining base balance back to principal at current price.
        jobs.settleJob(jobId);

        IJobManager.Job memory j = jobs.getJob(jobId);
        // 500 WMNT -> 750 USDC, final = 750
        assertEq(j.finalPrincipalBalance, 750e6);
        assertEq(j.finalPnL, -int256(250e6));

        // No firm fee on loss; client gets all 750
        assertEq(usdc.balanceOf(firmOwner), 0);
        assertEq(usdc.balanceOf(client), 750e6);

        // Reputation: 1 job, 0 successful
        IReputationRegistry.Reputation memory r = reputation.getReputation(firmId);
        assertEq(r.totalJobs, 1);
        assertEq(r.successfulJobs, 0);
        assertEq(r.cumulativePnL, -int256(250e6));
    }

    function test_revert_settleBeforeMaturity() public {
        uint256 jobId = _createJob();
        vm.expectRevert(JobManager.JobNotMature.selector);
        jobs.settleJob(jobId);
    }

    function test_revert_invalidFirm() public {
        vm.startPrank(firmOwner);
        uint256 signalId = identity.register(
            IIdentityRegistry.AgentKind.Signal,
            firmId,
            "ipfs://signal",
            ""
        );
        vm.stopPrank();

        vm.prank(client);
        vm.expectRevert(JobManager.InvalidFirm.selector);
        jobs.createJob(
            signalId, // not a firm — should revert
            address(usdc),
            PRINCIPAL,
            address(wmnt),
            1 hours,
            2_000
        );
    }
}
