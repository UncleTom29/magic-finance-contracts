import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

module.exports = buildModule("MagicToken", (m) => {
    // Parameters
    const owner = m.getAccount(0);
    const treasury = m.getAccount(0);
    
    // Deploy GovernanceToken (MAGIC)
    const magicToken = m.contract("MagicToken", [owner, treasury]);

    // Return the deployed contract
    return { magicToken };
});

// Usage example:
// npx hardhat ignition deploy ./ignition/modules/DeployGovernanceToken.js --network core_testnet --parameters parameters.json

