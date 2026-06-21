// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IAlloraConsumer } from "./IAlloraConsumer.sol";

/// @title AlloraConsumer — Mantle deployment of Allora Network's prediction consumer
/// @notice Receives signed inferences from Allora topic publishers and exposes them
///         to any on-chain consumer (Signal Agent, dApps, indexers).
/// @dev    This is the first Allora consumer deployment on Mantle Network. Mantle ecosystem
///         contribution: extends decentralized AI inference layer to Mantle.
contract AlloraConsumer is Ownable, EIP712, IAlloraConsumer {
    bytes32 private constant _NETWORK_INFERENCE_DATA_TYPEHASH = keccak256(
        "NetworkInferenceData(uint256 topicId,int256 networkInference,"
        "uint256 networkInferenceTimestamp,uint64 confidenceBps,bytes extraData)"
    );

    uint256 public maxFreshnessSeconds = 30 minutes;

    mapping(address => bool) public trustedSigners;
    mapping(uint256 => bool) public isTopicEnabled;
    mapping(uint256 => StoredInference) private _latest;

    error UntrustedSigner();
    error TopicNotEnabled();
    error StaleData();
    error FutureData();
    error InferenceNotNewer();
    error NoInferenceRecorded();
    error InvalidConfidence();

    constructor(address initialOwner) Ownable(initialOwner) EIP712("AlloraConsumer", "1") { }

    // -------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------

    function setTrustedSigner(address signer, bool trusted) external onlyOwner {
        trustedSigners[signer] = trusted;
        emit TrustedSignerUpdated(signer, trusted);
    }

    function setTopicEnabled(uint256 topicId, bool enabled) external onlyOwner {
        isTopicEnabled[topicId] = enabled;
        emit TopicEnabled(topicId, enabled);
    }

    function setMaxFreshnessSeconds(uint256 newValue) external onlyOwner {
        maxFreshnessSeconds = newValue;
        emit MaxFreshnessUpdated(newValue);
    }

    // -------------------------------------------------------------------
    // Inference submission
    // -------------------------------------------------------------------

    function submitInference(SignedInferenceMessage calldata message) external {
        NetworkInferenceData calldata data = message.data;

        if (!isTopicEnabled[data.topicId]) revert TopicNotEnabled();
        if (data.confidenceBps > 10_000) revert InvalidConfidence();
        if (data.networkInferenceTimestamp > block.timestamp) revert FutureData();
        if (block.timestamp - data.networkInferenceTimestamp > maxFreshnessSeconds) {
            revert StaleData();
        }

        StoredInference storage prev = _latest[data.topicId];
        if (data.networkInferenceTimestamp <= prev.timestamp) revert InferenceNotNewer();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _NETWORK_INFERENCE_DATA_TYPEHASH,
                    data.topicId,
                    data.networkInference,
                    data.networkInferenceTimestamp,
                    data.confidenceBps,
                    keccak256(data.extraData)
                )
            )
        );

        address signer = ECDSA.recover(digest, message.signature);
        if (!trustedSigners[signer]) revert UntrustedSigner();

        _latest[data.topicId] = StoredInference({
            value: data.networkInference,
            timestamp: data.networkInferenceTimestamp,
            confidenceBps: data.confidenceBps,
            publishedBy: signer
        });

        emit InferenceRecorded(
            data.topicId,
            data.networkInference,
            data.networkInferenceTimestamp,
            data.confidenceBps,
            signer
        );
    }

    // -------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------

    function getLatestInference(uint256 topicId) external view returns (StoredInference memory) {
        StoredInference memory s = _latest[topicId];
        if (s.timestamp == 0) revert NoInferenceRecorded();
        return s;
    }

    /// @notice Compute the EIP-712 digest for a given inference data — exposed so the
    ///         off-chain relayer can validate signing locally before broadcast.
    function digestFor(NetworkInferenceData calldata data) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _NETWORK_INFERENCE_DATA_TYPEHASH,
                    data.topicId,
                    data.networkInference,
                    data.networkInferenceTimestamp,
                    data.confidenceBps,
                    keccak256(data.extraData)
                )
            )
        );
    }
}
