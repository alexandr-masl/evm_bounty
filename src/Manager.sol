// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "strategy/interfaces/IStrategyFactory.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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

    function initialize(address _strategy, address _strategyFactory) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        strategy = _strategy;
        strategyFactory = IStrategyFactory(_strategyFactory);
        thresholdPercentage = 70;
    }

    function getPoolToken(bytes32 _bountyId) external view returns (address token) {
        token = projects[_bountyId].token;
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

    function _generateProfileId(uint256 _nonce, address _owner) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nonce, _owner));
    }
}
