// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockDexRouter — Uniswap-V2-compatible swap surface for HeliQuant testnet
/// @notice Deployable (lives in `src/`) so the OPTIONAL B-full DEX path of the demo
///         can route real `vault.trade()` calls on Mantle Sepolia. Price is a fixed
///         per-pair ratio (1e18 scale): "how much tokenOut per 1 tokenIn", i.e.
///         amountOut = amountIn * priceX18[tokenIn][tokenOut] / 1e18.
///
///         This is intentionally NOT constant-product. The vault only depends on the
///         `swapExactTokensForTokens(...)` signature (see IDexRouter in ITradingVault),
///         so a fixed-ratio router is sufficient for the HOLD/settle MVP and a simple
///         trade demo. The router must be pre-funded with both tokens to pay out swaps
///         (use MockERC20.mint(router, ...)). NOT for mainnet.
contract MockDexRouter {
    /// @dev priceX18[tokenIn][tokenOut] = tokenOut units per 1 tokenIn, 1e18-scaled.
    mapping(address => mapping(address => uint256)) public priceX18;

    function setPrice(address tokenIn, address tokenOut, uint256 price) external {
        priceX18[tokenIn][tokenOut] = price;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    )
        external
        returns (uint256[] memory amounts)
    {
        require(path.length == 2, "path");
        address tokenIn = path[0];
        address tokenOut = path[1];
        uint256 price = priceX18[tokenIn][tokenOut];
        require(price > 0, "no price");

        uint256 amountOut = (amountIn * price) / 1e18;
        require(amountOut >= amountOutMin, "slippage");

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }
}
