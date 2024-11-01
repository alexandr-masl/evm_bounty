// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IManager} from "./interfaces/IManager.sol";
import {Manager} from "./Manager.sol";

contract BountyStrategy is ReentrancyGuard, AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant DONOR_ROLE = keccak256("DONOR_ROLE");

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

    struct RejectStrategyVotes {
        uint256 votes;
        mapping(address => uint256) donorVotes; // Mapping of supplier addresses to their vote counts.
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
        uint256 thresholdPercentage;
    }

    struct OfferedMilestones {
        Milestone[] milestones;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => uint256) managersVotes;
    }

    struct Milestone {
        uint256 amountPercentage;
        string metadata;
        Status milestoneStatus;
        string description;
    }

    event Initialized();
    event OfferedMilestonesDropped();
    event ProjectRejected();

    /// @notice Emitted when offered milestones are accepted for a recipient.
    event OfferedMilestonesAccepted();

    /// @notice Emitted when offered milestones are rejected for a recipient.
    event OfferedMilestonesRejected();

    /// @notice Emitted when milestones for a recipient are reviewed.
    event MilestonesReviewed(Status status);

    /// @notice Emitted when milestones are offered to a recipient.
    event MilestonesOffered(uint256 milestonesLength);

    /// @notice Emitted when milestones are set for a recipient.
    event MilestonesSet(uint256 milestonesLength);

    Manager.BountyInformation bounty;
    bytes32 bountyId;
    Storage public strategyStorage;
    OfferedMilestones public offeredMilestones;
    Milestone[] public milestones;
    RejectStrategyVotes public rejectStrategyVotes;
    IManager private manager;

    mapping(address => uint256) private _managerVotingPower;
    mapping(address => uint256) private _donorContributionFraction;

    function initialize(address _manager, bytes32 _bountyId) external virtual {
        require(strategyStorage.thresholdPercentage == 0, "ALREADY_INITIALIZED");
        _BountyStrategy_init(_manager, _bountyId);
        emit Initialized();
    }

    modifier onlyActive() {
        require(strategyStorage.state == StrategyState.Active, "ACTIVE_STATE_REQUIERED");
        _;
    }

    function _BountyStrategy_init(address _manager, bytes32 _bountyId) internal {
        strategyStorage.thresholdPercentage = 77;
        strategyStorage.maxRecipientsAmount = 1;
        manager = IManager(_manager);

        bounty = manager.getBounty(_bountyId);
        bountyId = _bountyId;

        for (uint256 i = 0; i < bounty.managers.length; i++) {
            strategyStorage.totalSupply += manager.getManagerVotingPower(_bountyId, bounty.managers[i]);
        }

        for (uint256 i = 0; i < bounty.managers.length; i++) {
            uint256 votingPower = manager.getManagerVotingPower(_bountyId, bounty.managers[i]);
            _managerVotingPower[bounty.managers[i]] = (votingPower * 1e18) / strategyStorage.totalSupply;

            _grantRole(MANAGER_ROLE, bounty.managers[i]);
        }

        for (uint256 i = 0; i < bounty.donors.length; i++) {
            uint256 donorContribution = manager.getDonorContribution(_bountyId, bounty.donors[i]);
            _donorContributionFraction[bounty.donors[i]] = (donorContribution * 1e18) / strategyStorage.totalSupply;

            _grantRole(DONOR_ROLE, bounty.donors[i]);
        }

        strategyStorage.state = StrategyState.Active;
    }

    function offerMilestones(Milestone[] memory _milestones) external onlyRole(MANAGER_ROLE) onlyActive() {
        for (uint256 i = 0; i < _milestones.length; i++) {
            offeredMilestones.milestones.push(_milestones[i]);
        }

        emit MilestonesOffered(_milestones.length);

        reviewOfferedtMilestones(Status.Accepted);
    }

    /// @notice Reviews the offered milestones for a specific recipient and sets their status.
    /// @param _status The new status to be set for the offered milestones.
    /// @dev Requires the sender to be the pool manager and wearing the supplier hat.
    /// Emits a MilestonesReviewed event and, depending on the outcome, either OfferedMilestonesAccepted or OfferedMilestonesRejected.
    function reviewOfferedtMilestones(Status _status) public onlyRole(MANAGER_ROLE) onlyActive() {
        require(offeredMilestones.managersVotes[msg.sender] == 0, "ALREADY_REVIEWED");
        require(milestones.length == 0, "MILESTONES_ALREADY_SET");

        uint256 managerVotingPower = manager.getManagerVotingPower(bountyId, msg.sender);
        offeredMilestones.managersVotes[msg.sender] = managerVotingPower;

        if (_status == Status.Accepted) {
            offeredMilestones.votesFor += managerVotingPower;

            if (_checkIfVotesExceedThreshold(offeredMilestones.votesFor)) {
                _setMilestones(offeredMilestones.milestones);
                emit OfferedMilestonesAccepted();
            }
        } else if (_status == Status.Rejected) {
            offeredMilestones.votesAgainst += managerVotingPower;

            if (_checkIfVotesExceedThreshold(offeredMilestones.votesAgainst)) {
                _resetOfferedMilestones();
                emit OfferedMilestonesRejected();
            }
        }

        emit MilestonesReviewed(_status);
    }

    function rejectStrategy() external onlyRole(DONOR_ROLE) onlyActive() {
        require(rejectStrategyVotes.donorVotes[msg.sender] == 0, "ALREADY_REVIEWED");

        uint256 donorContributionFraction = _donorContributionFraction[msg.sender];
        rejectStrategyVotes.donorVotes[msg.sender] = donorContributionFraction;
        rejectStrategyVotes.votes += donorContributionFraction;

        if (_checkIfVotesExceedThreshold(rejectStrategyVotes.votes)) {
            _distributeFundsBackToDonors();

            strategyStorage.state = StrategyState.Rejected;
            emit ProjectRejected();
        }
    }

    function _setMilestones(Milestone[] memory _milestones) internal {
        uint256 totalAmountPercentage;

        // Clear out the milestones and reset the index to 0
        if (milestones.length > 0) {
            delete milestones;
        }

        uint256 milestonesLength = _milestones.length;

        // Loop through the milestones and set them
        for (uint256 i; i < milestonesLength;) {
            Milestone memory milestone = _milestones[i];

            // Reverts if the milestone status is 'None'
            require(milestone.milestoneStatus == Status.None, "INVALID_MILESTONE_STATUS");

            // Add the milestone percentage amount to the total percentage amount
            totalAmountPercentage += milestone.amountPercentage;

            // Add the milestone to the recipient's milestones
            milestones.push(milestone);

            unchecked {
                i++;
            }
        }

        require(totalAmountPercentage == 1e18, "INVALID_MILESTONES_PERCENTAGE");

        emit MilestonesSet(milestonesLength);
    }

    function _checkIfVotesExceedThreshold(uint256 _votes) internal view returns (bool) {
        uint256 thresholdValue = (strategyStorage.totalSupply * strategyStorage.thresholdPercentage) / 100;
        return _votes > thresholdValue;
    }

    function _resetOfferedMilestones() internal {
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            offeredMilestones.managersVotes[bounty.managers[i]] = 0;
        }
        delete offeredMilestones;

        emit OfferedMilestonesDropped();
    }

    function _distributeFundsBackToDonors() private {
        IERC20 token = IERC20(bounty.token);
        uint256 tokenBalance = token.balanceOf(address(this));

        for (uint256 i = 0; i < bounty.donors.length; i++) {
            uint256 fraction = _donorContributionFraction[bounty.donors[i]];
            uint256 amount = tokenBalance * fraction / 1e18;
            SafeTransferLib.safeTransfer(bounty.token, bounty.donors[i], amount);
        }
    }
}
