// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestSetUp} from "../tesSetUp/TestSetUp.sol";
import {BountyStrategy} from "../../src/BountyStrategy.sol";

contract OfferMilestones is TestSetUp {
    BountyStrategy.Milestone milestones;

    function setUp() public override {
        super.setUp();
    }

    function test_UnAuthorizedRejectStrategyByManager() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyDonor);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        bytes memory expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            bountyManager,
            strategyContract.DONOR_ROLE() // Assumes `SUPPLIER_ROLE` is accessible
        );

        vm.expectRevert(expectedError);
        strategyContract.rejectStrategy();

        vm.stopPrank();
    }

    function test_RejectStrategyByManager() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyManager);

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        strategyContract.rejectStrategy();

        vm.stopPrank();
    }

    function test_RejectStrategyByDonor() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);
        manager.supplyProject(profileId, 1e18, bountyDonor);

        vm.stopPrank();

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        vm.prank(bountyDonor);
        strategyContract.rejectStrategy();
    }

    function test_RejectStrategyByMajorityVotes() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);

        manager.supplyProject(profileId, 0.85e18, bountyDonor);

        manager.supplyProject(profileId, 0.15e18, bountyDonor2);

        vm.stopPrank();

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        vm.prank(bountyDonor);
        strategyContract.rejectStrategy();

        vm.expectRevert(bytes("ACTIVE_STATE_REQUIERED"));
        vm.prank(bountyManager);
        strategyContract.reviewOfferedtMilestones(BountyStrategy.Status.Accepted);
    }

    function test_RejectStrategyByMinorityVotes() public {
        vm.startPrank(bountyManager);

        bountyToken.approve(address(manager), 100e18);

        manager.supplyProject(profileId, 0.85e18, bountyDonor);

        manager.supplyProject(profileId, 0.15e18, bountyDonor2);

        vm.stopPrank();

        address projectStrategy = manager.getBountyStrategy(profileId);
        BountyStrategy strategyContract = BountyStrategy(payable(projectStrategy));

        vm.prank(bountyDonor2);
        strategyContract.rejectStrategy();

        // vm.expectRevert(bytes("ACTIVE_STATE_REQUIERED"));
        // vm.prank(bountyManager);
        // strategyContract.reviewOfferedtMilestones(BountyStrategy.Status.Accepted);
    }
}
