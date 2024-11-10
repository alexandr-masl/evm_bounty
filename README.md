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
