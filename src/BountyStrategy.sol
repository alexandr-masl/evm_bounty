// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract BountyStrategy is ReentrancyGuard, AccessControl {
    bytes32 public constant SUPPLIER_ROLE = keccak256("SUPPLIER_ROLE");

    /// @notice Struct to hold details of an recipient
    enum StrategyState {
        None,
        Active,
        Executed,
        Rejected
    }

    enum Status {
        None,
        Pending,
        Accepted,
        Rejected,
        Appealed,
        InReview,
        Canceled
    }

    /// @notice Struct to represent the power of a supplier.
    struct SupplierPower {
        address supplierId; // Address of the supplier.
        uint256 supplierPower; // Power value associated with the supplier.
    }

    struct Storage {
        StrategyState state;
        uint256 registeredRecipients;
        uint32 maxRecipientsAmount;
        uint256 totalSupply;
        uint256 currentSupply;
        uint256 thresholdPercentage;
    }

    struct OfferedMilestones {
        Milestone[] milestones;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => uint256) suppliersVotes;
    }

    struct Milestone {
        uint256 amountPercentage;
        string metadata;
        Status milestoneStatus;
        string description;
    }

    event Initialized();
    event MilestonesOffered(uint256 milestonesLength);

    Storage public strategyStorage;
    address[] private _suppliersStore;
    OfferedMilestones public offeredMilestones;
    Milestone[] public milestones;
    mapping(address => uint256) private _supplierPower;

    function initialize(SupplierPower[] memory _projectSuppliers, uint32 _maxRecipients) external virtual {
        require(strategyStorage.thresholdPercentage == 0, "ALREADY_INITIALIZED");
        _BountyStrategy_init(_projectSuppliers, _maxRecipients);
        emit Initialized();
    }

    function _BountyStrategy_init(SupplierPower[] memory _projectSuppliers, uint32 _maxRecipients) internal {
        strategyStorage.thresholdPercentage = 77;
        strategyStorage.maxRecipientsAmount = _maxRecipients;

        SupplierPower[] memory supliersPower = _projectSuppliers;

        uint256 totalInvestment = 0;
        for (uint256 i = 0; i < supliersPower.length; i++) {
            totalInvestment += supliersPower[i].supplierPower;
        }

        for (uint256 i = 0; i < supliersPower.length; i++) {
            _suppliersStore.push(supliersPower[i].supplierId);

            // Normalize supplier power to a percentage
            _supplierPower[supliersPower[i].supplierId] = (supliersPower[i].supplierPower * 1e18) / totalInvestment;
            strategyStorage.totalSupply += _supplierPower[supliersPower[i].supplierId];

            _grantRole(SUPPLIER_ROLE, supliersPower[i].supplierId);
        }

        strategyStorage.currentSupply = strategyStorage.totalSupply;
        strategyStorage.state = StrategyState.Active;
    }

    function offerMilestones(Milestone[] memory _milestones) external onlyRole(SUPPLIER_ROLE) {
        require(milestones.length == 0, "MILESTONES_ALREADY_SET");

        // _resetOfferedMilestones();

        for (uint256 i = 0; i < _milestones.length; i++) {
            offeredMilestones.milestones.push(_milestones[i]);
        }

        uint256 managerVotingPower = _supplierPower[msg.sender];

        offeredMilestones.suppliersVotes[msg.sender] = managerVotingPower;

        // _reviewOfferedtMilestones(Status.Accepted, managerVotingPower);

        emit MilestonesOffered(_milestones.length);
    }
}
