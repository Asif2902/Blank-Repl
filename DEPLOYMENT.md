# SholoGuti Modular Smart Contracts - Deployment Information

## Network
- **Network**: Base Sepolia Testnet
- **Chain ID**: 84532 (0x14a34)
- **RPC URL**: https://sepolia.base.org
- **Explorer**: https://sepolia.basescan.org/

## Deployed Contract Addresses

### MainHub (Central Coordinator)
**Address**: `0x6d413385B0383aaB3F69642c7d25dC90414f5f2c`
- Manages player ELO ratings
- Handles platform fees and payouts
- Coordinates all game mode contracts
- [View on Explorer](https://sepolia.basescan.org/address/0x6d413385B0383aaB3F69642c7d25dC90414f5f2c)

### RandomMultiplayer (ELO-based Matchmaking)
**Address**: `0xC0aA4c3b53eaE5128a70f6B24A50bcE392A75db2`
- Random player matchmaking with ELO-based pairing
- Supports betting with automatic payouts
- [View on Explorer](https://sepolia.basescan.org/address/0xC0aA4c3b53eaE5128a70f6B24A50bcE392A75db2)

### RoomWithFriends (Private Rooms)
**Address**: `0xC3dA3Ef175Fa0C960a8066F63BC944c8E05af873`
- Create private rooms to play with specific friends
- Optional betting support
- [View on Explorer](https://sepolia.basescan.org/address/0xC3dA3Ef175Fa0C960a8066F63BC944c8E05af873)

### BotMatch (Play Against AI)
**Address**: `0xd663bF28330f9072037E7894f5021A26FB9Cf53C`
- Play against AI with difficulty levels (Easy, Medium, Hard)
- No betting, practice mode
- [View on Explorer](https://sepolia.basescan.org/address/0xd663bF28330f9072037E7894f5021A26FB9Cf53C)

## Contract Architecture

The contracts follow a modular, Uniswap-style architecture:

1. **Shared Libraries**:
   - `GameTypes.sol`: Common structs, enums, events, and constants
   - `GameErrors.sol`: Custom error definitions
   - `GameUtils.sol`: Utility functions (ELO calculations, room ID generation)

2. **Core Engine**:
   - `GameEngine.sol`: Abstract contract with board logic, move validation, and game rules

3. **Game Mode Contracts** (inherit from GameEngine):
   - `RandomMultiplayer.sol`: Random matchmaking with ELO filtering
   - `RoomWithFriends.sol`: Private room creation and joining
   - `BotMatch.sol`: Single-player games against AI

4. **MainHub**:
   - Central coordinator that manages player data and coordinates between modules
   - Handles all ETH custody and payouts
   - Maintains global state (ELO ratings, platform fees)

## Key Features

✅ **Modular Design**: Each game mode is a separate contract, staying under deployment size limits
✅ **Shared Logic**: Common game rules in GameEngine reduce code duplication
✅ **Centralized State**: MainHub manages player ELO and funds for security
✅ **ELO Rating System**: Fair matchmaking based on skill level
✅ **Automatic Payouts**: Winner/draw payouts processed automatically
✅ **Platform Fees**: 1% fee on bets goes to platform
✅ **Game Timeouts**: Automatic forfeit after 10 minutes of inactivity
✅ **Draw Mechanics**: 69 moves without capture triggers automatic draw
✅ **Bot Difficulty**: Three difficulty levels for AI opponents

## Integration Instructions

### For Frontend Developers

1. Connect to Base Sepolia network
2. Use the MainHub address as the entry point for:
   - Checking player ELO
   - Viewing platform statistics
   - Accessing room lists

3. Use specific game mode contracts for:
   - **RandomMultiplayer**: `createRandomRoom()`, `joinRandomRoom()`
   - **RoomWithFriends**: `createFriendsRoom()`, `joinFriendsRoom()`
   - **BotMatch**: `createBotGame(difficulty)`

4. All contracts emit events for real-time updates:
   - `RoomCreated`
   - `PlayerJoined`
   - `MoveMade`
   - `GameCompleted`
   - `EloUpdated`

### Sample Web3 Code

```javascript
import { ethers } from 'ethers';

// Contract addresses
const MAINHUB_ADDRESS = '0x6d413385B0383aaB3F69642c7d25dC90414f5f2c';
const RANDOM_MULTIPLAYER_ADDRESS = '0xC0aA4c3b53eaE5128a70f6B24A50bcE392A75db2';
const ROOM_WITH_FRIENDS_ADDRESS = '0xC3dA3Ef175Fa0C960a8066F63BC944c8E05af873';
const BOT_MATCH_ADDRESS = '0xd663bF28330f9072037E7894f5021A26FB9Cf53C';

// Connect to contract
const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();
const mainHub = new ethers.Contract(MAINHUB_ADDRESS, MainHub_ABI, signer);
const roomWithFriends = new ethers.Contract(ROOM_WITH_FRIENDS_ADDRESS, RoomWithFriends_ABI, signer);

// Create a room with 0.01 ETH bet
const betAmount = ethers.parseEther("0.01");
const tx = await roomWithFriends.createFriendsRoom(betAmount, { value: betAmount });
await tx.wait();
```

## Game Rules (Preserved from Original)

- **Board**: 37-node graph with specific adjacency connections
- **Pieces**: Each player starts with specific pieces on designated positions
- **Moves**: Adjacent movement or capture by jumping over opponent
- **Mandatory Capture**: Must capture if a capture move is available
- **Chain Captures**: If multiple captures available, must continue until no more captures
- **Win Conditions**:
  - Eliminate all opponent pieces
  - Opponent has no legal moves
  - After 69 moves without capture, player with more pieces wins
- **Timeout**: 10 minutes per move, automatic forfeit on timeout
- **Draw**: Both players can offer draw, or automatic draw if equal pieces after move limit

## Security Notes

- All player funds are held in game mode contracts until game completion
- Platform fees accumulate in MainHub and can only be withdrawn by owner
- Reentrancy guards protect payout functions
- Only registered game mode contracts can call MainHub admin functions
- Private key is stored securely in Replit Secrets

## Gas Optimization

- Optimizer enabled with 200 runs
- Library functions reduce deployment size
- Efficient storage layout
- Batch operations where possible

---

**Deployment Date**: November 9, 2025
**Solidity Version**: 0.8.20
**Compiler**: Hardhat 2.22.6
