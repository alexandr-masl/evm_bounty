// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {TestSetUp} from "../tesSetUp/TestSetUp.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";

contract OfferRecipient is TestSetUp {
    function setUp() public override {
        super.setUp();
    }

    function test_submitMilestone() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyManager);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        BountyStrategy.Milestone[] memory milestones = new BountyStrategy.Milestone[](1);

        // Initialize each element manually
        milestones[0] = BountyStrategy.Milestone({
            amountPercentage: 1 ether,
            metadata: "metadata",
            milestoneStatus: BountyStrategy.Status.None, // Assuming 0 corresponds to Pending status
            description: "I will do my best"
        });

        strategyContract.offerMilestones(milestones);
        strategyContract.reviewRecipient(bountyHunter, BountyStrategy.Status.Accepted);

        uint256 hunterBalance = bountyToken.balanceOf(bountyHunter);
        console.log("::::::::: Hunter Balance:", hunterBalance);

        strategyContract.submitMilestone(0, "test_pointer");

        uint256 updatedHunterBalance = bountyToken.balanceOf(bountyHunter);
        console.log("::::::::: Updated Hunter Balance:", updatedHunterBalance);

        vm.stopPrank();
    }

    function test_SwitchHunterAndSubmitMilestone() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyManager);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        BountyStrategy.Milestone[] memory milestones = new BountyStrategy.Milestone[](1);

        // Initialize each element manually
        milestones[0] = BountyStrategy.Milestone({
            amountPercentage: 1 ether,
            metadata: "metadata",
            milestoneStatus: BountyStrategy.Status.None, // Assuming 0 corresponds to Pending status
            description: "I will do my best"
        });

        strategyContract.offerMilestones(milestones);
        strategyContract.reviewRecipient(bountyHunter, BountyStrategy.Status.Accepted);

        strategyContract.reviewRecipient(bountyHunter, BountyStrategy.Status.Rejected);

        strategyContract.reviewRecipient(bountyHunter2, BountyStrategy.Status.Accepted);

        uint256 hunterBalance = bountyToken.balanceOf(bountyHunter2);
        console.log("::::::::: Second Hunter Balance:", hunterBalance);

        strategyContract.submitMilestone(0, "test_pointer");

        uint256 updatedHunterBalance = bountyToken.balanceOf(bountyHunter2);
        console.log("::::::::: Second Hunter Updated Balance:", updatedHunterBalance);

        vm.stopPrank();
    }
}
