// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol"; // Adjust the import path based on your project structure;

contract MockERC20Script is Script {
    MockERC20 public mockToken;
    address public mintToAddress = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Replace with the address to mint to
    uint256 public mintAmount = 5 * 10 ** 18; // Adjust the amount and decimals if needed

    function setUp() public {
        // Optional setup logic, if needed
    }

    function run() public {
        vm.startBroadcast();

        // Deploy the MockERC20 token
        mockToken = new MockERC20("Mock Token", "MOCK", 18);
        console.log("MockERC20 deployed to:", address(mockToken));

        // Mint tokens to the specified address
        mockToken.mint(mintToAddress, mintAmount);
        console.log("Minted", mintAmount / (10 ** mockToken.decimals()), "MOCK to:", mintToAddress);

        vm.stopBroadcast();
    }
}
