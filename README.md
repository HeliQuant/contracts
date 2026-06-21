# contracts

> Smart contracts for **[HeliQuant](https://github.com/HeliQuant)** — autonomous multi-source intelligence trading firm on Mantle.

## Overview

Six core contracts implementing the on-chain layer of HeliQuant:

| Standard | Contract | Role |
|---|---|---|
| ERC-8004 | `IdentityRegistry` | NFT-based agent identity (firm + sub-agents) |
| ERC-8004 | `ReputationRegistry` | Per-agent perf counters: win rate, PnL, drawdown |
| ERC-8004 | `ValidationRegistry` | Cryptographic proof-of-work credentials per settled job |
| ERC-8183 | `JobManager` | Client → Firm trading job escrow with deterministic settlement |
| Custom | `TradingVault` | Per-job escrow + DEX router for trade execution |
| Custom | `AlloraConsumer` | EIP-712 signed Allora prediction receiver (first deploy on Mantle) |

## Deployed on Mantle Sepolia (chain 5003)

All contracts deployed + verified on Mantlescan, 2026-05-28. Deployer: `0x48379F4d1427209311E9FF0bcC4a354953ea631B`.

| Contract | Address | Mantlescan |
|---|---|---|
| IdentityRegistry | `0x0fAE6342195fdc0007B94Fb3293bF56463C55ff3` | [verify](https://sepolia.mantlescan.xyz/address/0x0fAE6342195fdc0007B94Fb3293bF56463C55ff3) |
| ReputationRegistry | `0x5A18F8D33D551666233701025754274dCA9B2929` | [verify](https://sepolia.mantlescan.xyz/address/0x5A18F8D33D551666233701025754274dCA9B2929) |
| ValidationRegistry | `0x8e55E41dc9a93E30aaf580DBA0B3Ee6B34e14a1B` | [verify](https://sepolia.mantlescan.xyz/address/0x8e55E41dc9a93E30aaf580DBA0B3Ee6B34e14a1B) |
| AlloraConsumer | `0x7A072465AC232709C114C5DAa842a9b7010D1d4f` | [verify](https://sepolia.mantlescan.xyz/address/0x7A072465AC232709C114C5DAa842a9b7010D1d4f) |
| TradingVault | `0x3BbD1f5e8733e901A8FdFf5cFA7E18e575896424` | [verify](https://sepolia.mantlescan.xyz/address/0x3BbD1f5e8733e901A8FdFf5cFA7E18e575896424) |
| JobManager | `0x10421Eb1A230F484eEdB64642505d073e791823c` | [verify](https://sepolia.mantlescan.xyz/address/0x10421Eb1A230F484eEdB64642505d073e791823c) |

**First Allora-on-Mantle submission**: [tx 0x0d7c09…c469](https://sepolia.mantlescan.xyz/tx/0x0d7c09c945f74595a484b16f185db5c78d175eb286596a881bc78868a6c745b1)

## Quickstart

```bash
forge install                              # OpenZeppelin v5, Solady, forge-std
forge test -vv                             # 23/23 should pass

# Deploy (requires DEPLOYER_PRIVATE_KEY + MANTLESCAN_API_KEY in env)
forge script script/Deploy.s.sol \
  --rpc-url mantle_sepolia \
  --broadcast --verify
```

## Tests

- 23/23 passing as of submission
- `test/erc8004/` — Identity, Reputation, Validation registries
- `test/AlloraConsumer.t.sol` — EIP-712 signature verification, replay protection
- `test/JobAndVault.t.sol` — End-to-end Job lifecycle with mock USDC, mock DEX router

## Stack

- Foundry (forge 1.5)
- Solidity 0.8.27
- OpenZeppelin v5 (Ownable, ERC721, EIP712, ECDSA)
- Solady (gas-efficient utilities)
- via_ir off, optimizer 200 runs

## License

MIT
