// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Manager} from "../../src/Manager.sol";
import {StrategyFactory} from "../../lib/strategy/StrategyFactory.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ManagerTest is Test {
    address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address bountyAdmin = address(0x456);
    address bountyManager = address(0x457);
    address bountyDonor = address(0x458);
    address unAuthorized = address(0x455);
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
        bountyToken.mint(address(bountyManager), 2000e18);
    }

    // function test_ManagerInitialized() public view {
    //     address strategy = manager.strategy();
    //     console.log("Manager Strategy:", strategy);
    // }

    // function test_registerProject() public {
    //     vm.startPrank(bountyAdmin);

    //     uint256 needs = 1e18;
    //     string memory name = "Test Project";
    //     string memory metadata = "Test Metadata";

    //     bytes32 profileId = manager.registerProject(address(bountyToken), needs, name, metadata);

    //     (address token,,,, uint256 need,,,, string memory retMetadata, string memory retName) =
    //         manager.getBountyInfo(profileId);

    //     // Assertions to verify the token and other fields.
    //     assertEq(token, address(bountyToken), "Token address does not match the expected bounty token address");
    //     assertEq(need, needs, "Need amount does not match the expected value");
    //     assertEq(retMetadata, metadata, "Metadata does not match the expected metadata");
    //     assertEq(retName, name, "Project name does not match the expected name");

    //     vm.stopPrank();
    // }

    // function test_supplyProject() public {
    //     vm.startPrank(bountyAdmin);

    //     uint256 needs = 1e18;
    //     string memory name = "Test Project";
    //     string memory metadata = "Test Metadata";

    //     bytes32 profileId = manager.registerProject(address(bountyToken), needs, name, metadata);

    //     bountyToken.approve(address(manager), 100e18);

    //     vm.expectEmit(true, true, false, true);
    //     emit Manager.ProjectFunded(profileId, 1e18);

    //     manager.supplyProject(profileId, 1e18, bountyAdmin);

    //     vm.stopPrank();
    // }

    // function test_supplyProjectByTwoDonors() public {
    //     vm.startPrank(bountyAdmin);

    //     uint256 needs = 0.5e18;
    //     string memory name = "Test Project";
    //     string memory metadata = "Test Metadata";

    //     bytes32 profileId = manager.registerProject(address(bountyToken), needs, name, metadata);

    //     bountyToken.approve(address(manager), 1e18);

    //     vm.expectEmit(true, true, false, true);
    //     emit Manager.ProjectFunded(profileId, 0.15e18);

    //     manager.supplyProject(profileId, 0.15e18, bountyAdmin);

    //     vm.stopPrank();

    //     vm.startPrank(bountyManager);

    //     bountyToken.approve(address(manager), 1e18);
    //     manager.supplyProject(profileId, 0.35e18, bountyManager);

    //     vm.stopPrank();
    // }

    function test_supplyProjectAndRevokeSupply() public {
        vm.startPrank(bountyAdmin);

        uint256 needs = 0.5e18;
        string memory name = "Test Project";
        string memory metadata = "Test Metadata";

        bytes32 profileId = manager.registerProject(address(bountyToken), needs, name, metadata);

        bountyToken.approve(address(manager), 1e18);

        vm.expectEmit(true, true, false, true);
        emit Manager.ProjectFunded(profileId, 0.15e18);

        manager.supplyProject(profileId, 0.15e18, bountyAdmin);

        vm.stopPrank();

        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 1e18);
        manager.supplyProject(profileId, 0.25e18, bountyManager);

        uint256 bountyDonorInitialBalance = bountyToken.balanceOf(bountyDonor);

        console.log(
            "::::::::: test_supplyProjectAndRevokeSupply | bountyDonorInitialBalance:", bountyDonorInitialBalance
        );

        manager.revokeProjectSupply(profileId, bountyManager);

        vm.stopPrank();

        // vm.prank(bountyDonor);
        // manager.revokeProjectSupply(profileId, bountyDonor);

        uint256 bountyDonorUpdatedBalance = bountyToken.balanceOf(bountyDonor);
        console.log(
            "::::::::: test_supplyProjectAndRevokeSupply | bountyDonorUpdatedBalance:", bountyDonorUpdatedBalance
        );
    }
}
