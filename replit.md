# SholoGuti Modular Smart Contracts

## Overview

SholoGuti is a blockchain-based board game platform deployed on Base Sepolia testnet. The system implements a traditional South Asian strategy game (similar to checkers/draughts) using Solidity smart contracts. The platform supports multiple game modes including random matchmaking with ELO-based pairing, private rooms for playing with friends, and AI bot matches for practice. The architecture follows a modular design pattern inspired by Uniswap, with a central coordinator (MainHub) managing player ratings, fees, and payouts, while individual game mode contracts handle specific gameplay logic.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Core Architecture Pattern

**Problem**: Need a flexible, extensible game platform that supports multiple game modes while maintaining consistent player statistics and payout mechanisms.

**Solution**: Modular hub-and-spoke architecture where MainHub acts as the central coordinator and individual game mode contracts handle specific gameplay logic.

**Design Principles**:
- **Separation of Concerns**: Shared libraries (GameTypes, GameErrors, GameUtils) provide common functionality, while GameEngine provides core game logic that all game modes inherit
- **Single Source of Truth**: MainHub maintains all ELO ratings and handles all financial transactions, preventing inconsistencies across game modes
- **Extensibility**: New game modes can be added by creating new contracts that inherit from GameEngine and register with MainHub

**Alternatives Considered**: Monolithic contract approach was rejected due to code size limitations and reduced flexibility for adding new game modes.

**Pros**:
- Easy to add new game modes without modifying existing contracts
- Clear separation of financial logic (MainHub) from game logic (individual modes)
- Shared libraries reduce code duplication

**Cons**:
- More complex deployment process with multiple contracts
- Cross-contract calls add gas overhead
- Requires careful coordination between MainHub and game mode contracts

### Smart Contract Components

**1. Shared Libraries**

- **GameTypes.sol**: Defines common data structures (Room, Move, Player), enums (GameStatus, RoomType, BotDifficulty), events (GameStarted, MoveMade, GameEnded), and constants used across all contracts
- **GameErrors.sol**: Centralizes custom error definitions for consistent error handling
- **GameUtils.sol**: Provides utility functions including ELO calculation algorithms and room ID generation

**2. Core Game Engine (GameEngine.sol)**

**Purpose**: Abstract contract providing fundamental game board logic and move validation.

**Key Features**:
- 23-node board representation with adjacency mapping
- Move validation (regular moves and capture moves)
- Win condition detection
- Game state management
- Move history tracking

**Design Decision**: Made abstract to enforce that it cannot be deployed standalone - must be inherited by game mode contracts.

**3. MainHub Contract**

**Purpose**: Central coordinator managing cross-game-mode concerns.

**Responsibilities**:
- Player ELO rating management (starts at 1000, updated after each game)
- Platform fee collection (1% of bet amount)
- Payout distribution to winners
- Game mode contract registration and authorization
- Cross-game statistics tracking

**Key Design Decisions**:
- Only registered game mode contracts can update ELO ratings (prevents unauthorized manipulation)
- All financial transactions flow through MainHub (prevents payout inconsistencies)
- Owner-controlled game mode registration (allows platform governance)

**4. Game Mode Contracts**

All game modes inherit from GameEngine and implement specific matchmaking/room logic:

**RandomMultiplayer.sol**:
- ELO-based matchmaking (players matched within ±200 ELO range)
- Public matchmaking queue
- Betting support with automatic winner payouts
- Timeout mechanism (15 minutes per move)

**RoomWithFriends.sol**:
- Private room creation with unique room IDs
- Invitation-based joining (specific friend must join)
- Optional betting
- Room creator controls betting amount

**BotMatch.sol**:
- Single-player practice mode
- Three difficulty levels (Easy, Medium, Hard)
- No betting or ELO changes
- Bot moves generated on-chain (deterministic based on block data)

### Financial Flow

**Betting Mechanism**:
1. Players send ETH when creating/joining games
2. MainHub holds funds in escrow during gameplay
3. Upon game completion:
   - 1% platform fee deducted
   - Remaining pot sent to winner
   - Draw results in full refunds

**ELO System**:
- K-factor of 32 for rating adjustments
- Expected score calculated using standard ELO formula
- Updates triggered by game mode contracts calling MainHub
- Bot matches don't affect ELO ratings

### Board Game Logic

**Board Structure**:
- 23 interconnected nodes in traditional SholoGuti layout
- Each node can be empty or contain a piece (Player 1 or Player 2)
- Adjacency mapping defines valid move paths

**Move Types**:
- **Simple Move**: Move piece to adjacent empty node
- **Capture Move**: Jump over opponent's piece to empty node beyond, removing opponent's piece

**Win Conditions**:
- Capture all opponent pieces, OR
- Block opponent from making any legal moves

**Game Rules Enforcement**:
- Mandatory captures (must capture if capture move available)
- Turn-based play with timeout enforcement
- Move validation against board state and adjacency rules

### Deployment Architecture

**Network**: Base Sepolia Testnet (Chain ID: 84532)

**Deployment Sequence**:
1. Deploy MainHub first (no dependencies)
2. Deploy game mode contracts (each references MainHub address)
3. Register game mode contracts with MainHub via setGameModeContracts()

**Configuration**: Uses Hardhat with ethers.js for deployment and testing. Environment-based private key management via dotenv.

## External Dependencies

### Blockchain Infrastructure

- **Base Sepolia Testnet**: Ethereum Layer 2 scaling solution
  - RPC Endpoint: https://sepolia.base.org
  - Block Explorer: https://sepolia.basescan.org
  - Lower gas costs compared to Ethereum mainnet
  - Fast block times for responsive gameplay

### Development Tools

- **Hardhat**: Ethereum development environment
  - Smart contract compilation
  - Testing framework
  - Deployment scripts
  - Network configuration management

- **OpenZeppelin Contracts v5.4.0**: Industry-standard smart contract library (currently included but not actively used in deployed contracts - available for future features like access control enhancements)

- **Ethers.js**: Ethereum library for contract interaction (bundled with Hardhat toolbox)

### Node.js Ecosystem

- **dotenv**: Environment variable management for secure private key handling
- **@nomicfoundation/hardhat-toolbox**: Comprehensive Hardhat plugin bundle including testing utilities, ethers.js integration, and verification tools

### On-Chain Dependencies

**No external smart contract dependencies**: All game logic is self-contained within the deployed contracts. The system does not rely on oracles, external price feeds, or other smart contract protocols.

**Future Integration Opportunities** (not currently implemented):
- Chainlink VRF for verifiable random bot moves
- Token-based rewards system
- NFT integration for game achievements

## Current Deployment

**Latest Deployment Date**: November 9, 2025
**Network**: Base Sepolia (Chain ID: 84532)

**Deployed Contract Addresses**:
- MainHub: `0x145C788562F44bD093f573E398fcB40AB50241CF`
- RandomMultiplayer: `0xB78D15ee835692f58bF4579a1154cd1D978139b5`
- RoomWithFriends: `0x9F34Be6dF8c7A1dB9728e662eeE75c60A2DD4833`
- BotMatch: `0xB9B3357c2b999A89728624C9dc13b19D37D83B58`

All contracts successfully deployed and integrated. See DEPLOYMENT.md for complete deployment details and integration instructions.

## Recent Changes

**Critical Bug Fix (November 9, 2025)**: Fixed capture move logic in GameEngine.sol
- **Issue**: The original `_executeMove` used `(from + to) / 2` to find captured pieces, which didn't work with SholoGuti's non-sequential node numbering (e.g., capturing from node 8→13 should remove node 9, but calculation gave node 10)
- **Fix**: Implemented `_findCapturedPiece()` that correctly identifies the opponent piece by finding the common neighbor between source and destination nodes that contains an opponent piece
- **Impact**: All capture moves now correctly remove the opponent's piece, maintaining game integrity
- **Verification**: Architect-reviewed and approved; contracts redeployed with fix