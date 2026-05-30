// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { AlloraConsumer } from "../src/allora/AlloraConsumer.sol";
import { IAlloraConsumer } from "../src/allora/IAlloraConsumer.sol";

contract AlloraConsumerTest is Test {
    AlloraConsumer internal consumer;

    uint256 internal signerKey = 0xA110A1;
    address internal signer;
    address internal owner = address(this);

    uint256 internal constant TOPIC_BTC = 1;

    function setUp() public {
        signer = vm.addr(signerKey);
        consumer = new AlloraConsumer(owner);
        consumer.setTrustedSigner(signer, true);
        consumer.setTopicEnabled(TOPIC_BTC, true);
    }

    function _sign(IAlloraConsumer.NetworkInferenceData memory data, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = consumer.digestFor(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_submitAndRead() public {
        IAlloraConsumer.NetworkInferenceData memory data = IAlloraConsumer.NetworkInferenceData({
            topicId: TOPIC_BTC,
            networkInference: int256(67_000e18),
            networkInferenceTimestamp: block.timestamp,
            confidenceBps: 8500,
            extraData: ""
        });

        bytes memory sig = _sign(data, signerKey);

        consumer.submitInference(IAlloraConsumer.SignedInferenceMessage({
            data: data,
            signature: sig
        }));

        IAlloraConsumer.StoredInference memory latest = consumer.getLatestInference(TOPIC_BTC);
        assertEq(latest.value, int256(67_000e18));
        assertEq(latest.confidenceBps, 8500);
        assertEq(latest.publishedBy, signer);
    }

    function test_revert_untrustedSigner() public {
        uint256 rogueKey = 0xBADBAD;

        IAlloraConsumer.NetworkInferenceData memory data = IAlloraConsumer.NetworkInferenceData({
            topicId: TOPIC_BTC,
            networkInference: int256(60_000e18),
            networkInferenceTimestamp: block.timestamp,
            confidenceBps: 7000,
            extraData: ""
        });

        bytes memory sig = _sign(data, rogueKey);

        vm.expectRevert(AlloraConsumer.UntrustedSigner.selector);
        consumer.submitInference(IAlloraConsumer.SignedInferenceMessage({
            data: data,
            signature: sig
        }));
    }

    function test_revert_topicDisabled() public {
        uint256 unknownTopic = 99;

        IAlloraConsumer.NetworkInferenceData memory data = IAlloraConsumer.NetworkInferenceData({
            topicId: unknownTopic,
            networkInference: int256(1),
            networkInferenceTimestamp: block.timestamp,
            confidenceBps: 5000,
            extraData: ""
        });

        bytes memory sig = _sign(data, signerKey);

        vm.expectRevert(AlloraConsumer.TopicNotEnabled.selector);
        consumer.submitInference(IAlloraConsumer.SignedInferenceMessage({
            data: data,
            signature: sig
        }));
    }

    function test_revert_staleData() public {
        IAlloraConsumer.NetworkInferenceData memory data = IAlloraConsumer.NetworkInferenceData({
            topicId: TOPIC_BTC,
            networkInference: int256(60_000e18),
            networkInferenceTimestamp: block.timestamp,
            confidenceBps: 7000,
            extraData: ""
        });
        bytes memory sig = _sign(data, signerKey);

        // Move forward past the freshness window.
        vm.warp(block.timestamp + 31 minutes);

        vm.expectRevert(AlloraConsumer.StaleData.selector);
        consumer.submitInference(IAlloraConsumer.SignedInferenceMessage({
            data: data,
            signature: sig
        }));
    }

    function test_revert_notNewer() public {
        IAlloraConsumer.NetworkInferenceData memory data = IAlloraConsumer.NetworkInferenceData({
            topicId: TOPIC_BTC,
            networkInference: int256(60_000e18),
            networkInferenceTimestamp: block.timestamp,
            confidenceBps: 7000,
            extraData: ""
        });
        bytes memory sig = _sign(data, signerKey);

        consumer.submitInference(IAlloraConsumer.SignedInferenceMessage({
            data: data,
            signature: sig
        }));

        // Replay the same payload — same timestamp, must revert.
        vm.expectRevert(AlloraConsumer.InferenceNotNewer.selector);
        consumer.submitInference(IAlloraConsumer.SignedInferenceMessage({
            data: data,
            signature: sig
        }));
    }
}
