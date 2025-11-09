const hre = require("hardhat");

async function main() {
  console.log("Deploying SholoGuti Modular Contracts to Base Sepolia...\n");

  console.log("1. Deploying MainHub...");
  const MainHub = await hre.ethers.getContractFactory("MainHub");
  const mainHub = await MainHub.deploy();
  await mainHub.waitForDeployment();
  const mainHubAddress = await mainHub.getAddress();
  console.log("✓ MainHub deployed to:", mainHubAddress);

  console.log("\n2. Deploying RandomMultiplayer...");
  const RandomMultiplayer = await hre.ethers.getContractFactory("RandomMultiplayer");
  const randomMultiplayer = await RandomMultiplayer.deploy(mainHubAddress);
  await randomMultiplayer.waitForDeployment();
  const randomMultiplayerAddress = await randomMultiplayer.getAddress();
  console.log("✓ RandomMultiplayer deployed to:", randomMultiplayerAddress);

  console.log("\n3. Deploying RoomWithFriends...");
  const RoomWithFriends = await hre.ethers.getContractFactory("RoomWithFriends");
  const roomWithFriends = await RoomWithFriends.deploy(mainHubAddress);
  await roomWithFriends.waitForDeployment();
  const roomWithFriendsAddress = await roomWithFriends.getAddress();
  console.log("✓ RoomWithFriends deployed to:", roomWithFriendsAddress);

  console.log("\n4. Deploying BotMatch...");
  const BotMatch = await hre.ethers.getContractFactory("BotMatch");
  const botMatch = await BotMatch.deploy(mainHubAddress);
  await botMatch.waitForDeployment();
  const botMatchAddress = await botMatch.getAddress();
  console.log("✓ BotMatch deployed to:", botMatchAddress);

  console.log("\n5. Connecting game mode contracts to MainHub...");
  const tx = await mainHub.setGameModeContracts(
    randomMultiplayerAddress,
    roomWithFriendsAddress,
    botMatchAddress
  );
  await tx.wait();
  console.log("✓ Game mode contracts registered with MainHub");

  console.log("\n===========================================");
  console.log("DEPLOYMENT COMPLETE");
  console.log("===========================================");
  console.log("\nContract Addresses:");
  console.log("-------------------------------------------");
  console.log("MainHub:            ", mainHubAddress);
  console.log("RandomMultiplayer:  ", randomMultiplayerAddress);
  console.log("RoomWithFriends:    ", roomWithFriendsAddress);
  console.log("BotMatch:           ", botMatchAddress);
  console.log("===========================================");
  console.log("\nNetwork: Base Sepolia (Chain ID: 84532)");
  console.log("Explorer: https://sepolia.basescan.org/");
  console.log("\nSave these addresses for your frontend integration!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
