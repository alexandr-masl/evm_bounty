// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

interface IStrategyFactory {
    function createStrategy(address _template) external returns (address);
}
