// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IIdentityRegistry — ERC-8004 Identity Registry interface
/// @notice On-chain identity registry for autonomous AI agents on Mantle
interface IIdentityRegistry {
    enum AgentKind {
        Firm,       // Top-level trading firm (transferable identity)
        Research,
        Signal,
        Risk,
        Execution,
        Reputation,
        Custom
    }

    struct Identity {
        uint256 tokenId;
        address owner;
        AgentKind kind;
        uint64 createdAt;
        uint256 parentTokenId; // 0 if no parent (firm has none)
        string metadataURI;    // off-chain agent descriptor (IPFS/HTTPS)
        string serviceEndpoint; // optional callable endpoint (A2A protocol)
    }

    event AgentRegistered(
        uint256 indexed tokenId,
        address indexed owner,
        AgentKind indexed kind,
        uint256 parentTokenId,
        string metadataURI
    );

    event MetadataUpdated(uint256 indexed tokenId, string metadataURI);
    event ServiceEndpointUpdated(uint256 indexed tokenId, string serviceEndpoint);

    /// @notice Register a new agent identity. Firm identities are transferable; sub-agents soulbound.
    function register(
        AgentKind kind,
        uint256 parentTokenId,
        string calldata metadataURI,
        string calldata serviceEndpoint
    ) external returns (uint256 tokenId);

    function updateMetadata(uint256 tokenId, string calldata metadataURI) external;
    function updateServiceEndpoint(uint256 tokenId, string calldata serviceEndpoint) external;

    function getIdentity(uint256 tokenId) external view returns (Identity memory);
    function ownerOfAgent(uint256 tokenId) external view returns (address);
    function totalAgents() external view returns (uint256);
}
