// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Manager} from "../src/Manager.sol";
import {StrategyFactory} from "../lib/strategy/StrategyFactory.sol";
import {BountyStrategy} from "../src/BountyStrategy.sol";

contract ManagerScript is Script {
    Manager public manager;
    StrategyFactory public strategyFactory;
    BountyStrategy public bountyStrategy;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        manager = new Manager();
        strategyFactory = new StrategyFactory();
        bountyStrategy = new BountyStrategy();

        manager.initialize(address(bountyStrategy), address(strategyFactory));
        console.log("Manager deployed and initialized at:", address(manager));

        vm.stopBroadcast();
    }
}
