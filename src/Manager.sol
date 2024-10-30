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
    struct SuppliersById {
        mapping(address => uint256) supplyById; // Maps supplier address to their supply amount.
    }

    struct BountySupply {
        uint256 need; // The total amount needed for the project.
        uint256 has; // The amount currently supplied.
    }

    struct BountyInformation {
        address token;
        address executor;
        address[] suppliers;
        SuppliersById suppliersById;
        BountySupply supply;
        uint256 poolId;
        address strategy;
        string metadata;
        string name;
    }

    bool private initialized;
    IStrategyFactory private strategyFactory;

    uint8 public thresholdPercentage;
    address public strategy;
    uint256 public nonce;

    mapping(bytes32 => BountyInformation) projects;

    event ProjectRegistered(bytes32 profileId, uint256 nonce);
    event ProjectFunded(bytes32 indexed projectId, uint256 amount);
    event ProjectPoolCreated(bytes32 projectId);

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
        return projects[_projectId].strategy;
    }

    function getBountyInfo(bytes32 _bountyId)
        external
        view
        returns (
            address _token,
            address _executor,
            address[] memory _suppliers,
            uint256 _need,
            uint256 _has,
            uint256 _poolId,
            address _strategy,
            string memory _metadata,
            string memory _name
        )
    {
        BountyInformation storage bounty = projects[_bountyId];
        return (
            bounty.token,
            bounty.executor,
            bounty.suppliers,
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

        projects[profileId].token = _token;
        projects[profileId].supply.need = _needs;
        projects[profileId].metadata = _metadata;
        projects[profileId].poolId = nonce;
        projects[profileId].name = _name;

        emit ProjectRegistered(profileId, nonce);

        return profileId;
    }

    function supplyProject(bytes32 _projectId, uint256 _amount, address _donor) external payable nonReentrant {
        require(
            (projects[_projectId].supply.has + _amount) <= projects[_projectId].supply.need,
            "AMOUNT_IS_BIGGER_THAN_DECLARED_NEEDEDS"
        );

        require(_projectExists(_projectId), "BOUNTY_DOES_NOT_EXISTS");

        require(_amount > 0, "INVALID_AMOUNT");

        require(projects[_projectId].strategy == address(0), "BOUNTY_IS_FULLY_FUNDED");

        SafeTransferLib.safeTransferFrom(projects[_projectId].token, _donor, address(this), _amount);

        projects[_projectId].supply.has += _amount;

        if (projects[_projectId].suppliersById.supplyById[msg.sender] == 0) {
            projects[_projectId].suppliers.push(msg.sender);
        }

        projects[_projectId].suppliersById.supplyById[msg.sender] += _amount;

        emit ProjectFunded(_projectId, _amount);

        if (projects[_projectId].supply.has >= projects[_projectId].supply.need) {
            IERC20 token = IERC20(projects[_projectId].token);

            require(
                token.balanceOf(address(this)) >= projects[_projectId].supply.need,
                "Insufficient token balance in contract"
            );

            BountyStrategy.SupplierPower[] memory suppliers = _extractSupliers(_projectId);
            address[] memory managers = new address[](suppliers.length);

            for (uint256 i = 0; i < suppliers.length; i++) {
                managers[i] = (suppliers[i].supplierId);
            }

            address strategyAddress = strategyFactory.createStrategy(strategy);

            projects[_projectId].strategy = strategyAddress;

            BountyStrategy(strategyAddress).initialize(suppliers, 1);

            SafeTransferLib.safeTransfer(projects[_projectId].token, strategyAddress, projects[_projectId].supply.need);

            emit ProjectPoolCreated(_projectId);
        }
    }

    function _extractSupliers(bytes32 _projectId) internal view returns (BountyStrategy.SupplierPower[] memory) {
        BountyStrategy.SupplierPower[] memory suppliersPower =
            new BountyStrategy.SupplierPower[](projects[_projectId].suppliers.length);

        for (uint256 i = 0; i < projects[_projectId].suppliers.length; i++) {
            address supplierId = projects[_projectId].suppliers[i];
            uint256 supplierPower = projects[_projectId].suppliersById.supplyById[supplierId];

            suppliersPower[i] = BountyStrategy.SupplierPower(supplierId, uint256(supplierPower));
        }

        return suppliersPower;
    }

    function _generateProfileId(uint256 _nonce, address _owner) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nonce, _owner));
    }

    function _projectExists(bytes32 _profileId) private view returns (bool) {
        BountyInformation storage bounty = projects[_profileId];
        return bounty.token != address(0);
    }

    /// @notice This contract should be able to receive native token
    receive() external payable {}
}
