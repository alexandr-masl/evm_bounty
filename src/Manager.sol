// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "strategy/interfaces/IStrategyFactory.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Manager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    bool private initialized;
    IStrategyFactory private strategyFactory;

    uint8 public thresholdPercentage;
    address public strategy;

    function initialize(address _strategy, address _strategyFactory) public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        strategy = _strategy;
        strategyFactory = IStrategyFactory(_strategyFactory);
        thresholdPercentage = 70;
    }
}
