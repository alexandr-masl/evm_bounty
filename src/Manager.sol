// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "strategy/interfaces/IStrategyFactory.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {BountyStrategy} from "./BountyStrategy.sol";

contract Manager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /**
     * @dev Represents the funding details for a bounty project.
     * @param need The total amount of funding required for the project.
     * @param has The amount of funding currently supplied to the project.
     */
    struct BountySupply {
        uint256 need; // The total amount needed for the project.
        uint256 has; // The amount currently supplied.
    }

    /**
     * @dev Represents the full details of a bounty project.
     * @param token The address of the ERC20 token used for funding the project.
     * @param executor The address of the executor responsible for managing the project.
     * @param managers The list of addresses assigned as managers for the project.
     * @param donors The list of addresses that have contributed funds to the project.
     * @param supply A `BountySupply` struct containing funding requirements and progress.
     * @param poolId A unique identifier for the project's funding pool.
     * @param strategy The address of the strategy contract associated with the project.
     * @param metadata A string containing additional metadata about the project (e.g., description, links).
     * @param name The name of the project.
     */
    struct BountyInformation {
        address token;
        address executor;
        address[] managers;
        address[] donors;
        BountySupply supply;
        uint256 poolId;
        address strategy;
        string metadata;
        string name;
    }

    /**
     * @notice The percentage threshold required for manager voting to approve certain actions.
     * @dev This is a value between 0 and 100, representing a percentage.
     */
    uint8 public thresholdPercentage;

    /**
     * @notice The address of the default strategy contract used for managing project funds.
     * @dev This strategy is applied to projects once they are fully funded.
     */
    address public strategy;

    /**
     * @notice A counter used to assign unique pool IDs for projects.
     * @dev Incremented with each new project registration.
     */
    uint256 public nonce;

    // Private Variables

    /**
     * @notice Indicates whether the contract has been initialized.
     * @dev Used to prevent the contract from being initialized more than once.
     */
    bool private initialized;

    /**
     * @notice The address of the strategy factory contract used to create new strategy instances.
     * @dev Provides a standardized way to deploy strategy contracts for projects.
     */
    IStrategyFactory private strategyFactory;

    /**
     * @notice Stores the details of all registered bounty projects.
     * @dev Maps a unique project ID (`bytes32`) to its corresponding `BountyInformation` struct.
     */
    mapping(bytes32 => BountyInformation) public bounties;

    /**
     * @notice Tracks the voting power of each manager for a specific bounty project.
     * @dev Maps a project ID (`bytes32`) and a manager's address to their voting power (`uint256`).
     */
    mapping(bytes32 => mapping(address => uint256)) public managerVotingPower;

    /**
     * @notice Tracks the contribution amounts of each donor for a specific bounty project.
     * @dev Maps a project ID (`bytes32`) and a donor's address to the amount they contributed (`uint256`).
     */
    mapping(bytes32 => mapping(address => uint256)) public donorContribution;

    /**
     * @notice Maps each donor to the manager they are associated with for a specific bounty project.
     * @dev Maps a project ID (`bytes32`) and a donor's address to the manager's address (`address`).
     */
    mapping(bytes32 => mapping(address => address)) public donorToManager;

    /**
     * @notice Emitted when a new project (bounty) is registered.
     * @param profileId The unique identifier assigned to the registered project.
     * @param nonce The unique pool ID assigned to the project during registration.
     */
    event ProjectRegistered(bytes32 profileId, uint256 nonce);

    /**
     * @notice Emitted when a project receives funding from a donor.
     * @param projectId The unique identifier of the funded project.
     * @param amount The amount of funding supplied to the project.
     */
    event ProjectFunded(bytes32 indexed projectId, uint256 amount);

    /**
     * @notice Emitted when a project is fully funded and its pool is created.
     * @param projectId The unique identifier of the project whose pool was created.
     */
    event ProjectPoolCreated(bytes32 projectId);

    /**
     * @notice Emitted when a donor's contribution to a project is revoked and refunded.
     * @param projectId The unique identifier of the project from which the supply was revoked.
     * @param donor The address of the donor whose contribution was revoked.
     * @param amount The amount of funding that was refunded to the donor.
     */
    event ProjectSupplyRevoked(bytes32 projectId, address donor, uint256 amount);

    /**
     * @notice Initializes the Manager contract with required dependencies and initial settings.
     * @dev This function can only be called once. It initializes the Ownable and ReentrancyGuard modules.
     * @param _strategy The address of the default strategy contract to be used for bounties.
     * @param _strategyFactory The address of the strategy factory contract used to create strategies.
     */
    function initialize(address _strategy, address _strategyFactory) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;

        // Initialize Ownable and ReentrancyGuard modules
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        // Set the default strategy and strategy factory addresses
        strategy = _strategy;
        strategyFactory = IStrategyFactory(_strategyFactory);

        // Set the default threshold percentage for manager voting
        thresholdPercentage = 70;
    }

    /**
     * @notice Retrieves the address of the strategy contract associated with a specific project.
     * @param _projectId The unique identifier of the project.
     * @return The address of the strategy contract linked to the given project.
     */
    function getBountyStrategy(bytes32 _projectId) public view returns (address) {
        return bounties[_projectId].strategy;
    }

    /**
     * @notice Retrieves detailed information about a specific bounty.
     * @param _bountyId The unique identifier of the bounty.
     * @return A `BountyInformation` struct containing details about the bounty,
     * including token address, executor, managers, donors, supply details, pool ID, strategy, metadata, and name.
     */
    function getBounty(bytes32 _bountyId) external view returns (BountyInformation memory) {
        return bounties[_bountyId];
    }

    /**
     * @notice Retrieves the voting power of a specific manager for a given bounty.
     * @param _bountyId The unique identifier of the bounty.
     * @param _manager The address of the manager whose voting power is being queried.
     * @return The voting power of the specified manager for the given bounty.
     */
    function getManagerVotingPower(bytes32 _bountyId, address _manager) external view returns (uint256) {
        return managerVotingPower[_bountyId][_manager];
    }

    /**
     * @notice Retrieves the total contribution made by a specific donor for a given bounty.
     * @param _bountyId The unique identifier of the bounty.
     * @param _donor The address of the donor whose contribution is being queried.
     * @return The total contribution amount made by the specified donor for the given bounty.
     */
    function getDonorContribution(bytes32 _bountyId, address _donor) external view returns (uint256) {
        return donorContribution[_bountyId][_donor];
    }

    /**
     * @notice Retrieves detailed information about a specific bounty.
     * @param _bountyId The unique identifier of the bounty.
     * @return _token The address of the ERC20 token associated with the bounty.
     * @return _executor The address of the executor responsible for managing the bounty.
     * @return _managers The array of addresses for managers associated with the bounty.
     * @return _donors The array of addresses for donors who contributed to the bounty.
     * @return _need The total amount of funds required for the bounty.
     * @return _has The amount of funds currently raised for the bounty.
     * @return _poolId The ID of the funding pool associated with the bounty.
     * @return _strategy The address of the strategy contract linked to the bounty.
     * @return _metadata Additional metadata describing the bounty.
     * @return _name The name of the bounty.
     */
    function getBountyInfo(bytes32 _bountyId)
        external
        view
        returns (
            address _token,
            address _executor,
            address[] memory _managers,
            address[] memory _donors,
            uint256 _need,
            uint256 _has,
            uint256 _poolId,
            address _strategy,
            string memory _metadata,
            string memory _name
        )
    {
        BountyInformation storage bounty = bounties[_bountyId];
        return (
            bounty.token,
            bounty.executor,
            bounty.managers,
            bounty.donors,
            bounty.supply.need,
            bounty.supply.has,
            bounty.poolId,
            bounty.strategy,
            bounty.metadata,
            bounty.name
        );
    }

    /**
     * @notice Registers a new project (bounty) with the specified parameters.
     * @dev Assigns a unique profile ID to the project and stores its information in the contract's state.
     * @param _token The address of the ERC20 token to be used for the project's funding.
     * @param _needs The total amount of funding required for the project.
     * @param _name The name of the project.
     * @param _metadata Metadata containing additional information about the project (e.g., description, links).
     * @return The unique profile ID assigned to the registered project.
     */
    function registerProject(address _token, uint256 _needs, string memory _name, string memory _metadata)
        external
        returns (bytes32)
    {
        // Generate a unique profile ID for the project
        bytes32 profileId = _generateProfileId(msg.sender);

        // Initialize the project's bounty information
        bounties[profileId].token = _token;
        bounties[profileId].supply.need = _needs;
        bounties[profileId].metadata = _metadata;
        bounties[profileId].poolId = nonce;
        bounties[profileId].name = _name;

        // Emit an event for the registered project
        emit ProjectRegistered(profileId, nonce);

        // Return the unique profile ID of the project
        return profileId;
    }

    /**
     * @notice Supplies funding to a specific project (bounty) and updates its state.
     * @dev Ensures the supplied amount does not exceed the required amount. Once fully funded, the project's strategy is created and initialized.
     * @param _projectId The unique identifier of the project to fund.
     * @param _amount The amount of funding (in the project's token) being supplied.
     * @param _donor The address of the donor supplying the funds.
     *
     * Requirements:
     * - The total funding (`supply.has + _amount`) must not exceed the required funding (`supply.need`).
     * - The project must exist.
     * - The supplied amount must be greater than zero.
     * - The project must not already have a strategy (i.e., not fully funded).
     *
     * Emits:
     * - `ProjectFunded` when funds are successfully supplied.
     * - `ProjectPoolCreated` when the project becomes fully funded, and its strategy is created.
     */
    function supplyProject(bytes32 _projectId, uint256 _amount, address _donor) external payable nonReentrant {
        // Ensure the supplied amount does not exceed the declared funding need
        require(
            (bounties[_projectId].supply.has + _amount) <= bounties[_projectId].supply.need,
            "AMOUNT_IS_BIGGER_THAN_DECLARED_NEEDEDS"
        );

        // Ensure the project exists
        require(_projectExists(_projectId), "BOUNTY_DOES_NOT_EXISTS");

        // Ensure the supplied amount is valid
        require(_amount > 0, "INVALID_AMOUNT");

        // Ensure the project is not already fully funded
        require(bounties[_projectId].strategy == address(0), "BOUNTY_IS_FULLY_FUNDED");

        // Transfer the funding amount from the donor to the contract
        SafeTransferLib.safeTransferFrom(bounties[_projectId].token, msg.sender, address(this), _amount);

        // Update the project's funding state
        bounties[_projectId].supply.has += _amount;

        // Add the manager to the project if not already added
        if (managerVotingPower[_projectId][msg.sender] == 0) {
            bounties[_projectId].managers.push(msg.sender);
        }

        // Add the donor to the project if not already added
        if (donorContribution[_projectId][_donor] == 0) {
            bounties[_projectId].donors.push(_donor);
        }

        // Update the manager's voting power and donor's contribution
        managerVotingPower[_projectId][msg.sender] += _amount;
        donorContribution[_projectId][_donor] += _amount;
        donorToManager[_projectId][_donor] = msg.sender;

        // Emit an event to signify the project was funded
        emit ProjectFunded(_projectId, _amount);

        // Check if the project is now fully funded
        if (bounties[_projectId].supply.has >= bounties[_projectId].supply.need) {
            IERC20 token = IERC20(bounties[_projectId].token);

            // Ensure the contract holds enough tokens to create the strategy
            require(
                token.balanceOf(address(this)) >= bounties[_projectId].supply.need,
                "Insufficient token balance in contract"
            );

            // Create and initialize the strategy for the project
            address strategyAddress = strategyFactory.createStrategy(strategy);
            bounties[_projectId].strategy = strategyAddress;

            BountyStrategy(strategyAddress).initialize(address(this), _projectId);

            // Transfer the full bounty funds to the strategy
            SafeTransferLib.safeTransfer(bounties[_projectId].token, strategyAddress, bounties[_projectId].supply.need);

            // Emit an event to signify the project pool was created
            emit ProjectPoolCreated(_projectId);
        }
    }

    /**
     * @notice Revokes a donor's contribution to a project and refunds the amount.
     * @dev Can only be executed if the project is not yet managed by a strategy (i.e., not fully funded).
     * Removes the donor and their associated manager from the project if applicable.
     * @param _projectId The unique identifier of the project from which the supply is being revoked.
     * @param _donor The address of the donor whose contribution is being revoked.
     *
     * Requirements:
     * - The project must exist.
     * - The project must not already be managed by a strategy.
     * - The caller must either be a manager or a donor of the project.
     * - The specified donor must have a contribution greater than zero.
     *
     * Emits:
     * - `ProjectSupplyRevoked` when the supply is successfully revoked.
     */
    function revokeProjectSupply(bytes32 _projectId, address _donor) external nonReentrant {
        // Ensure the project exists
        require(_projectExists(_projectId), "Project does not exist");

        // Ensure the project is not yet managed by a strategy
        require(bounties[_projectId].strategy == address(0), "BOUNTY_IS_MANAGED_BY_THE_STRATEGY");

        // Ensure the caller is authorized (must be a manager or a donor)
        require(
            managerVotingPower[_projectId][msg.sender] != 0 || donorContribution[_projectId][msg.sender] != 0,
            "UNAUTHORIZED"
        );

        // Get the donor's contribution amount and ensure it exists
        uint256 amount = donorContribution[_projectId][_donor];
        require(amount > 0, "DONOR NOT FOUND");

        // Remove the donor's manager voting power
        address managerId = donorToManager[_projectId][_donor];
        delete managerVotingPower[_projectId][managerId];

        // Remove the donor's contribution
        delete donorContribution[_projectId][_donor];

        // Update the project's supply
        bounties[_projectId].supply.has -= amount;

        // Remove the manager from the project's list
        address[] memory updatedManagers = new address[](bounties[_projectId].managers.length - 1);
        uint256 j = 0;
        for (uint256 i = 0; i < bounties[_projectId].managers.length; i++) {
            if (bounties[_projectId].managers[i] != managerId) {
                updatedManagers[j] = bounties[_projectId].managers[i];
                j++;
            }
        }
        bounties[_projectId].managers = updatedManagers;

        // Remove the donor from the project's list
        address[] memory updatedDonors = new address[](bounties[_projectId].donors.length - 1);
        uint256 donorIndex = 0;
        for (uint256 i = 0; i < bounties[_projectId].donors.length; i++) {
            if (bounties[_projectId].donors[i] != _donor) {
                updatedDonors[donorIndex] = bounties[_projectId].donors[i];
                donorIndex++;
            }
        }
        bounties[_projectId].donors = updatedDonors;

        // Refund the donor
        SafeTransferLib.safeTransfer(bounties[_projectId].token, _donor, amount);

        // Emit an event indicating the supply has been revoked
        emit ProjectSupplyRevoked(_projectId, _donor, amount);
    }

    /**
     * @notice Generates a unique profile ID for a project based on the owner's address and current blockchain data.
     * @dev Uses `keccak256` hashing with the owner's address, current timestamp, and the previous block's random number.
     * This ensures a unique identifier for each project.
     * @param _owner The address of the owner creating the project.
     * @return A unique `bytes32` profile ID for the project.
     */
    function _generateProfileId(address _owner) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_owner, block.timestamp, block.prevrandao));
    }

    /**
     * @notice Checks if a project exists in the contract's state.
     * @dev A project is considered to exist if its associated token address is not zero.
     * @param _profileId The unique identifier of the project.
     * @return A boolean indicating whether the project exists (`true`) or not (`false`).
     */
    function _projectExists(bytes32 _profileId) private view returns (bool) {
        BountyInformation storage bounty = bounties[_profileId];
        return bounty.token != address(0);
    }

    /// @notice This contract should be able to receive native token
    receive() external payable {}
}
