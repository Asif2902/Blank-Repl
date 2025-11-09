// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library GameTypes {
    uint256 constant STARTING_ELO = 400;
    uint256 constant ELO_K_FACTOR = 32;
    uint256 constant ELO_RANGE = 200;
    uint256 constant PLATFORM_FEE_PERCENT = 1;
    uint256 constant GAME_TIMEOUT = 10 minutes;
    uint256 constant MOVE_LIMIT_FOR_DRAW = 69;
    
    enum GameStatus { Waiting, Active, Completed, Resigned, DrawAccepted, Timeout }
    enum RoomType { Friends, Random, Bot }
    enum BotDifficulty { None, Easy, Medium, Hard }
    enum MoveType { Normal, Capture }
    
    struct Player {
        address playerAddress;
        uint256 elo;
        bool hasJoined;
    }
    
    struct Room {
        string roomId;
        RoomType roomType;
        Player player1;
        Player player2;
        uint256 betAmount;
        GameStatus status;
        address currentTurn;
        uint256 moveCount;
        uint256 movesWithoutCapture;
        uint256 lastMoveTime;
        address winner;
        bool drawOfferedBy1;
        bool drawOfferedBy2;
        BotDifficulty botDifficulty;
        mapping(uint8 => int8) board;
        bool payoutCompleted;
    }
    
    struct RoomData {
        string roomId;
        RoomType roomType;
        address player1;
        address player2;
        uint256 player1Elo;
        uint256 player2Elo;
        uint256 betAmount;
        GameStatus status;
        address currentTurn;
        uint256 moveCount;
        uint256 movesWithoutCapture;
        uint256 lastMoveTime;
        address winner;
        bool drawOfferedBy1;
        bool drawOfferedBy2;
        BotDifficulty botDifficulty;
        uint8 player1PieceCount;
        uint8 player2PieceCount;
    }
    
    struct Move {
        uint8 from;
        uint8 to;
        MoveType moveType;
        uint256 timestamp;
    }
    
    event RoomCreated(string indexed roomId, RoomType roomType, address indexed creator, uint256 betAmount);
    event PlayerJoined(string indexed roomId, address indexed player);
    event MoveMade(string indexed roomId, address indexed player, uint8 from, uint8 to, MoveType moveType);
    event GameCompleted(string indexed roomId, address indexed winner, GameStatus status, uint256 player1NewElo, uint256 player2NewElo);
    event DrawOffered(string indexed roomId, address indexed offerer);
    event DrawAccepted(string indexed roomId);
    event GameResigned(string indexed roomId, address indexed resignee, address indexed winner);
    event EloUpdated(address indexed player, uint256 oldElo, uint256 newElo);
    event PayoutProcessed(string indexed roomId, address indexed recipient, uint256 amount);
}
