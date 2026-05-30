// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console2 } from "forge-std/Script.sol";
import { IdentityRegistry } from "../src/erc8004/IdentityRegistry.sol";
import { ReputationRegistry } from "../src/erc8004/ReputationRegistry.sol";
import { ValidationRegistry } from "../src/erc8004/ValidationRegistry.sol";
import { AlloraConsumer } from "../src/allora/AlloraConsumer.sol";
import { TradingVault } from "../src/vault/TradingVault.sol";
import { JobManager } from "../src/erc8183/JobManager.sol";

/// @title Deploy - Deploy + wire the full Mantle AI Trading Firm stack
/// @notice Usage:
///   forge script script/Deploy.s.sol --rpc-url mantle_sepolia --broadcast --verify
contract Deploy is Script {
    struct Deployment {
        address identityRegistry;
        address reputationRegistry;
        address validationRegistry;
        address alloraConsumer;
        address tradingVault;
        address jobManager;
    }

    function run() external returns (Deployment memory d) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address alloraSigner = vm.envOr("ALLORA_TRUSTED_SIGNER", address(0));

        console2.log("Deployer:", deployer);
        console2.log("Allora trusted signer:", alloraSigner);

        vm.startBroadcast(deployerKey);

        IdentityRegistry identity = new IdentityRegistry();
        ReputationRegistry reputation = new ReputationRegistry(address(identity), deployer);
        ValidationRegistry validation = new ValidationRegistry(address(identity), deployer);
        AlloraConsumer consumer = new AlloraConsumer(deployer);
        TradingVault vault = new TradingVault(deployer);

        JobManager jobs = new JobManager(
            deployer,
            address(identity),
            address(reputation),
            address(validation),
            address(vault)
        );

        // Wiring
        reputation.setAuthorizedReporter(address(jobs), true);
        validation.setAuthorizedSubmitter(address(jobs), true);
        vault.setJobManager(address(jobs));

        // Optional: pre-authorize Allora signer if configured
        if (alloraSigner != address(0)) {
            consumer.setTrustedSigner(alloraSigner, true);
            consumer.setTopicEnabled(1, true); // topic 1 = BTC/USD (Allora default)
            consumer.setTopicEnabled(2, true); // topic 2 = ETH/USD
            consumer.setTopicEnabled(3, true); // topic 3 = MNT/USD (we will set up)
        }

        vm.stopBroadcast();

        d = Deployment({
            identityRegistry: address(identity),
            reputationRegistry: address(reputation),
            validationRegistry: address(validation),
            alloraConsumer: address(consumer),
            tradingVault: address(vault),
            jobManager: address(jobs)
        });

        console2.log("");
        console2.log("=================================================");
        console2.log("  Mantle AI Trading Firm - Deployment complete");
        console2.log("=================================================");
        console2.log("IdentityRegistry   :", d.identityRegistry);
        console2.log("ReputationRegistry :", d.reputationRegistry);
        console2.log("ValidationRegistry :", d.validationRegistry);
        console2.log("AlloraConsumer     :", d.alloraConsumer);
        console2.log("TradingVault       :", d.tradingVault);
        console2.log("JobManager         :", d.jobManager);
        console2.log("=================================================");

        _writeDeploymentJson(d);
    }

    function _writeDeploymentJson(Deployment memory d) internal {
        string memory chainName = _chainName();
        string memory path = string.concat("./deployments/", chainName, ".json");

        string memory json = "deployment";
        vm.serializeAddress(json, "identityRegistry", d.identityRegistry);
        vm.serializeAddress(json, "reputationRegistry", d.reputationRegistry);
        vm.serializeAddress(json, "validationRegistry", d.validationRegistry);
        vm.serializeAddress(json, "alloraConsumer", d.alloraConsumer);
        vm.serializeAddress(json, "tradingVault", d.tradingVault);
        string memory finalJson = vm.serializeAddress(json, "jobManager", d.jobManager);

        vm.writeJson(finalJson, path);
        console2.log("Wrote:", path);
    }

    function _chainName() internal view returns (string memory) {
        uint256 id = block.chainid;
        if (id == 5000) return "mantle_mainnet";
        if (id == 5003) return "mantle_sepolia";
        if (id == 31_337) return "anvil";
        return vm.toString(id);
    }
}
