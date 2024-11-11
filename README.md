# Bounty Machine

Designed to manage any milestone-based funding logic, including bounties and crowdfunding. 
Essentially, it functions like a traditional paper contract but leverages key Web3 benefits such as automation, security, transparent voting, and flexible task delegation. All funds distribution events in the strategy are driven by a committee voting process, ensuring accountability.

The strategy incorporates three main roles: **Donor**, **Manager**, and **Hunter**.

## Process Overview:

- **Pool Creation:** A user creates a project, providing a description of the work to be done. The project creator can fund it themselves, making it a bounty task, or leave it open for others to fund, in which case it becomes a crowdfunding project. Once funded, the contributors form a voting committee with the `Donor` role, giving them decision-making power.

- **Voting and Management:** Donors can choose to manage the process directly or delegate their voting power to a Manager—typically a bot. If a bot manages the bounty, it takes on the `Manager` role with delegated voting power, though a person can also serve as Manager if they prefer to make decisions manually.

- **Milestone Setup:** Once funded, the Manager(s) can define milestones, dividing the total pool among milestones by percentage. For example, they might set two milestones at 50% each or a single 100% milestone, specifying the task for each milestone that a Hunter must complete to receive payment.

- **Task Completion and Voting:** Any approved person can be promoted to the `Hunter` role to work on the milestone. Once ready, the Hunter submits the completed work, and the Manager(s) vote on its quality. If the submission passes the voting threshold, funds are distributed to the Hunter.

- **Strategy Rejection:** At any point, if the project shows no progress, Donors can reject the strategy, sending funds back to contributors.


## Overview of Main Process Phases

- ### Project Creation:

    This phase involves interactions with [the Manager contract](https://github.com/alexandr-masl/evm_bounty/blob/main/src/Manager.sol). Any user can create a project by calling the [`registerProject`](https://github.com/alexandr-masl/evm_bounty/blob/e95ed7b71214bfe14a134a056e3bed22ee5d1020/src/Manager.sol#L106) function on the Manager contract with the following parameters: `address _token`, `uint256 _needs`, `string _name`, and `string _metadata`. These parameters represent the project token, the required funding amount, the project name, and metadata (such as a URL) pointing to the project details. 

    For example, the parameters might look like this: `(0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9, 7, "Test Project", "https://github.com/alexandr-masl/evm_bounty")`. Upon successful registration, the contract will add the project and return a project ID (in `bytes32` format), which will be used for all subsequent interactions with the project.

- ### Project Funding:

    This phase involves funding the project. A supporter can contribute by calling the [`supplyProject`](https://github.com/alexandr-masl/evm_bounty/blob/e95ed7b71214bfe14a134a056e3bed22ee5d1020/src/Manager.sol#L123) function on the Manager contract, providing the following parameters: `bytes32 _projectId`, `uint256 _amount`, and `address _donor`. These represent the project ID, the amount of project tokens to contribute, and the donor address, respectively.

    If the contributor wishes to manage all processes personally, they specify their own address as the donor. Alternatively, if they prefer to delegate voting rights, they can approve the contribution amount for a bot (or another representative), which will fund the project on their behalf and set the donor’s address of the sponsor. In this case, the bot will have voting rights, while the donor retains the ability to withdraw their funds at any time.

    The account that calls the `supplyProject` function is assigned the **`Manager`** role, while the _donor address is assigned the **`Donor`** role. An account can hold both roles if it designates its own wallet as the donor. Alternatively, if the account delegates, it retains only the `Donor` role, while the delegated entity assumes the `Manager` role.

    A project can be fully funded, granting 100% voting power to the contributor, or it can be partially funded. For example, if a contributor funds 30% of the project's required amount, they will receive 30% voting power, proportional to their contribution relative to the project's total funding requirement





### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Manager.s.sol:ManagerScript --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast

$ forge script script/MockERC20.s.sol:MockERC20Script --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast

```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
