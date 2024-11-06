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
    bytes32 public constant HUNTER_ROLE = keccak256("HUNTER_ROLE");

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
        address hunter;
    }

    struct OfferedMilestones {
        Milestone[] milestones;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => uint256) managersVotes;
    }

    struct SubmiteddMilestone {
        uint256 votesFor; // Total number of votes in favor of the submitted milestone.
        uint256 votesAgainst; // Total number of votes against the submitted milestone.
        mapping(address => uint256) managersVotes; // Mapping of supplier addresses to their vote counts.
    }

    struct Milestone {
        uint256 amountPercentage;
        string metadata;
        Status milestoneStatus;
        string description;
    }

    struct OfferedRecipient {
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => uint256) managersVotes;
    }

    error UNAUTHORIZED();

    event Initialized();
    event OfferedMilestonesDropped();
    event ProjectRejected();
    event MilestoneSubmitted(uint256 milestoneId, string _metadata);
    event Distributed(uint256 milestoneId, address hunter, uint256 amountToDistributed);
    event MilestoneStatusChanged(uint256 milestoneId, Status status);
    event SubmittedMilestoneReviewed(uint256 milestoneId, Status status);

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
    mapping(address => OfferedRecipient) public offeredRecipient;
    mapping(uint256 => SubmiteddMilestone) public submittedvMilestones;

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

    function getBountyStrategyInfo()
        external
        view
        returns (
            StrategyState _state,
            uint32 _maxRecipientsAmount,
            uint256 _totalSupply,
            uint256 _thresholdPercentage,
            address _hunter
        )
    {
        return (
            strategyStorage.state,
            strategyStorage.maxRecipientsAmount,
            strategyStorage.totalSupply,
            strategyStorage.thresholdPercentage,
            strategyStorage.hunter
        );
    }

    function offerMilestones(Milestone[] memory _milestones) external onlyRole(MANAGER_ROLE) onlyActive {
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
    function reviewOfferedtMilestones(Status _status) public onlyRole(MANAGER_ROLE) onlyActive {
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

    function rejectStrategy() external onlyRole(DONOR_ROLE) onlyActive {
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

    function reviewRecipient(address _recipient, Status _status) external onlyRole(MANAGER_ROLE) onlyActive {
        if (_status == Status.Accepted) {
            require(strategyStorage.hunter == address(0), "MAX_RECIPIENTS_AMOUNT_REACHED");
        } else {
            require(strategyStorage.hunter != address(0), "INVALID_HUNTER");
        }

        require(offeredRecipient[_recipient].managersVotes[msg.sender] == 0, "ALREADY_REVIEWED");

        require(_status == Status.Accepted || _status == Status.Rejected, "INVALID STATUS");

        uint256 managerVotingPower = manager.getManagerVotingPower(bountyId, msg.sender);
        offeredRecipient[_recipient].managersVotes[msg.sender] = managerVotingPower;

        if (_status == Status.Accepted) {
            offeredRecipient[_recipient].votesFor += managerVotingPower;

            if (_checkIfVotesExceedThreshold(offeredRecipient[_recipient].votesFor)) {
                strategyStorage.hunter = _recipient;
                _dropRecipientsVotes(_recipient);

                _grantRole(HUNTER_ROLE, _recipient);
            }
        } else {
            offeredRecipient[_recipient].votesAgainst += managerVotingPower;

            if (_checkIfVotesExceedThreshold(offeredRecipient[_recipient].votesAgainst)) {
                strategyStorage.hunter = address(0);
                _dropRecipientsVotes(_recipient);

                _revokeRole(HUNTER_ROLE, _recipient);
            }
        }
    }

    function submitMilestone(uint256 _milestoneId, string calldata _metadata) external {
        require(_milestoneId < milestones.length, "INVALID_MILESTONE");

        Milestone storage milestone = milestones[_milestoneId];

        require(milestone.milestoneStatus != Status.Accepted, "MILESTONE_ALREADY_ACCEPTED");

        if (hasRole(HUNTER_ROLE, msg.sender)) {
            _submitMilestone(_milestoneId, milestone, _metadata);
        } else if (hasRole(MANAGER_ROLE, msg.sender)) {
            _submitMilestone(_milestoneId, milestone, _metadata);

            reviewSubmitedMilestone(_milestoneId, Status.Accepted);
        } else {
            revert UNAUTHORIZED();
        }
    }

    function reviewSubmitedMilestone(uint256 _milestoneId, Status _status) public onlyRole(MANAGER_ROLE) {
        require(submittedvMilestones[_milestoneId].managersVotes[msg.sender] == 0, "ALREADY_REVIEWED");

        require(_milestoneId < milestones.length, "INVALID_MILESTONE");

        Milestone storage milestone = milestones[_milestoneId];

        require(milestone.milestoneStatus == Status.Pending, "INVALID_MILESTONE_STATUS");

        require(_status == Status.Accepted || _status == Status.Rejected, "INVALID STATUS");

        uint256 managerVotingPower = manager.getManagerVotingPower(bountyId, msg.sender);
        submittedvMilestones[_milestoneId].managersVotes[msg.sender] = managerVotingPower;

        if (_status == Status.Accepted) {
            submittedvMilestones[_milestoneId].votesFor += managerVotingPower;

            if (_checkIfVotesExceedThreshold(submittedvMilestones[_milestoneId].votesFor)) {
                milestone.milestoneStatus = _status;
                emit MilestoneStatusChanged(_milestoneId, _status);

                _distributeMilestone(_milestoneId);
            }
        } else {
            submittedvMilestones[_milestoneId].votesAgainst += managerVotingPower;

            if (_checkIfVotesExceedThreshold(submittedvMilestones[_milestoneId].votesAgainst)) {
                milestone.milestoneStatus = _status;
                for (uint256 i = 0; i < bounty.managers.length; i++) {
                    submittedvMilestones[_milestoneId].managersVotes[bounty.managers[i]] = 0;
                }
                delete submittedvMilestones[_milestoneId];
                emit MilestoneStatusChanged(_milestoneId, _status);
            }
        }

        emit SubmittedMilestoneReviewed(_milestoneId, _status);
    }

    function _distributeMilestone(uint256 _milestoneId) private {
        Milestone storage milestone = milestones[_milestoneId];

        require(milestone.milestoneStatus == Status.Accepted, "INVALID_MILESTONE_STATUS");

        // Calculate the amount to be distributed for the milestone
        uint256 amountToDistribute = strategyStorage.totalSupply * milestone.amountPercentage / 1e18;

        SafeTransferLib.safeTransfer(bounty.token, strategyStorage.hunter, amountToDistribute);

        if ((_milestoneId + 1) >= milestones.length) {
            strategyStorage.state = StrategyState.Executed;
        }

        // Emit events for the distribution
        emit Distributed(_milestoneId, strategyStorage.hunter, amountToDistribute);
    }

    function _submitMilestone(uint256 _milestoneId, Milestone storage milestone, string calldata _metadata) internal {
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            submittedvMilestones[_milestoneId].managersVotes[bounty.managers[i]] = 0;
        }
        delete submittedvMilestones[_milestoneId];

        // Update the milestone metadata and status
        milestone.metadata = _metadata;
        milestone.milestoneStatus = Status.Pending;

        // Emit an event to indicate successful milestone submission
        emit MilestoneSubmitted(_milestoneId, _metadata);
    }

    function _dropRecipientsVotes(address _recipient) internal {
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            offeredRecipient[_recipient].managersVotes[bounty.managers[i]] = 0;
        }
        delete offeredRecipient[_recipient];
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
