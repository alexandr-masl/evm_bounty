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

    struct BountySupply {
        uint256 need; // The total amount needed for the project.
        uint256 has; // The amount currently supplied.
    }

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

    uint8 public thresholdPercentage;
    address public strategy;
    uint256 public nonce;

    bool private initialized;
    IStrategyFactory private strategyFactory;

    mapping(bytes32 => BountyInformation) public bounties;
    mapping(bytes32 => mapping(address => uint256)) public managerVotingPower;
    mapping(bytes32 => mapping(address => uint256)) public donorContribution;
    mapping(bytes32 => mapping(address => address)) public donorToManager;

    event ProjectRegistered(bytes32 profileId, uint256 nonce);
    event ProjectFunded(bytes32 indexed projectId, uint256 amount);
    event ProjectPoolCreated(bytes32 projectId);
    event ProjectSupplyRevoked(bytes32 projectId, address donor, uint256 amount);
    

    function initialize(address _strategy, address _strategyFactory) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        strategy = _strategy;
        strategyFactory = IStrategyFactory(_strategyFactory);
        thresholdPercentage = 70;
    }

    function getBountyStrategy(bytes32 _projectId) public view returns (address) {
        return bounties[_projectId].strategy;
    }

    function getBounty(bytes32 _bountyId)
    external
    view
    returns (BountyInformation memory) {
        return bounties[_bountyId];
    }

    function getManagerVotingPower(bytes32 _bountyId, address _manager)
    external
    view
    returns (uint256) {
        return managerVotingPower[_bountyId][_manager];
    }

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

    function registerProject(address _token, uint256 _needs, string memory _name, string memory _metadata)
        external
        returns (bytes32)
    {
        nonce++;

        bytes32 profileId = _generateProfileId(nonce, msg.sender);

        bounties[profileId].token = _token;
        bounties[profileId].supply.need = _needs;
        bounties[profileId].metadata = _metadata;
        bounties[profileId].poolId = nonce;
        bounties[profileId].name = _name;

        emit ProjectRegistered(profileId, nonce);

        return profileId;
    }

    function supplyProject(bytes32 _projectId, uint256 _amount, address _donor) external payable nonReentrant {
        require(
            (bounties[_projectId].supply.has + _amount) <= bounties[_projectId].supply.need,
            "AMOUNT_IS_BIGGER_THAN_DECLARED_NEEDEDS"
        );

        require(_projectExists(_projectId), "BOUNTY_DOES_NOT_EXISTS");

        require(_amount > 0, "INVALID_AMOUNT");

        require(bounties[_projectId].strategy == address(0), "BOUNTY_IS_FULLY_FUNDED");

        SafeTransferLib.safeTransferFrom(bounties[_projectId].token, msg.sender, address(this), _amount);

        bounties[_projectId].supply.has += _amount;

        if (managerVotingPower[_projectId][msg.sender] == 0) {
            bounties[_projectId].managers.push(msg.sender);
        }

        if (donorContribution[_projectId][_donor] == 0) {
            bounties[_projectId].donors.push(_donor);
        }

        managerVotingPower[_projectId][msg.sender] += _amount;
        donorContribution[_projectId][_donor] += _amount;
        donorToManager[_projectId][_donor] = msg.sender;

        emit ProjectFunded(_projectId, _amount);

        if (bounties[_projectId].supply.has >= bounties[_projectId].supply.need) {
            IERC20 token = IERC20(bounties[_projectId].token);

            require(
                token.balanceOf(address(this)) >= bounties[_projectId].supply.need,
                "Insufficient token balance in contract"
            );

            address strategyAddress = strategyFactory.createStrategy(strategy);

            bounties[_projectId].strategy = strategyAddress;

            BountyStrategy(strategyAddress).initialize(address(this), _projectId);

            SafeTransferLib.safeTransfer(bounties[_projectId].token, strategyAddress, bounties[_projectId].supply.need);

            emit ProjectPoolCreated(_projectId);
        }
    }

    function revokeProjectSupply(bytes32 _projectId, address _donor) external nonReentrant {
        require(_projectExists(_projectId), "Project does not exist");
        require(bounties[_projectId].strategy == address(0), "BOUNTY_IS_MANAGED_BY_THE_STRATEGY");

        require(managerVotingPower[_projectId][msg.sender] != 0 || donorContribution[_projectId][msg.sender] != 0, "UNAUTHORIZED");

        uint256 amount = donorContribution[_projectId][_donor];
        require(amount > 0, "DONOR NOT FOUND");

        address managerId = donorToManager[_projectId][_donor];
        delete managerVotingPower[_projectId][managerId];

        delete donorContribution[_projectId][_donor];

        bounties[_projectId].supply.has -= amount;

        address[] memory updatedManagers = new address[](bounties[_projectId].managers.length - 1);
        uint256 j = 0;

        for (uint256 i = 0; i < bounties[_projectId].managers.length; i++) {
            if (bounties[_projectId].managers[i] != managerId) {
                updatedManagers[j] = bounties[_projectId].managers[i];
                j++;
            }
        }
        bounties[_projectId].managers = updatedManagers;

        address[] memory updatedDonors = new address[](bounties[_projectId].donors.length - 1);
        uint256 donorIndex = 0;

        for (uint256 i = 0; i < bounties[_projectId].donors.length; i++) {
            if (bounties[_projectId].donors[i] != _donor) {
                updatedDonors[donorIndex] = bounties[_projectId].donors[i];
                donorIndex++;
            }
        }
        bounties[_projectId].donors = updatedDonors;

        SafeTransferLib.safeTransfer(bounties[_projectId].token, _donor, amount);

        emit ProjectSupplyRevoked(_projectId, _donor, amount);
    }

    function _extractSupliers(bytes32 _projectId) internal view returns (BountyStrategy.SupplierPower[] memory) {
        BountyStrategy.SupplierPower[] memory suppliersPower =
            new BountyStrategy.SupplierPower[](bounties[_projectId].managers.length);

        for (uint256 i = 0; i < bounties[_projectId].managers.length; i++) {
            address supplierId = bounties[_projectId].managers[i];
            uint256 supplierPower = managerVotingPower[_projectId][supplierId];

            suppliersPower[i] = BountyStrategy.SupplierPower(supplierId, uint256(supplierPower));
        }

        return suppliersPower;
    }

    function _generateProfileId(uint256 _nonce, address _owner) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nonce, _owner));
    }

    function _projectExists(bytes32 _profileId) private view returns (bool) {
        BountyInformation storage bounty = bounties[_profileId];
        return bounty.token != address(0);
    }

    /// @notice This contract should be able to receive native token
    receive() external payable {}
}
