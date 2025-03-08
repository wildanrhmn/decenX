// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/ContentRegistry.sol";
import "../contracts/ModeratorRegistry.sol";
import "../contracts/ModerationSystem.sol";

/**
 * @notice Deploy script for Content Moderation Platform contracts
 * @dev Inherits ScaffoldETHDeploy which:
 *      - Includes forge-std/Script.sol for deployment
 *      - Includes ScaffoldEthDeployerRunner modifier
 *      - Provides `deployer` variable
 * Example:
 * yarn deploy --file DeployYourContract.s.sol  # local anvil chain
 * yarn deploy --file DeployYourContract.s.sol --network sepolia # live network (requires keystore)
 */
contract DeployYourContract is ScaffoldETHDeploy {
    /**
     * @dev Deployer setup based on `ETH_KEYSTORE_ACCOUNT` in `.env`
     */
    function run() external ScaffoldEthDeployerRunner {
        ModeratorRegistry moderatorRegistry = new ModeratorRegistry();
        ContentRegistry contentRegistry = new ContentRegistry();
        ModerationSystem moderationSystem = new ModerationSystem(
            contentRegistry,
            moderatorRegistry
        );

        contentRegistry.setModerationContract(address(moderationSystem));
        moderatorRegistry.setModerationContract(address(moderationSystem));

        // The ScaffoldEthDeployerRunner modifier will automatically:
        // - Export contract addresses & ABIs to NextJS packages
        // - Log deployed addresses
    }
}
