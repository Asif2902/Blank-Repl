// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameTypes.sol";
import "./GameUtils.sol";

interface IGameMode {
    function endGame(string memory roomId, address winner, GameTypes.GameStatus status) external;
    function getRoomDetails(string memory roomId) external view returns (GameTypes.RoomData memory);
}

contract MainHub {
    using GameTypes for *;
    
    mapping(address => uint256) public playerElo;
    mapping(address => bool) public hasPlayed;
    mapping(address => string[]) private playerRooms;
    
    string[] private activeRooms;
    string[] private waitingRooms;
    
    address public owner;
    uint256 public platformBalance;
    uint256 public totalGamesPlayed;
    uint256 public totalBetsProcessed;
    
    address public randomMultiplayerContract;
    address public roomWithFriendsContract;
    address public botMatchContract;
    
    mapping(string => address) public roomToContract;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyGameMode() {
        require(
            msg.sender == randomMultiplayerContract ||
            msg.sender == roomWithFriendsContract ||
            msg.sender == botMatchContract,
            "Only game mode contracts"
        );
        _;
    }
    
    function setGameModeContracts(
        address _randomMultiplayer,
        address _roomWithFriends,
        address _botMatch
    ) external onlyOwner {
        randomMultiplayerContract = _randomMultiplayer;
        roomWithFriendsContract = _roomWithFriends;
        botMatchContract = _botMatch;
    }
    
    function getOrInitElo(address player) external returns (uint256) {
        if (!hasPlayed[player]) {
            playerElo[player] = GameTypes.STARTING_ELO;
            hasPlayed[player] = true;
        }
        return playerElo[player];
    }
    
    function getPlayerElo(address player) external view returns (uint256) {
        if (!hasPlayed[player]) return GameTypes.STARTING_ELO;
        return playerElo[player];
    }
    
    function registerRoom(string memory roomId, address playerAddress, address gameMode) external onlyGameMode {
        roomToContract[roomId] = gameMode;
        playerRooms[playerAddress].push(roomId);
    }
    
    function addToWaitingRooms(string memory roomId) external onlyGameMode {
        waitingRooms.push(roomId);
    }
    
    function removeFromWaitingRooms(string memory roomId) external onlyGameMode {
        for (uint i = 0; i < waitingRooms.length; i++) {
            if (keccak256(bytes(waitingRooms[i])) == keccak256(bytes(roomId))) {
                waitingRooms[i] = waitingRooms[waitingRooms.length - 1];
                waitingRooms.pop();
                break;
            }
        }
    }
    
    function addToActiveRooms(string memory roomId) external onlyGameMode {
        activeRooms.push(roomId);
    }
    
    function removeFromActiveRooms(string memory roomId) external onlyGameMode {
        for (uint i = 0; i < activeRooms.length; i++) {
            if (keccak256(bytes(activeRooms[i])) == keccak256(bytes(roomId))) {
                activeRooms[i] = activeRooms[activeRooms.length - 1];
                activeRooms.pop();
                break;
            }
        }
    }
    
    function addPlayerRoom(address player, string memory roomId) external onlyGameMode {
        playerRooms[player].push(roomId);
    }
    
    function updateElo(
        address player1,
        address player2,
        uint256 elo1,
        uint256 elo2,
        address winner
    ) external onlyGameMode returns (uint256 newElo1, uint256 newElo2) {
        (newElo1, newElo2) = GameUtils.calculateEloChange(elo1, elo2, winner, player1, player2);
        
        playerElo[player1] = newElo1;
        playerElo[player2] = newElo2;
        
        emit GameTypes.EloUpdated(player1, elo1, newElo1);
        emit GameTypes.EloUpdated(player2, elo2, newElo2);
    }
    
    function processPayout(
        string memory roomId,
        address player1,
        address player2,
        uint256 betAmount,
        address winner,
        bool player2Joined
    ) external payable onlyGameMode {
        totalGamesPlayed++;
        
        if (betAmount > 0 && player2Joined) {
            totalBetsProcessed += betAmount * 2;
            uint256 totalPot = betAmount * 2;
            uint256 platformFee = (totalPot * GameTypes.PLATFORM_FEE_PERCENT) / 100;
            uint256 netPot = totalPot - platformFee;
            
            platformBalance += platformFee;
            
            if (winner != address(0)) {
                payable(winner).transfer(netPot);
                emit GameTypes.PayoutProcessed(roomId, winner, netPot);
            } else {
                uint256 splitAmount = netPot / 2;
                payable(player1).transfer(splitAmount);
                payable(player2).transfer(splitAmount);
                emit GameTypes.PayoutProcessed(roomId, player1, splitAmount);
                emit GameTypes.PayoutProcessed(roomId, player2, splitAmount);
            }
        } else if (betAmount > 0 && !player2Joined) {
            payable(player1).transfer(betAmount);
            emit GameTypes.PayoutProcessed(roomId, player1, betAmount);
        }
    }
    
    function getWaitingRooms() external view returns (string[] memory) {
        return waitingRooms;
    }
    
    function getActiveRooms() external view returns (string[] memory) {
        return activeRooms;
    }
    
    function getPlayerRooms(address player) external view returns (string[] memory) {
        return playerRooms[player];
    }
    
    function getPlatformStats() external view returns (
        uint256 totalPlatformFees,
        uint256 activeGamesCount,
        uint256 waitingGamesCount,
        uint256 totalGames,
        uint256 totalBets
    ) {
        return (
            platformBalance,
            activeRooms.length,
            waitingRooms.length,
            totalGamesPlayed,
            totalBetsProcessed
        );
    }
    
    function withdrawPlatformFees() external onlyOwner {
        require(platformBalance > 0, "No fees to withdraw");
        uint256 amount = platformBalance;
        platformBalance = 0;
        payable(owner).transfer(amount);
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }
}
