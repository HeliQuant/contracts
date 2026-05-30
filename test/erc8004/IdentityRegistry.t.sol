// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IdentityRegistry } from "../../src/erc8004/IdentityRegistry.sol";
import { IIdentityRegistry } from "../../src/erc8004/IIdentityRegistry.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry internal registry;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        registry = new IdentityRegistry();
    }

    function test_registerFirm() public {
        vm.prank(alice);
        uint256 firmId = registry.register(
            IIdentityRegistry.AgentKind.Firm,
            0,
            "ipfs://firm-meta",
            "https://firm.example/a2a"
        );

        assertEq(firmId, 1);
        assertEq(registry.ownerOf(firmId), alice);
        assertEq(registry.totalAgents(), 1);

        IIdentityRegistry.Identity memory id = registry.getIdentity(firmId);
        assertEq(uint8(id.kind), uint8(IIdentityRegistry.AgentKind.Firm));
        assertEq(id.parentTokenId, 0);
    }

    function test_registerSubAgent() public {
        vm.startPrank(alice);
        uint256 firmId = registry.register(
            IIdentityRegistry.AgentKind.Firm,
            0,
            "ipfs://firm",
            ""
        );
        uint256 signalId = registry.register(
            IIdentityRegistry.AgentKind.Signal,
            firmId,
            "ipfs://signal",
            "https://firm.example/agents/signal"
        );
        vm.stopPrank();

        IIdentityRegistry.Identity memory id = registry.getIdentity(signalId);
        assertEq(id.parentTokenId, firmId);
        assertEq(uint8(id.kind), uint8(IIdentityRegistry.AgentKind.Signal));
    }

    function test_revert_subAgentWithoutParent() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidParent.selector);
        registry.register(IIdentityRegistry.AgentKind.Signal, 0, "ipfs://x", "");
    }

    function test_revert_subAgentNotOwnerOfParent() public {
        vm.prank(alice);
        uint256 firmId = registry.register(
            IIdentityRegistry.AgentKind.Firm,
            0,
            "ipfs://firm",
            ""
        );

        vm.prank(bob);
        vm.expectRevert(IdentityRegistry.NotOwner.selector);
        registry.register(IIdentityRegistry.AgentKind.Signal, firmId, "ipfs://x", "");
    }

    function test_firmIsTransferable() public {
        vm.prank(alice);
        uint256 firmId = registry.register(
            IIdentityRegistry.AgentKind.Firm,
            0,
            "ipfs://firm",
            ""
        );

        vm.prank(alice);
        registry.transferFrom(alice, bob, firmId);

        assertEq(registry.ownerOf(firmId), bob);
    }

    function test_revert_subAgentSoulbound() public {
        vm.startPrank(alice);
        uint256 firmId = registry.register(IIdentityRegistry.AgentKind.Firm, 0, "ipfs://f", "");
        uint256 signalId = registry.register(
            IIdentityRegistry.AgentKind.Signal,
            firmId,
            "ipfs://s",
            ""
        );

        vm.expectRevert(IdentityRegistry.SoulboundTransferDisallowed.selector);
        registry.transferFrom(alice, bob, signalId);
        vm.stopPrank();
    }

    function test_updateMetadata() public {
        vm.prank(alice);
        uint256 firmId = registry.register(IIdentityRegistry.AgentKind.Firm, 0, "ipfs://a", "");

        vm.prank(alice);
        registry.updateMetadata(firmId, "ipfs://b");

        assertEq(registry.tokenURI(firmId), "ipfs://b");
    }
}
