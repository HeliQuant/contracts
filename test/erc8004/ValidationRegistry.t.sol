// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IdentityRegistry } from "../../src/erc8004/IdentityRegistry.sol";
import { ValidationRegistry } from "../../src/erc8004/ValidationRegistry.sol";
import { IIdentityRegistry } from "../../src/erc8004/IIdentityRegistry.sol";
import { IValidationRegistry } from "../../src/erc8004/IValidationRegistry.sol";

contract ValidationRegistryTest is Test {
    IdentityRegistry internal identity;
    ValidationRegistry internal validation;

    address internal owner = address(this);
    address internal jobManager = address(0x10B);
    address internal alice = address(0xA11CE);
    uint256 internal firmId;

    function setUp() public {
        identity = new IdentityRegistry();
        validation = new ValidationRegistry(address(identity), owner);
        validation.setAuthorizedSubmitter(jobManager, true);

        vm.prank(alice);
        firmId = identity.register(IIdentityRegistry.AgentKind.Firm, 0, "ipfs://f", "");
    }

    function test_recordCredential() public {
        bytes32 proof = keccak256("settled-job-1");

        vm.prank(jobManager);
        uint256 credentialId = validation.recordCredential(
            firmId,
            1,
            IValidationRegistry.ProofKind.OnchainStateCheck,
            proof,
            address(0)
        );

        assertEq(credentialId, 1);
        assertEq(validation.credentialCountFor(firmId), 1);

        IValidationRegistry.ValidationCredential memory c = validation.getCredential(credentialId);
        assertEq(c.agentTokenId, firmId);
        assertEq(c.jobId, 1);
        assertEq(c.proofHash, proof);
    }

    function test_revert_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(ValidationRegistry.NotAuthorized.selector);
        validation.recordCredential(
            firmId,
            1,
            IValidationRegistry.ProofKind.OnchainStateCheck,
            keccak256("x"),
            address(0)
        );
    }
}
