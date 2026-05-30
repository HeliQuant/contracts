// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IdentityRegistry } from "../../src/erc8004/IdentityRegistry.sol";
import { ReputationRegistry } from "../../src/erc8004/ReputationRegistry.sol";
import { IIdentityRegistry } from "../../src/erc8004/IIdentityRegistry.sol";
import { IReputationRegistry } from "../../src/erc8004/IReputationRegistry.sol";

contract ReputationRegistryTest is Test {
    IdentityRegistry internal identity;
    ReputationRegistry internal rep;

    address internal owner = address(this);
    address internal alice = address(0xA11CE);
    address internal jobManager = address(0x10B);
    uint256 internal firmId;

    function setUp() public {
        identity = new IdentityRegistry();
        rep = new ReputationRegistry(address(identity), owner);
        rep.setAuthorizedReporter(jobManager, true);

        vm.prank(alice);
        firmId = identity.register(IIdentityRegistry.AgentKind.Firm, 0, "ipfs://f", "");
    }

    function test_recordWin() public {
        vm.prank(jobManager);
        rep.recordJobOutcome(firmId, 1, int256(100e6), 1000e6, 1100e6);

        IReputationRegistry.Reputation memory r = rep.getReputation(firmId);
        assertEq(r.totalJobs, 1);
        assertEq(r.successfulJobs, 1);
        assertEq(r.cumulativePnL, int256(100e6));
        assertEq(r.totalVolume, 1000e6);
        assertEq(r.peakBalance, 1100e6);
        assertEq(rep.winRateBps(firmId), 10_000);
    }

    function test_recordLossUpdatesDrawdown() public {
        vm.startPrank(jobManager);
        // Initial win sets peak.
        rep.recordJobOutcome(firmId, 1, int256(100e6), 1000e6, 1100e6);
        // Loss drives balance down to 900 -> drawdown vs peak 1100 = 18.18% -> 1818 bps
        rep.recordJobOutcome(firmId, 2, -int256(200e6), 1000e6, 900e6);
        vm.stopPrank();

        IReputationRegistry.Reputation memory r = rep.getReputation(firmId);
        assertEq(r.totalJobs, 2);
        assertEq(r.successfulJobs, 1);
        assertEq(r.cumulativePnL, -int256(100e6));
        assertGt(r.maxDrawdownBps, 1800);
        assertLt(r.maxDrawdownBps, 1900);
        assertEq(rep.winRateBps(firmId), 5_000);
    }

    function test_revert_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(ReputationRegistry.NotAuthorized.selector);
        rep.recordJobOutcome(firmId, 1, int256(50), 100, 1050);
    }
}
