// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IValidationRegistry — ERC-8004 Validation Registry interface
/// @notice Stake-secured or ZK-secured proof of work credentials for agents
interface IValidationRegistry {
    enum ProofKind {
        OnchainStateCheck,  // settled by on-chain state (e.g., Job's TradingVault PnL)
        AttestedByValidator,
        ZKProof
    }

    struct ValidationCredential {
        uint256 agentTokenId;
        uint256 jobId;
        ProofKind kind;
        bytes32 proofHash;        // keccak256 of off-chain proof or on-chain digest
        uint64 timestamp;
        address attestedBy;       // 0x0 for OnchainStateCheck
    }

    event CredentialRecorded(
        uint256 indexed agentTokenId,
        uint256 indexed jobId,
        bytes32 indexed proofHash,
        ProofKind kind,
        address attestedBy
    );

    event AuthorizedSubmitterUpdated(address indexed submitter, bool allowed);

    function recordCredential(
        uint256 agentTokenId,
        uint256 jobId,
        ProofKind kind,
        bytes32 proofHash,
        address attestedBy
    ) external returns (uint256 credentialId);

    function getCredential(uint256 credentialId) external view returns (ValidationCredential memory);
    function credentialCountFor(uint256 agentTokenId) external view returns (uint256);
}
