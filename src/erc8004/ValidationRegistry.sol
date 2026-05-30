// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IIdentityRegistry } from "./IIdentityRegistry.sol";
import { IValidationRegistry } from "./IValidationRegistry.sol";

/// @title ValidationRegistry — ERC-8004 Validation Registry
/// @notice Records cryptographic proof-of-work credentials for completed Jobs.
contract ValidationRegistry is Ownable, IValidationRegistry {
    IIdentityRegistry public immutable identityRegistry;

    uint256 private _nextCredentialId = 1;
    mapping(uint256 => ValidationCredential) private _credentials;
    mapping(uint256 => uint256[]) private _agentCredentials; // agentTokenId => credentialIds

    mapping(address => bool) public authorizedSubmitters;

    error NotAuthorized();
    error UnknownAgent();
    error UnknownCredential();
    error InvalidIdentityRegistry();

    modifier onlyAuthorized() {
        if (!authorizedSubmitters[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor(address identityRegistry_, address initialOwner) Ownable(initialOwner) {
        if (identityRegistry_ == address(0)) revert InvalidIdentityRegistry();
        identityRegistry = IIdentityRegistry(identityRegistry_);
    }

    // -------------------------------------------------------------------
    // Authorization
    // -------------------------------------------------------------------

    function setAuthorizedSubmitter(address submitter, bool allowed) external onlyOwner {
        authorizedSubmitters[submitter] = allowed;
        emit AuthorizedSubmitterUpdated(submitter, allowed);
    }

    // -------------------------------------------------------------------
    // Credentials
    // -------------------------------------------------------------------

    function recordCredential(
        uint256 agentTokenId,
        uint256 jobId,
        ProofKind kind,
        bytes32 proofHash,
        address attestedBy
    )
        external
        onlyAuthorized
        returns (uint256 credentialId)
    {
        identityRegistry.getIdentity(agentTokenId); // reverts if non-existent

        credentialId = _nextCredentialId++;
        _credentials[credentialId] = ValidationCredential({
            agentTokenId: agentTokenId,
            jobId: jobId,
            kind: kind,
            proofHash: proofHash,
            timestamp: uint64(block.timestamp),
            attestedBy: attestedBy
        });

        _agentCredentials[agentTokenId].push(credentialId);

        emit CredentialRecorded(agentTokenId, jobId, proofHash, kind, attestedBy);
    }

    // -------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------

    function getCredential(uint256 credentialId)
        external
        view
        returns (ValidationCredential memory)
    {
        if (_credentials[credentialId].timestamp == 0) revert UnknownCredential();
        return _credentials[credentialId];
    }

    function credentialCountFor(uint256 agentTokenId) external view returns (uint256) {
        return _agentCredentials[agentTokenId].length;
    }

    function credentialIdsOf(uint256 agentTokenId) external view returns (uint256[] memory) {
        return _agentCredentials[agentTokenId];
    }
}
