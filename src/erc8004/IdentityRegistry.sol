// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IIdentityRegistry } from "./IIdentityRegistry.sol";

/// @title IdentityRegistry — ERC-8004 Identity Registry
/// @notice ERC-721 based agent identity. Firm tokens are transferable (enables ERC-7857
///         transfer of the strategy brain). Sub-agent tokens are soulbound to firm.
/// @dev Mantle Turing Test Hackathon 2026 — Track 1 AI Trading & Strategy
contract IdentityRegistry is ERC721, IIdentityRegistry {
    uint256 private _nextTokenId;
    mapping(uint256 => Identity) private _identities;

    error InvalidParent();
    error NotOwner();
    error SoulboundTransferDisallowed();
    error InvalidKindForParent();
    error NonexistentToken();

    constructor() ERC721("Mantle Agent Identity", "MAID") {
        _nextTokenId = 1; // tokenId 0 reserved as "no parent" sentinel
    }

    // -------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------

    function register(
        AgentKind kind,
        uint256 parentTokenId,
        string calldata metadataURI,
        string calldata serviceEndpoint
    )
        external
        returns (uint256 tokenId)
    {
        if (kind == AgentKind.Firm) {
            if (parentTokenId != 0) revert InvalidKindForParent();
        } else {
            if (parentTokenId == 0) revert InvalidParent();
            if (!_exists(parentTokenId)) revert InvalidParent();
            if (_identities[parentTokenId].kind != AgentKind.Firm) revert InvalidParent();
            if (ownerOf(parentTokenId) != msg.sender) revert NotOwner();
        }

        tokenId = _nextTokenId++;
        _identities[tokenId] = Identity({
            tokenId: tokenId,
            owner: msg.sender,
            kind: kind,
            createdAt: uint64(block.timestamp),
            parentTokenId: parentTokenId,
            metadataURI: metadataURI,
            serviceEndpoint: serviceEndpoint
        });

        _safeMint(msg.sender, tokenId);

        emit AgentRegistered(tokenId, msg.sender, kind, parentTokenId, metadataURI);
    }

    function updateMetadata(uint256 tokenId, string calldata metadataURI) external {
        if (!_exists(tokenId)) revert NonexistentToken();
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();

        _identities[tokenId].metadataURI = metadataURI;
        emit MetadataUpdated(tokenId, metadataURI);
    }

    function updateServiceEndpoint(uint256 tokenId, string calldata serviceEndpoint) external {
        if (!_exists(tokenId)) revert NonexistentToken();
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();

        _identities[tokenId].serviceEndpoint = serviceEndpoint;
        emit ServiceEndpointUpdated(tokenId, serviceEndpoint);
    }

    // -------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------

    function getIdentity(uint256 tokenId) external view returns (Identity memory) {
        if (!_exists(tokenId)) revert NonexistentToken();
        return _identities[tokenId];
    }

    function ownerOfAgent(uint256 tokenId) external view returns (address) {
        return ownerOf(tokenId);
    }

    function totalAgents() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert NonexistentToken();
        return _identities[tokenId].metadataURI;
    }

    // -------------------------------------------------------------------
    // Soulbound enforcement
    //   - Firm tokens: transferable (so they can be wrapped in ERC-7857)
    //   - Sub-agent tokens: soulbound (cannot transfer separately from firm)
    // -------------------------------------------------------------------

    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        // Allow mint (from == 0) and burn (to == 0) freely.
        if (from != address(0) && to != address(0)) {
            if (_identities[tokenId].kind != AgentKind.Firm) {
                revert SoulboundTransferDisallowed();
            }
        }
        return super._update(to, tokenId, auth);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
