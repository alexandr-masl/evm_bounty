// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BountyStrategy is ReentrancyGuard {
    /// @notice Struct to hold details of an recipient
    enum StrategyState {
        None,
        Active,
        Executed,
        Rejected
    }

    /// @notice Struct to represent the power of a supplier.
    struct SupplierPower {
        address supplierId; // Address of the supplier.
        uint256 supplierPowerr; // Power value associated with the supplier.
    }

    struct Storage {
        StrategyState state;
        uint256 registeredRecipients;
        uint32 maxRecipientsAmount;
        uint256 totalSupply;
        uint256 currentSupply;
        uint256 thresholdPercentage;
    }

    event Initialized();

    Storage public strategyStorage;
    address[] private _suppliersStore;
    mapping(address => uint256) private _suplierPower;

    function initialize(SupplierPower[] memory _projectSuppliers, uint32 _maxRecipients) external virtual {
        require(strategyStorage.thresholdPercentage == 0, "ALREADY_INITIALIZED");
        _BountyStrategy_init(_projectSuppliers, _maxRecipients);
        emit Initialized();
    }

    function _BountyStrategy_init(SupplierPower[] memory _projectSuppliers, uint32 _maxRecipients) internal {
        // Set the strategy specific variables
        strategyStorage.thresholdPercentage = 77;
        strategyStorage.maxRecipientsAmount = _maxRecipients;

        SupplierPower[] memory supliersPower = _projectSuppliers;

        uint256 totalInvestment = 0;
        for (uint256 i = 0; i < supliersPower.length; i++) {
            totalInvestment += supliersPower[i].supplierPowerr;
        }

        for (uint256 i = 0; i < supliersPower.length; i++) {
            _suppliersStore.push(supliersPower[i].supplierId);

            // Normalize supplier power to a percentage
            _suplierPower[supliersPower[i].supplierId] = (supliersPower[i].supplierPowerr * 1e18) / totalInvestment;
            strategyStorage.totalSupply += _suplierPower[supliersPower[i].supplierId];
        }

        strategyStorage.currentSupply = strategyStorage.totalSupply;
        strategyStorage.state = StrategyState.Active;

        // _createAndMintManagerHat(
        //     "Manager", supliersPower, "ipfs://bafkreiey2a5jtqvjl4ehk3jx7fh7edsjqmql6vqxdh47znsleetug44umy/"
        // );

        // _createRecipientHat("Recipient", "ipfs://bafkreih7hjg4ehf4lqdoqstlkjxvjy7zfnza4keh2knohsle3ikjja3g2i/");
    }
}
