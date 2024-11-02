// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestSetUp} from "../tesSetUp/TestSetUp.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";

contract OfferRecipient is TestSetUp {
    function setUp() public override {
        super.setUp();
    }

    function test_reviewRecipient() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyManager);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        BountyStrategy.Milestone[] memory milestones = new BountyStrategy.Milestone[](1);

        // Initialize each element manually
        milestones[0] = BountyStrategy.Milestone({
            amountPercentage: 0.5 ether,
            metadata: "metadata",
            milestoneStatus: BountyStrategy.Status.None, // Assuming 0 corresponds to Pending status
            description: "I will do my best"
        });

        strategyContract.offerMilestones(milestones);
        strategyContract.reviewRecipient(bountyHunter, BountyStrategy.Status.Accepted);

        // strategyContract.reviewSubmitedMilestone(bountyHunter, 1, BountyStrategy.Status.Accepted);

        vm.stopPrank();
    }
}
