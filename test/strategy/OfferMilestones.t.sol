// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Manager} from "../../src/Manager.sol";
import {StrategyFactory} from "../../lib/strategy/StrategyFactory.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract OfferMilestones is Test {
    address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address bountyAdmin = address(0x456);
    address unAuthorized = address(0x455);
    Manager public manager;
    StrategyFactory public strategyFactory;
    BountyStrategy public bountyStrategy;
    bytes32 profileId;
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

        vm.startPrank(bountyAdmin);

        uint256 needs = 1e18;
        string memory name = "Test Project";
        string memory metadata = "Test Metadata";

        profileId = manager.registerProject(address(bountyToken), needs, name, metadata);

        vm.stopPrank();
    }

    function test_offerMilestonesByAdmin() public {
        vm.startPrank(bountyAdmin);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyAdmin);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        BountyStrategy.Milestone[] memory milestones = getMilestones();

        strategyContract.offerMilestones(milestones);

        vm.stopPrank();
    }

    function test_UnauthorizedOfferMilestonesByAdmin() public {
        vm.startPrank(bountyAdmin);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyAdmin);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        BountyStrategy.Milestone[] memory milestones = getMilestones();

        vm.stopPrank();

        bytes memory expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unAuthorized,
            strategyContract.SUPPLIER_ROLE() // Assumes `SUPPLIER_ROLE` is accessible
        );
        vm.expectRevert(expectedError);

        vm.prank(unAuthorized);
        strategyContract.offerMilestones(milestones);
    }

    function getMilestones() public pure returns (BountyStrategy.Milestone[] memory milestones) {
        milestones = new BountyStrategy.Milestone[](2);

        // Initialize each element manually
        milestones[0] = BountyStrategy.Milestone({
            amountPercentage: 0.5 ether,
            metadata: "metadata",
            milestoneStatus: BountyStrategy.Status.None, // Assuming 0 corresponds to Pending status
            description: "I will do my best"
        });

        milestones[1] = BountyStrategy.Milestone({
            amountPercentage: 0.5 ether,
            metadata: "metadata",
            milestoneStatus: BountyStrategy.Status.None,
            description: "I will do my best"
        });
    }
}
