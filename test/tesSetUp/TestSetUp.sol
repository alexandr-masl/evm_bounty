// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Manager} from "../../src/Manager.sol";
import {StrategyFactory} from "../../lib/strategy/StrategyFactory.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TestSetUp is Test {
    address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address bountyManager = address(0x456);
    address unAuthorized = address(0x455);
    address bountyDonor = address(0x458);
    address bountyDonor2 = address(0x454);
    Manager public manager;
    StrategyFactory public strategyFactory;
    BountyStrategy public bountyStrategy;
    bytes32 profileId;
    MockERC20 bountyToken;

    function setUp() public virtual {
        bountyToken = new MockERC20("Bounty Token", "BNTY", 18);

        vm.startPrank(deployer);

        manager = new Manager();
        strategyFactory = new StrategyFactory();
        bountyStrategy = new BountyStrategy();

        manager.initialize(address(bountyStrategy), address(strategyFactory));
        console.log("TEST Manager deployed and initialized at:", address(manager));

        vm.stopPrank();

        bountyToken.mint(address(bountyManager), 2000e18);

        vm.startPrank(bountyManager);

        uint256 needs = 1e18;
        string memory name = "Test Project";
        string memory metadata = "Test Metadata";

        profileId = manager.registerProject(address(bountyToken), needs, name, metadata);

        vm.stopPrank();
    }
}
