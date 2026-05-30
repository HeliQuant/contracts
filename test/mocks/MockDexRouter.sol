// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Trivial DEX router for tests. Price is a per-pair ratio (1e18 scale)
///         representing "how much tokenOut do I get per 1 tokenIn".
contract MockDexRouter {
    mapping(address => mapping(address => uint256)) public priceX18;

    function setPrice(address tokenIn, address tokenOut, uint256 price) external {
        priceX18[tokenIn][tokenOut] = price;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
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
