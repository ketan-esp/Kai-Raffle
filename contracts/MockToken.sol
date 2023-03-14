// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(uint256 initalSupply) ERC20("MockToken", "MT") {
        _mint(msg.sender, initalSupply * 10**decimals()); //mint tokens
    }
}
