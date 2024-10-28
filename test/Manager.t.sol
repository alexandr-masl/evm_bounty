// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Manager} from "../src/Manager.sol";
import {StrategyFactory} from "../lib/strategy/StrategyFactory.sol";
import {BountyStrategy} from "../src/BountyStrategy.sol";

contract CounterTest is Test {
    address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    Manager public manager;
    StrategyFactory public strategyFactory;
    BountyStrategy public bountyStrategy;

    function setUp() public {
        vm.startPrank(deployer);

        manager = new Manager();
        strategyFactory = new StrategyFactory();
        bountyStrategy = new BountyStrategy();

        manager.initialize(address(bountyStrategy), address(strategyFactory));
        console.log("TEST Manager deployed and initialized at:", address(manager));

        vm.stopPrank();
    }

    function test_ManagerInitialized() public view {
        address strategy = manager.strategy();
        console.log("Manager Strategy:", strategy);
    }
}
