// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console2 } from "forge-std/Script.sol";
import { IIdentityRegistry } from "../src/erc8004/IIdentityRegistry.sol";
import { ReputationRegistry } from "../src/erc8004/ReputationRegistry.sol";
import { ValidationRegistry } from "../src/erc8004/ValidationRegistry.sol";
import { TradingVault } from "../src/vault/TradingVault.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { MockDexRouter } from "../src/mocks/MockDexRouter.sol";

/// @title DeployTestnet — Mint test tokens + register HeliQuant Firm + finish wiring
/// @notice Second-stage deploy for the ALREADY-deployed core stack on Mantle Sepolia.
///         Lets a demo user actually "hire the firm": deposit Mock USDC into JobManager
///         (HOLD/settle MVP) and get refunded on settle.
///
/// Reads existing core addresses from env (set these from deployments/mantle_sepolia.json):
///   IDENTITY_REGISTRY_ADDRESS, JOB_MANAGER_ADDRESS, TRADING_VAULT_ADDRESS,
///   REPUTATION_REGISTRY_ADDRESS, VALIDATION_REGISTRY_ADDRESS
/// Broadcasts with DEPLOYER_PRIVATE_KEY (must be the OWNER of the registries/vault to
/// re-assert wiring — on Mantle Sepolia that is 0x48379F4d1427209311E9FF0bcC4a354953ea631B).
///
/// Optional B-full DEX path (off by default): set DEPLOY_DEX_PATH=true to also deploy a
/// MockDexRouter, seed it with USDC/WMNT, and wire setDexRouter + setExecutor(deployer).
/// The HOLD/settle MVP works WITHOUT the DEX path.
///
/// USAGE (broadcast is a separate human-approved step — do NOT run during build/test):
///   forge script script/DeployTestnet.s.sol \
///     --rpc-url mantle_sepolia --broadcast
contract DeployTestnet is Script {
    // Demo defaults for the optional DEX seeding.
    uint256 internal constant DEX_USDC_SEED = 1_000_000e6; // 1,000,000 USDC
    uint256 internal constant DEX_WMNT_SEED = 1_000_000e18; // 1,000,000 WMNT

    /// @dev Resolved env config (kept in a struct to limit stack depth in run()).
    struct Core {
        address deployer;
        address identity;
        address jobManager;
        address vault;
        address reputation;
        address validation;
        bool deployDexPath;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Core memory c = _loadConfig(deployerKey);
        _logInputs(c);

        vm.startBroadcast(deployerKey);

        // 1) Mock tokens (public faucet so demo users can self-fund).
        MockERC20 usdc = new MockERC20("Mock USD Coin", "mUSDC", 6);
        MockERC20 wmnt = new MockERC20("Mock Wrapped Mantle", "mWMNT", 18);

        // 2) Register the HeliQuant Firm identity (ERC-8004).
        uint256 firmTokenId = _registerFirm(c.identity);

        // 3) Wiring required for settleJob() to succeed (idempotent).
        _ensureWiring(c);

        // 4) OPTIONAL: B-full DEX path (set DEPLOY_DEX_PATH=true to enable).
        address dexRouterAddr = address(0);
        if (c.deployDexPath) {
            dexRouterAddr = _deployDexPath(c, usdc, wmnt);
        }

        vm.stopBroadcast();

        _logOutputs(c, address(usdc), address(wmnt), firmTokenId, dexRouterAddr);
    }

    // ---------------------------------------------------------------------
    // Helpers (split out to keep run()'s stack shallow — via_ir stays off)
    // ---------------------------------------------------------------------

    function _loadConfig(uint256 deployerKey) internal view returns (Core memory c) {
        c.deployer = vm.addr(deployerKey);
        c.identity = vm.envAddress("IDENTITY_REGISTRY_ADDRESS");
        c.jobManager = vm.envAddress("JOB_MANAGER_ADDRESS");
        c.vault = vm.envAddress("TRADING_VAULT_ADDRESS");
        c.reputation = vm.envAddress("REPUTATION_REGISTRY_ADDRESS");
        c.validation = vm.envAddress("VALIDATION_REGISTRY_ADDRESS");
        c.deployDexPath = vm.envOr("DEPLOY_DEX_PATH", false);
    }

    /// @notice AgentKind.Firm requires parentTokenId == 0 (see IdentityRegistry).
    ///         The firm NFT mints to the broadcaster (deployer); firmFee on profitable
    ///         jobs is paid to ownerOfAgent(firmTokenId).
    function _registerFirm(address identityAddr) internal returns (uint256 firmTokenId) {
        firmTokenId = IIdentityRegistry(identityAddr).register(
            IIdentityRegistry.AgentKind.Firm,
            0,
            "ipfs://heliquant-firm", // TODO: replace with real metadata URI when ready
            "" // optional A2A service endpoint
        );
    }

    /// @notice settleJob() calls reputation.recordJobOutcome (onlyAuthorized reporters)
    ///         and validation.recordCredential (onlyAuthorized submitters). Both
    ///         registries are Ownable; only the owner (deployer) can grant these. The
    ///         vault must also know its JobManager. All guarded so re-runs are no-ops.
    function _ensureWiring(Core memory c) internal {
        ReputationRegistry reputation = ReputationRegistry(c.reputation);
        ValidationRegistry validation = ValidationRegistry(c.validation);
        TradingVault vault = TradingVault(c.vault);

        if (!reputation.authorizedReporters(c.jobManager)) {
            reputation.setAuthorizedReporter(c.jobManager, true);
            console2.log("Granted reputation reporter -> JobManager");
        }
        if (!validation.authorizedSubmitters(c.jobManager)) {
            validation.setAuthorizedSubmitter(c.jobManager, true);
            console2.log("Granted validation submitter -> JobManager");
        }
        if (vault.jobManager() != c.jobManager) {
            vault.setJobManager(c.jobManager);
            console2.log("Set vault.jobManager -> JobManager");
        }
    }

    /// @notice Deploys a fixed-ratio MockDexRouter, seeds it with both tokens, and wires
    ///         setDexRouter + setExecutor(deployer) so the Execution Agent can trade.
    ///         NOT a constant-product Uniswap V2 (no LP pair token) — the vault only
    ///         needs the swapExactTokensForTokens signature, which this satisfies. For
    ///         true AMM behaviour later, point setDexRouter at a real Merchant Moe / Agni
    ///         router and seed a real pool instead (TODO). NOT needed for HOLD/settle.
    function _deployDexPath(
        Core memory c,
        MockERC20 usdc,
        MockERC20 wmnt
    )
        internal
        returns (address dexRouterAddr)
    {
        MockDexRouter router = new MockDexRouter();
        dexRouterAddr = address(router);

        usdc.mint(dexRouterAddr, DEX_USDC_SEED);
        wmnt.mint(dexRouterAddr, DEX_WMNT_SEED);

        // Demo price: MNT = 2 USDC. Scale-aware (USDC 6dp, WMNT 18dp):
        //   BUY  1e6 USDC -> 0.5e18 WMNT  => price = 0.5e30
        //   SELL 1e18 WMNT -> 2e6  USDC   => price = 2e6
        router.setPrice(address(usdc), address(wmnt), 0.5e30);
        router.setPrice(address(wmnt), address(usdc), 2e6);

        TradingVault vault = TradingVault(c.vault);
        if (vault.dexRouter() != dexRouterAddr) {
            vault.setDexRouter(dexRouterAddr);
        }
        if (!vault.executors(c.deployer)) {
            vault.setExecutor(c.deployer, true);
        }
        console2.log("DEX path deployed + wired");
    }

    function _logInputs(Core memory c) internal pure {
        console2.log("Deployer            :", c.deployer);
        console2.log("IdentityRegistry    :", c.identity);
        console2.log("JobManager          :", c.jobManager);
        console2.log("TradingVault        :", c.vault);
        console2.log("ReputationRegistry  :", c.reputation);
        console2.log("ValidationRegistry  :", c.validation);
        console2.log("Deploy DEX path     :", c.deployDexPath);
    }

    function _logOutputs(
        Core memory c,
        address usdc,
        address wmnt,
        uint256 firmTokenId,
        address dexRouterAddr
    )
        internal
        pure
    {
        console2.log("");
        console2.log("=================================================");
        console2.log("  HeliQuant Testnet provisioning complete");
        console2.log("=================================================");
        console2.log("MOCK_USDC      :", usdc);
        console2.log("MOCK_WMNT      :", wmnt);
        console2.log("FIRM_TOKEN_ID  :", firmTokenId);
        if (c.deployDexPath) {
            console2.log("MOCK_DEX_ROUTER:", dexRouterAddr);
        }
        console2.log("-------------------------------------------------");
        console2.log("Paste into .env:");
        console2.log("  PRINCIPAL_TOKEN_ADDRESS=", usdc); // USDC = principal
        console2.log("  BASE_TOKEN_ADDRESS=", wmnt); // WMNT = traded base
        console2.log("  FIRM_TOKEN_ID=", firmTokenId);
        if (c.deployDexPath) {
            console2.log("  DEX_ROUTER_ADDRESS=", dexRouterAddr);
        }
        console2.log("=================================================");
    }
}
