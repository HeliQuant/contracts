// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20 — Testnet faucet token for HeliQuant demo flows
/// @notice Minimal mintable ERC20 with configurable decimals and a PUBLIC mint faucet.
///         Lives in `src/` (not `test/`) so it can be deployed to Mantle Sepolia and
///         let any demo user self-fund (`mint`) before "hiring the firm" via the
///         JobManager. NOT for mainnet — the open mint makes supply unbounded.
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    )
        ERC20(name_, symbol_)
    {
        _decimals = decimals_;
    }

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Open faucet — anyone can mint to any address (testnet only).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
