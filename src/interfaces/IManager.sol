// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../Manager.sol";

interface IManager {
    function getBounty(bytes32 _bountyId) external view returns (Manager.BountyInformation memory);
    function getManagerVotingPower(bytes32 _bountyId, address _manager) external view returns (uint256);
    function getDonorContribution(bytes32 _bountyId, address _donor) external view returns (uint256);
}
