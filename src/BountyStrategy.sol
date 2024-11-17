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
    /**
     * @notice Role identifier for managers who oversee and make decisions regarding the bounty project.
     * @dev Managers are responsible for offering milestones, voting on decisions, and approving recipients.
     */
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /**
     * @notice Role identifier for donors who contribute funds to the bounty project.
     * @dev Donors have voting rights on the rejection of the strategy and influence the project's progress.
     */
    bytes32 public constant DONOR_ROLE = keccak256("DONOR_ROLE");

    /**
     * @notice Role identifier for hunters who are eligible to receive funds upon completing milestones.
     * @dev A hunter is the recipient of the bounty funds once milestones are approved and completed.
     */
    bytes32 public constant HUNTER_ROLE = keccak256("HUNTER_ROLE");

    /**
     * @notice Represents the state of the bounty strategy in its lifecycle.
     * @dev The strategy transitions through these states as the project progresses.
     */
    enum StrategyState {
        None, // The strategy is not initialized or inactive.
        Active, // The strategy is active and milestones are being managed.
        Executed, // All milestones are completed and the strategy is finalized.
        Rejected // The strategy was rejected by donors or managers.

    }

    /**
     * @notice Represents the status of a milestone or recipient in the bounty strategy.
     * @dev This enum tracks the lifecycle or decision state of milestones or recipients.
     */
    enum Status {
        None, // No status has been assigned or the process has not started.
        Pending, // The milestone or decision is pending approval.
        Accepted, // The milestone or recipient has been approved.
        Rejected, // The milestone or recipient has been rejected.
        Appealed, // The decision is under appeal and awaiting resolution.
        InReview, // The milestone or decision is actively under review.
        Canceled // The milestone or process has been canceled.

    }

    /**
     * @notice Tracks votes for rejecting the strategy by donors.
     * @dev Each donor's vote is proportional to their contribution fraction.
     * @param votes Total votes for rejecting the strategy.
     * @param donorVotes Mapping of donor addresses to their respective votes.
     */
    struct RejectStrategyVotes {
        uint256 votes; // Total votes for rejecting the strategy.
        mapping(address => uint256) donorVotes; // Donor-specific vote counts.
    }

    /**
     * @notice Represents the voting power of a supplier (manager or donor).
     * @dev This struct is used to calculate and track each supplier's influence in the project.
     * @param supplierId The address of the supplier.
     * @param supplierPower The power value associated with the supplier.
     */
    struct SupplierPower {
        address supplierId; // Address of the supplier.
        uint256 supplierPower; // Power value associated with the supplier.
    }

    /**
     * @notice Holds the configuration and state of the strategy.
     * @dev This struct is used to store key parameters and the current state of the strategy.
     * @param state The current state of the strategy (e.g., Active, Executed).
     * @param registeredRecipients The number of recipients registered for the strategy.
     * @param maxRecipientsAmount The maximum number of recipients allowed for the strategy.
     * @param totalSupply The total voting power of all managers and donors.
     * @param thresholdPercentage The voting threshold percentage required for decisions.
     * @param hunter The address of the recipient (hunter) of the bounty funds.
     */
    struct Storage {
        StrategyState state; // The current state of the strategy.
        uint256 registeredRecipients; // The number of recipients registered.
        uint32 maxRecipientsAmount; // Maximum number of recipients allowed.
        uint256 totalSupply; // Total voting power of all managers and donors.
        uint256 thresholdPercentage; // Voting threshold percentage for decisions.
        address hunter; // The address of the selected recipient.
    }

    /**
     * @notice Tracks milestones offered by managers for approval.
     * @dev Includes vote counts and the milestones proposed by managers.
     * @param milestones The milestones proposed by managers.
     * @param votesFor Total votes in favor of the proposed milestones.
     * @param votesAgainst Total votes against the proposed milestones.
     * @param managersVotes Mapping of manager addresses to their individual vote counts.
     */
    struct OfferedMilestones {
        Milestone[] milestones; // List of offered milestones.
        uint256 votesFor; // Votes in favor of the milestones.
        uint256 votesAgainst; // Votes against the milestones.
        mapping(address => uint256) managersVotes; // Vote counts per manager.
    }

    /**
     * @notice Tracks a submitted milestone's review status and vote counts.
     * @dev Used to monitor votes for and against a submitted milestone.
     * @param votesFor Total number of votes in favor of the submitted milestone.
     * @param votesAgainst Total number of votes against the submitted milestone.
     * @param managersVotes Mapping of manager addresses to their individual vote counts.
     */
    struct SubmiteddMilestone {
        uint256 votesFor; // Votes in favor of the submitted milestone.
        uint256 votesAgainst; // Votes against the submitted milestone.
        mapping(address => uint256) managersVotes; // Vote counts per manager.
    }

    /**
     * @notice Represents a milestone within the bounty strategy.
     * @dev Contains details about the milestone's allocation, status, and description.
     * @param amountPercentage The percentage of total funds allocated to this milestone.
     * @param metadata Metadata providing additional information about the milestone.
     * @param milestoneStatus The current status of the milestone (e.g., Pending, Accepted).
     * @param description A textual description of the milestone.
     */
    struct Milestone {
        uint256 amountPercentage; // Percentage of total funds allocated.
        string metadata; // Metadata about the milestone.
        Status milestoneStatus; // The current status of the milestone.
        string description; // Description of the milestone.
    }

    /**
     * @notice Tracks votes for accepting or rejecting an offered recipient.
     * @dev Used to manage recipient approvals and associated vote counts.
     * @param votesFor Total votes in favor of accepting the recipient.
     * @param votesAgainst Total votes against the recipient.
     * @param managersVotes Mapping of manager addresses to their individual vote counts.
     */
    struct OfferedRecipient {
        uint256 votesFor; // Votes in favor of the recipient.
        uint256 votesAgainst; // Votes against the recipient.
        mapping(address => uint256) managersVotes; // Vote counts per manager.
    }

    /**
     * @notice Indicates that the caller is not authorized to perform the requested action.
     * @dev This error is used to enforce role-based or permission-based access control.
     * It is typically triggered when a function is called by an address that lacks the required role or privileges.
     */
    error UNAUTHORIZED();

    /**
     * @notice Emitted when the strategy contract is successfully initialized.
     */
    event Initialized();

    /**
     * @notice Emitted when all offered milestones are dropped or reset.
     * @dev This occurs when the proposed milestones are rejected by managers.
     */
    event OfferedMilestonesDropped();

    /**
     * @notice Emitted when the bounty project is rejected by donors.
     * @dev This happens when donor votes exceed the rejection threshold for the strategy.
     */
    event ProjectRejected();

    /**
     * @notice Emitted when a new milestone is submitted by a hunter or manager.
     * @param milestoneId The ID of the milestone being submitted.
     * @param _metadata Additional metadata related to the submitted milestone.
     */
    event MilestoneSubmitted(uint256 milestoneId, string _metadata);

    /**
     * @notice Emitted when funds are distributed for a specific milestone.
     * @param milestoneId The ID of the milestone for which funds are distributed.
     * @param hunter The address of the recipient (hunter) receiving the funds.
     * @param amountToDistributed The amount of funds distributed for the milestone.
     */
    event Distributed(uint256 milestoneId, address hunter, uint256 amountToDistributed);

    /**
     * @notice Emitted when the status of a milestone is changed.
     * @param milestoneId The ID of the milestone whose status has changed.
     * @param status The new status of the milestone (e.g., Accepted, Rejected).
     */
    event MilestoneStatusChanged(uint256 milestoneId, Status status);

    /**
     * @notice Emitted when a submitted milestone is reviewed by managers.
     * @param milestoneId The ID of the submitted milestone being reviewed.
     * @param status The outcome of the review (e.g., Accepted, Rejected).
     */
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

    /**
     * @notice Stores the information about the bounty project managed by this strategy.
     * @dev This is an instance of the `BountyInformation` struct from the `Manager` contract.
     */
    Manager.BountyInformation bounty;

    /**
     * @notice The unique identifier for the bounty project associated with this strategy.
     * @dev This ID is used to reference the project in the `Manager` contract.
     */
    bytes32 bountyId;

    /**
     * @notice Holds the configuration and state of the strategy.
     * @dev This is an instance of the `Storage` struct, tracking key parameters like voting thresholds and the strategy state.
     */
    Storage public strategyStorage;

    /**
     * @notice Tracks milestones proposed by managers and their voting progress.
     * @dev This is an instance of the `OfferedMilestones` struct, storing milestones awaiting approval or rejection.
     */
    OfferedMilestones public offeredMilestones;

    /**
     * @notice An array of milestones approved for the bounty project.
     * @dev This array contains instances of the `Milestone` struct representing each approved milestone.
     */
    Milestone[] public milestones;

    /**
     * @notice Tracks votes for rejecting the strategy by donors.
     * @dev This is an instance of the `RejectStrategyVotes` struct, used to calculate and store donor votes.
     */
    RejectStrategyVotes public rejectStrategyVotes;

    /**
     * @notice The reference to the `Manager` contract.
     * @dev Used to fetch project details, manage voting power, and validate roles.
     */
    IManager private manager;

    /**
     * @notice Tracks the voting power of each manager in the strategy.
     * @dev Maps a manager's address to their proportional voting power within the strategy.
     * This value is derived from the manager's contribution and the total supply.
     */
    mapping(address => uint256) private _managerVotingPower;

    /**
     * @notice Tracks the fraction of total contributions made by each donor.
     * @dev Maps a donor's address to their contribution fraction, expressed in 18-decimal precision.
     * This value is used for proportional voting and fund distribution.
     */
    mapping(address => uint256) private _donorContributionFraction;

    /**
     * @notice Tracks votes for accepting or rejecting offered recipients in the strategy.
     * @dev Maps a recipient's address to an `OfferedRecipient` struct, which stores vote counts and manager-specific votes.
     */
    mapping(address => OfferedRecipient) public offeredRecipient;

    /**
     * @notice Tracks the voting progress and review status of submitted milestones.
     * @dev Maps a milestone ID to a `SubmiteddMilestone` struct, which tracks votes and manager-specific contributions.
     */
    mapping(uint256 => SubmiteddMilestone) public submittedvMilestones;

    /**
     * @notice Initializes the BountyStrategy contract with the manager address and associated bounty ID.
     * @dev This function must be called only once. It sets the initial configuration and state of the strategy.
     * Emits an `Initialized` event upon successful execution.
     * @param _manager The address of the Manager contract that oversees the bounty project.
     * @param _bountyId The unique identifier of the bounty project associated with this strategy.
     *
     * Requirements:
     * - The strategy must not have been initialized previously (i.e., `thresholdPercentage` must be 0).
     * - This function must be called externally by an authorized entity.
     *
     * Emits:
     * - `Initialized` when the strategy is successfully initialized.
     */
    function initialize(address _manager, bytes32 _bountyId) external virtual {
        require(strategyStorage.thresholdPercentage == 0, "ALREADY_INITIALIZED");
        _BountyStrategy_init(_manager, _bountyId);
        emit Initialized();
    }

    /**
     * @notice Restricts access to functions that require the strategy to be in an active state.
     * @dev This modifier ensures the strategy's state is set to `StrategyState.Active` before allowing execution.
     *
     * Requirements:
     * - The strategy's state must be `StrategyState.Active`.
     *
     * Reverts:
     * - If the strategy's state is not `StrategyState.Active`, with the error message `"ACTIVE_STATE_REQUIERED"`.
     */
    modifier onlyActive() {
        require(strategyStorage.state == StrategyState.Active, "ACTIVE_STATE_REQUIERED");
        _;
    }

    /**
     * @notice Internal initialization function for the BountyStrategy contract.
     * @dev Sets up the initial state of the strategy, including voting power, roles, and strategy configuration.
     * This function is called by the `initialize` function and should not be called directly.
     * @param _manager The address of the Manager contract that oversees the bounty project.
     * @param _bountyId The unique identifier of the bounty project associated with this strategy.
     *
     * Steps:
     * 1. Sets the voting threshold percentage (`thresholdPercentage`) to 77%.
     * 2. Limits the strategy to a maximum of one recipient (`maxRecipientsAmount`).
     * 3. Fetches the bounty details from the Manager contract using `_bountyId`.
     * 4. Calculates the total voting power for all managers and assigns proportional voting power.
     * 5. Grants the `MANAGER_ROLE` to each manager based on their voting power.
     * 6. Calculates donor contribution fractions and grants the `DONOR_ROLE` to each donor.
     * 7. Marks the strategy as active by setting the state to `StrategyState.Active`.
     *
     * Requirements:
     * - This function should only be called internally during contract initialization.
     */
    function _BountyStrategy_init(address _manager, bytes32 _bountyId) internal {
        // Set initial strategy configuration
        strategyStorage.thresholdPercentage = 77;
        strategyStorage.maxRecipientsAmount = 1;
        manager = IManager(_manager);

        // Fetch bounty details from the Manager contract
        bounty = manager.getBounty(_bountyId);
        bountyId = _bountyId;

        // Calculate total voting power for managers
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            strategyStorage.totalSupply += manager.getManagerVotingPower(_bountyId, bounty.managers[i]);
        }

        // Assign voting power and roles to managers
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            uint256 votingPower = manager.getManagerVotingPower(_bountyId, bounty.managers[i]);
            _managerVotingPower[bounty.managers[i]] = (votingPower * 1e18) / strategyStorage.totalSupply;

            _grantRole(MANAGER_ROLE, bounty.managers[i]);
        }

        // Calculate contribution fractions and assign roles to donors
        for (uint256 i = 0; i < bounty.donors.length; i++) {
            uint256 donorContribution = manager.getDonorContribution(_bountyId, bounty.donors[i]);
            _donorContributionFraction[bounty.donors[i]] = (donorContribution * 1e18) / strategyStorage.totalSupply;

            _grantRole(DONOR_ROLE, bounty.donors[i]);
        }

        // Set the strategy state to active
        strategyStorage.state = StrategyState.Active;
    }

    /**
     * @notice Retrieves detailed information about the current state and configuration of the strategy.
     * @dev This function provides an external view of key parameters in the `strategyStorage` struct.
     * @return _state The current state of the strategy (e.g., Active, Executed, Rejected).
     * @return _maxRecipientsAmount The maximum number of recipients allowed for the strategy.
     * @return _totalSupply The total voting power of all managers and donors in the strategy.
     * @return _thresholdPercentage The voting threshold percentage required for decisions.
     * @return _hunter The address of the selected recipient (hunter) of the bounty funds.
     */
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

    /**
     * @notice Allows a manager to propose a set of milestones for the bounty strategy.
     * @dev The milestones are added to the `offeredMilestones` struct for review and voting by other managers.
     * Once the milestones are offered, the function automatically calls `reviewOfferedtMilestones` with a default `Accepted` status.
     * Emits a `MilestonesOffered` event indicating the number of milestones proposed.
     * @param _milestones An array of `Milestone` structs representing the proposed milestones.
     *
     * Requirements:
     * - The caller must have the `MANAGER_ROLE`.
     * - The strategy must be in an active state (`StrategyState.Active`).
     *
     * Emits:
     * - `MilestonesOffered` when the milestones are successfully offered.
     */
    function offerMilestones(Milestone[] memory _milestones) external onlyRole(MANAGER_ROLE) onlyActive {
        // Add each milestone to the offered milestones list
        for (uint256 i = 0; i < _milestones.length; i++) {
            offeredMilestones.milestones.push(_milestones[i]);
        }

        // Emit an event indicating the number of milestones offered
        emit MilestonesOffered(_milestones.length);

        // Automatically review the milestones with an "Accepted" status
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

    /**
     * @notice Allows a donor to vote for rejecting the bounty strategy.
     * @dev Each donor's vote is proportional to their contribution fraction.
     * If the total rejection votes exceed the threshold percentage, the strategy is rejected,
     * and the funds are redistributed back to the donors. The strategy state is updated to `Rejected`.
     * Emits a `ProjectRejected` event if the strategy is rejected.
     *
     * Requirements:
     * - The caller must have the `DONOR_ROLE`.
     * - The strategy must be in an active state (`StrategyState.Active`).
     * - The caller must not have already voted to reject the strategy.
     *
     * @custom:security Donors can only vote once to reject the strategy.
     */
    function rejectStrategy() external onlyRole(DONOR_ROLE) onlyActive {
        // Ensure the donor has not already voted
        require(rejectStrategyVotes.donorVotes[msg.sender] == 0, "ALREADY_REVIEWED");

        // Get the donor's contribution fraction and cast the vote
        uint256 donorContributionFraction = _donorContributionFraction[msg.sender];
        rejectStrategyVotes.donorVotes[msg.sender] = donorContributionFraction;
        rejectStrategyVotes.votes += donorContributionFraction;

        // Check if rejection votes exceed the threshold
        if (_checkIfVotesExceedThreshold(rejectStrategyVotes.votes)) {
            // Distribute funds back to the donors
            _distributeFundsBackToDonors();

            // Update the strategy state to rejected
            strategyStorage.state = StrategyState.Rejected;

            // Emit an event to signify strategy rejection
            emit ProjectRejected();
        }
    }

    /**
     * @notice Allows managers to vote on accepting or rejecting a recipient for the bounty strategy.
     * @dev Managers can cast votes for or against a recipient. Votes are proportional to the manager's voting power.
     * If the total votes exceed the threshold percentage for acceptance or rejection, the recipient's status is finalized:
     * - If accepted, the recipient is assigned as the hunter (`strategyStorage.hunter`) and granted the `HUNTER_ROLE`.
     * - If rejected, the recipient is disqualified, and the `HUNTER_ROLE` is revoked.
     *
     * @param _recipient The address of the recipient being reviewed.
     * @param _status The proposed status for the recipient (`Status.Accepted` or `Status.Rejected`).
     *
     * Requirements:
     * - The caller must have the `MANAGER_ROLE`.
     * - The strategy must be in an active state (`StrategyState.Active`).
     * - The recipient must not have already been reviewed by the caller.
     * - The status must be either `Accepted` or `Rejected`.
     * - If the status is `Accepted`, no recipient (hunter) must already be assigned.
     * - If the status is `Rejected`, a recipient must already be assigned.
     */
    function reviewRecipient(address _recipient, Status _status) external onlyRole(MANAGER_ROLE) onlyActive {
        if (_status == Status.Accepted) {
            require(strategyStorage.hunter == address(0), "MAX_RECIPIENTS_AMOUNT_REACHED");
        } else {
            require(strategyStorage.hunter != address(0), "INVALID_HUNTER");
        }

        // Ensure the manager has not already voted for this recipient
        require(offeredRecipient[_recipient].managersVotes[msg.sender] == 0, "ALREADY_REVIEWED");

        // Ensure the status is either Accepted or Rejected
        require(_status == Status.Accepted || _status == Status.Rejected, "INVALID STATUS");

        // Get the manager's voting power
        uint256 managerVotingPower = manager.getManagerVotingPower(bountyId, msg.sender);
        offeredRecipient[_recipient].managersVotes[msg.sender] = managerVotingPower;

        if (_status == Status.Accepted) {
            offeredRecipient[_recipient].votesFor += managerVotingPower;

            // Check if votes for acceptance exceed the threshold
            if (_checkIfVotesExceedThreshold(offeredRecipient[_recipient].votesFor)) {
                strategyStorage.hunter = _recipient;
                _dropRecipientsVotes(_recipient);

                // Assign the HUNTER_ROLE to the recipient
                _grantRole(HUNTER_ROLE, _recipient);
            }
        } else {
            offeredRecipient[_recipient].votesAgainst += managerVotingPower;

            // Check if votes for rejection exceed the threshold
            if (_checkIfVotesExceedThreshold(offeredRecipient[_recipient].votesAgainst)) {
                strategyStorage.hunter = address(0);
                _dropRecipientsVotes(_recipient);

                // Revoke the HUNTER_ROLE from the recipient
                _revokeRole(HUNTER_ROLE, _recipient);
            }
        }
    }

    /**
     * @notice Allows a hunter or manager to submit a milestone for review.
     * @dev If submitted by a hunter, the milestone is prepared for review by managers.
     * If submitted by a manager, the milestone is automatically reviewed and accepted.
     * Emits a `MilestoneSubmitted` event when the milestone is submitted.
     *
     * @param _milestoneId The ID of the milestone being submitted.
     * @param _metadata Metadata related to the milestone, such as additional details or proof of completion.
     *
     * Requirements:
     * - The `_milestoneId` must reference a valid milestone in the `milestones` array.
     * - The milestone's status must not already be `Accepted`.
     * - The caller must either have the `HUNTER_ROLE` or `MANAGER_ROLE`.
     *
     * Behavior:
     * - If the caller is a hunter (`HUNTER_ROLE`), the milestone is marked as submitted.
     * - If the caller is a manager (`MANAGER_ROLE`), the milestone is submitted and immediately reviewed with a default `Accepted` status.
     *
     * Reverts:
     * - If the caller does not have the required role, with `UNAUTHORIZED`.
     * - If the milestone ID is invalid, with `INVALID_MILESTONE`.
     * - If the milestone has already been accepted, with `MILESTONE_ALREADY_ACCEPTED`.
     */
    function submitMilestone(uint256 _milestoneId, string calldata _metadata) external {
        // Ensure the milestone ID is valid
        require(_milestoneId < milestones.length, "INVALID_MILESTONE");

        // Reference the milestone
        Milestone storage milestone = milestones[_milestoneId];

        // Ensure the milestone has not already been accepted
        require(milestone.milestoneStatus != Status.Accepted, "MILESTONE_ALREADY_ACCEPTED");

        // Handle submission based on the caller's role
        if (hasRole(HUNTER_ROLE, msg.sender)) {
            _submitMilestone(_milestoneId, milestone, _metadata);
        } else if (hasRole(MANAGER_ROLE, msg.sender)) {
            _submitMilestone(_milestoneId, milestone, _metadata);

            // Automatically review and accept the milestone
            reviewSubmitedMilestone(_milestoneId, Status.Accepted);
        } else {
            // Revert if the caller does not have the required role
            revert UNAUTHORIZED();
        }
    }

    /**
     * @notice Allows managers to review a submitted milestone and cast votes for acceptance or rejection.
     * @dev Votes are proportional to the manager's voting power. If the total votes for either acceptance or rejection exceed the threshold, the milestone's status is finalized:
     * - Accepted milestones are distributed to the recipient.
     * - Rejected milestones are reset and removed from review.
     * Emits a `SubmittedMilestoneReviewed` event and, upon finalization, a `MilestoneStatusChanged` event.
     *
     * @param _milestoneId The ID of the milestone being reviewed.
     * @param _status The proposed status for the milestone (`Status.Accepted` or `Status.Rejected`).
     *
     * Requirements:
     * - The caller must have the `MANAGER_ROLE`.
     * - The milestone must exist (`_milestoneId` must be valid).
     * - The milestone's status must be `Pending`.
     * - The caller must not have already reviewed the milestone.
     * - The status must be either `Accepted` or `Rejected`.
     *
     * Behavior:
     * - Adds the manager's voting power to the milestone's votes (for or against).
     * - Finalizes the milestone's status if votes exceed the threshold.
     * - Accepted milestones trigger fund distribution via `_distributeMilestone`.
     * - Rejected milestones are reset and removed from the review queue.
     *
     * Emits:
     * - `SubmittedMilestoneReviewed` after the review action is performed.
     * - `MilestoneStatusChanged` if the milestone's status is finalized.
     */
    function reviewSubmitedMilestone(uint256 _milestoneId, Status _status) public onlyRole(MANAGER_ROLE) {
        // Ensure the milestone has not already been reviewed by the caller
        require(submittedvMilestones[_milestoneId].managersVotes[msg.sender] == 0, "ALREADY_REVIEWED");

        // Validate that the milestone ID exists
        require(_milestoneId < milestones.length, "INVALID_MILESTONE");

        // Reference the milestone and ensure it is in a pending state
        Milestone storage milestone = milestones[_milestoneId];
        require(milestone.milestoneStatus == Status.Pending, "INVALID_MILESTONE_STATUS");

        // Ensure the status is valid for review
        require(_status == Status.Accepted || _status == Status.Rejected, "INVALID STATUS");

        // Add the manager's voting power to the milestone's votes
        uint256 managerVotingPower = manager.getManagerVotingPower(bountyId, msg.sender);
        submittedvMilestones[_milestoneId].managersVotes[msg.sender] = managerVotingPower;

        if (_status == Status.Accepted) {
            submittedvMilestones[_milestoneId].votesFor += managerVotingPower;

            // Finalize if votes exceed the threshold for acceptance
            if (_checkIfVotesExceedThreshold(submittedvMilestones[_milestoneId].votesFor)) {
                milestone.milestoneStatus = _status;
                emit MilestoneStatusChanged(_milestoneId, _status);

                // Distribute funds for the milestone
                _distributeMilestone(_milestoneId);
            }
        } else {
            submittedvMilestones[_milestoneId].votesAgainst += managerVotingPower;

            // Finalize if votes exceed the threshold for rejection
            if (_checkIfVotesExceedThreshold(submittedvMilestones[_milestoneId].votesAgainst)) {
                milestone.milestoneStatus = _status;

                // Reset all manager votes for the rejected milestone
                for (uint256 i = 0; i < bounty.managers.length; i++) {
                    submittedvMilestones[_milestoneId].managersVotes[bounty.managers[i]] = 0;
                }

                // Remove the rejected milestone from review
                delete submittedvMilestones[_milestoneId];
                emit MilestoneStatusChanged(_milestoneId, _status);
            }
        }

        // Emit an event to indicate the milestone was reviewed
        emit SubmittedMilestoneReviewed(_milestoneId, _status);
    }

    /**
     * @notice Distributes the allocated funds for an accepted milestone to the recipient (hunter).
     * @dev This function is called internally once a milestone is accepted and its status is finalized.
     * It calculates the amount to be distributed based on the milestone's percentage allocation and transfers it to the recipient.
     * If the distributed milestone is the last one in the project, the strategy state is updated to `Executed`.
     * Emits a `Distributed` event upon successful transfer of funds.
     *
     * @param _milestoneId The ID of the milestone being distributed.
     *
     * Requirements:
     * - The milestone's status must be `Accepted`.
     *
     * Behavior:
     * - Calculates the funds allocated to the milestone based on `amountPercentage` and the total supply.
     * - Transfers the calculated amount to the hunter (recipient).
     * - Updates the strategy state to `Executed` if the milestone is the last one in the project.
     *
     * Emits:
     * - `Distributed` when funds are successfully distributed to the recipient.
     */
    function _distributeMilestone(uint256 _milestoneId) private {
        // Reference the milestone and ensure it is accepted
        Milestone storage milestone = milestones[_milestoneId];
        require(milestone.milestoneStatus == Status.Accepted, "INVALID_MILESTONE_STATUS");

        // Calculate the amount to distribute for this milestone
        uint256 amountToDistribute = (strategyStorage.totalSupply * milestone.amountPercentage) / 1e18;

        // Transfer the calculated amount to the hunter (recipient)
        SafeTransferLib.safeTransfer(bounty.token, strategyStorage.hunter, amountToDistribute);

        // If this is the last milestone, update the strategy state to Executed
        if ((_milestoneId + 1) >= milestones.length) {
            strategyStorage.state = StrategyState.Executed;
        }

        // Emit an event indicating the milestone distribution
        emit Distributed(_milestoneId, strategyStorage.hunter, amountToDistribute);
    }

    /**
     * @notice Internal function to submit a milestone for review.
     * @dev Resets all previous manager votes for the milestone and updates its metadata and status to `Pending`.
     * Emits a `MilestoneSubmitted` event to indicate successful submission.
     *
     * @param _milestoneId The ID of the milestone being submitted.
     * @param milestone A reference to the milestone being updated.
     * @param _metadata Metadata associated with the milestone, such as proof of completion or additional details.
     *
     * Behavior:
     * - Resets the voting records for all managers associated with the milestone.
     * - Updates the milestone's metadata and sets its status to `Pending`.
     *
     * Emits:
     * - `MilestoneSubmitted` when the milestone is successfully submitted.
     */
    function _submitMilestone(uint256 _milestoneId, Milestone storage milestone, string calldata _metadata) internal {
        // Reset all manager votes for this milestone
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            submittedvMilestones[_milestoneId].managersVotes[bounty.managers[i]] = 0;
        }

        // Clear the existing submitted milestone records
        delete submittedvMilestones[_milestoneId];

        // Update the milestone with new metadata and set its status to Pending
        milestone.metadata = _metadata;
        milestone.milestoneStatus = Status.Pending;

        // Emit an event to indicate the milestone has been submitted
        emit MilestoneSubmitted(_milestoneId, _metadata);
    }

    /**
     * @notice Internal function to reset all votes associated with a specific recipient.
     * @dev Clears the voting records for all managers regarding the specified recipient and deletes the recipient's entry in the `offeredRecipient` mapping.
     *
     * @param _recipient The address of the recipient whose votes are being reset.
     *
     * Behavior:
     * - Iterates through all managers in the bounty project.
     * - Resets each manager's vote count for the specified recipient.
     * - Deletes the recipient's entry in the `offeredRecipient` mapping, effectively removing all associated vote data.
     */
    function _dropRecipientsVotes(address _recipient) internal {
        // Reset all manager votes for the specified recipient
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            offeredRecipient[_recipient].managersVotes[bounty.managers[i]] = 0;
        }

        // Delete the recipient's record from the offeredRecipient mapping
        delete offeredRecipient[_recipient];
    }

    /**
     * @notice Internal function to set and initialize milestones for the bounty strategy.
     * @dev Clears any existing milestones, validates the input milestones, and ensures their total percentage equals 100%.
     * Emits a `MilestonesSet` event upon successful initialization.
     *
     * @param _milestones An array of `Milestone` structs representing the milestones to be set.
     *
     * Requirements:
     * - Each milestone must have a status of `Status.None`.
     * - The sum of `amountPercentage` across all milestones must equal 100% (1e18 in 18-decimal precision).
     *
     * Behavior:
     * - Clears the existing milestones array, if any.
     * - Iterates through the input milestones, validates them, and appends them to the `milestones` array.
     * - Ensures the total percentage allocation across all milestones is exactly 100%.
     *
     * Emits:
     * - `MilestonesSet` indicating the number of milestones successfully set.
     */
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

        // Ensure the total amount percentage equals 100% (1e18 in 18-decimal precision)
        require(totalAmountPercentage == 1e18, "INVALID_MILESTONES_PERCENTAGE");

        // Emit an event indicating the milestones were successfully set
        emit MilestonesSet(milestonesLength);
    }

    /**
     * @notice Internal function to determine if a given number of votes exceeds the defined threshold.
     * @dev Compares the input vote count against the threshold calculated using the total voting power and the threshold percentage.
     *
     * @param _votes The number of votes to check.
     * @return `true` if the votes exceed the threshold, otherwise `false`.
     *
     * Behavior:
     * - Calculates the threshold value as `(totalSupply * thresholdPercentage) / 100`.
     * - Compares the input `_votes` with the calculated threshold.
     *
     * Requirements:
     * - `strategyStorage.totalSupply` must be correctly set to the total voting power of all managers and donors.
     * - `strategyStorage.thresholdPercentage` must be between 0 and 100.
     */
    function _checkIfVotesExceedThreshold(uint256 _votes) internal view returns (bool) {
        // Calculate the threshold value based on the total supply and percentage
        uint256 thresholdValue = (strategyStorage.totalSupply * strategyStorage.thresholdPercentage) / 100;

        // Return whether the votes exceed the threshold
        return _votes > thresholdValue;
    }

    /**
     * @notice Internal function to reset all offered milestones and their associated votes.
     * @dev Clears the votes for all managers and deletes the `offeredMilestones` struct.
     * Emits an `OfferedMilestonesDropped` event upon successful reset.
     *
     * Behavior:
     * - Iterates through all managers associated with the bounty.
     * - Resets their votes for the offered milestones to zero.
     * - Deletes the `offeredMilestones` struct, effectively clearing all proposed milestones.
     * - Emits an event to indicate the offered milestones have been dropped.
     *
     * Emits:
     * - `OfferedMilestonesDropped` when the offered milestones are successfully reset.
     */
    function _resetOfferedMilestones() internal {
        // Reset all manager votes for the offered milestones
        for (uint256 i = 0; i < bounty.managers.length; i++) {
            offeredMilestones.managersVotes[bounty.managers[i]] = 0;
        }

        // Delete the offered milestones record
        delete offeredMilestones;

        // Emit an event indicating the offered milestones were dropped
        emit OfferedMilestonesDropped();
    }

    /**
     * @notice Internal function to redistribute all funds held by the strategy back to the donors.
     * @dev Calculates the amount to be refunded to each donor based on their contribution fraction and transfers the funds.
     * Uses the `SafeTransferLib` for secure token transfers.
     *
     * Behavior:
     * - Fetches the token balance of the contract.
     * - Iterates through the list of donors and calculates their refund based on their contribution fraction.
     * - Transfers the calculated amount of tokens to each donor.
     *
     * Requirements:
     * - The contract must hold a sufficient token balance for redistribution.
     *
     * Security:
     * - Ensures safe token transfers using the `SafeTransferLib`.
     */
    function _distributeFundsBackToDonors() private {
        // Fetch the token balance held by the contract
        IERC20 token = IERC20(bounty.token);
        uint256 tokenBalance = token.balanceOf(address(this));

        // Iterate through all donors to calculate and distribute their refunds
        for (uint256 i = 0; i < bounty.donors.length; i++) {
            uint256 fraction = _donorContributionFraction[bounty.donors[i]];
            uint256 amount = (tokenBalance * fraction) / 1e18;

            // Safely transfer the calculated amount to the donor
            SafeTransferLib.safeTransfer(bounty.token, bounty.donors[i], amount);
        }
    }
}
