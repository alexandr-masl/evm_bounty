// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../Manager.sol";

/**
 * @title IManager
 * @notice Interface for interacting with the `Manager` contract from the `BountyStrategy` contract.
 * @dev Provides methods to fetch bounty details, manager voting power, and donor contributions.
 */
interface IManager {
    /**
     * @notice Retrieves the details of a specific bounty project.
     * @param _bountyId The unique identifier of the bounty project.
     * @return A `BountyInformation` struct containing details about the bounty.
     */
    function getBounty(bytes32 _bountyId) external view returns (Manager.BountyInformation memory);

    /**
     * @notice Retrieves the voting power of a specific manager for a given bounty.
     * @param _bountyId The unique identifier of the bounty project.
     * @param _manager The address of the manager whose voting power is being queried.
     * @return The voting power of the specified manager for the given bounty.
     */
    function getManagerVotingPower(bytes32 _bountyId, address _manager) external view returns (uint256);

    /**
     * @notice Retrieves the contribution amount of a specific donor for a given bounty.
     * @param _bountyId The unique identifier of the bounty project.
     * @param _donor The address of the donor whose contribution is being queried.
     * @return The contribution amount of the specified donor for the given bounty.
     */
    function getDonorContribution(bytes32 _bountyId, address _donor) external view returns (uint256);
}
