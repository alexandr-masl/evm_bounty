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

        strategyContract.reviewRecipient(bountyHunter, BountyStrategy.Status.Accepted);

        vm.stopPrank();
    }
}
