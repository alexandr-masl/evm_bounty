// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";
import {TestSetUp} from "../tesSetUp/TestSetUp.sol";

contract OfferMilestones is TestSetUp {

    function setUp() public override {
        super.setUp();
    }

    function test_offerMilestonesByAdmin() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyManager);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        BountyStrategy.Milestone[] memory milestones = getMilestones();

        strategyContract.offerMilestones(milestones);

        vm.stopPrank();
    }

    // function test_UnauthorizedOfferMilestonesByAdmin() public {
    //     vm.startPrank(bountyAdmin);

    //     bountyToken.approve(address(manager), 100e18);
    //     manager.supplyProject(profileId, 1e18, bountyAdmin);

    //     address projectStrategy = manager.getBountyStrategy(profileId);
    //     BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

    //     BountyStrategy.Milestone[] memory milestones = getMilestones();

    //     vm.stopPrank();

    //     bytes memory expectedError = abi.encodeWithSignature(
    //         "AccessControlUnauthorizedAccount(address,bytes32)",
    //         unAuthorized,
    //         strategyContract.SUPPLIER_ROLE() // Assumes `SUPPLIER_ROLE` is accessible
    //     );
    //     vm.expectRevert(expectedError);

    //     vm.prank(unAuthorized);
    //     strategyContract.offerMilestones(milestones);
    // }

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
