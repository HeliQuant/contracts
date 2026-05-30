// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IAlloraConsumer — Mantle-side consumer interface for Allora Network predictions
/// @notice Verifies and stores signed predictions submitted by Allora topic publishers.
///         Any on-chain consumer (Signal Agent, frontend, other dapps) can read the
///         latest aggregated inference per topic.
interface IAlloraConsumer {
    /// @notice The data payload that the Allora topic publisher signs off-chain.
    struct NetworkInferenceData {
        uint256 topicId;
        int256 networkInference;       // signed fixed-point (1e18 scale)
        uint256 networkInferenceTimestamp;
        uint64 confidenceBps;           // 0-10000
        bytes extraData;                // reserved (model id, version, etc.)
    }

    struct SignedInferenceMessage {
        NetworkInferenceData data;
        bytes signature;
    }

    struct StoredInference {
        int256 value;
        uint256 timestamp;
        uint64 confidenceBps;
        address publishedBy;
    }

    event InferenceRecorded(
        uint256 indexed topicId,
        int256 value,
        uint256 timestamp,
        uint64 confidenceBps,
        address indexed publisher
    );

    event TrustedSignerUpdated(address indexed signer, bool trusted);
    event TopicEnabled(uint256 indexed topicId, bool enabled);
    event MaxFreshnessUpdated(uint256 maxFreshnessSeconds);

    function submitInference(SignedInferenceMessage calldata message) external;
    function getLatestInference(uint256 topicId) external view returns (StoredInference memory);
    function isTopicEnabled(uint256 topicId) external view returns (bool);
}
