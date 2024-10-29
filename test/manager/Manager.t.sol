// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Manager} from "../../src/Manager.sol";
import {StrategyFactory} from "../../lib/strategy/StrategyFactory.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ManagerTest is Test {
    address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address bountyAdmin = address(0x456);
    Manager public manager;
    StrategyFactory public strategyFactory;
    BountyStrategy public bountyStrategy;

    MockERC20 bountyToken;

    function setUp() public {
        bountyToken = new MockERC20("Bounty Token", "BNTY", 18);

        vm.startPrank(deployer);

        manager = new Manager();
        strategyFactory = new StrategyFactory();
        bountyStrategy = new BountyStrategy();

        manager.initialize(address(bountyStrategy), address(strategyFactory));
        console.log("TEST Manager deployed and initialized at:", address(manager));

        vm.stopPrank();

        bountyToken.mint(address(bountyAdmin), 2000e18);
    }

    function test_ManagerInitialized() public view {
        address strategy = manager.strategy();
        console.log("Manager Strategy:", strategy);
    }

    function test_registerProject() public {
        vm.startPrank(bountyAdmin);

        uint256 needs = 1000;
        string memory name = "Test Project";
        string memory metadata = "Test Metadata";

        bytes32 profileId = manager.registerProject(address(bountyToken), needs, name, metadata);
        address token = manager.getPoolToken(profileId);

        assertEq(token, address(bountyToken), "Token address does not match the expected bounty token address");

        vm.stopPrank();
    }
}
