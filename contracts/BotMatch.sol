// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameEngine.sol";
import "./GameTypes.sol";
import "./GameErrors.sol";
import "./GameUtils.sol";
import "./MainHub.sol";

contract BotMatch is GameEngine {
    MainHub public hub;
    
    constructor(address _hub) {
        hub = MainHub(_hub);
    }
    
    function createBotGame(GameTypes.BotDifficulty difficulty) external returns (string memory) {
        if (difficulty == GameTypes.BotDifficulty.None) revert GameErrors.InvalidBotDifficulty();
        
        string memory roomId = GameUtils.generateRoomId(block.timestamp, msg.sender);
        GameTypes.Room storage room = rooms[roomId];
        
        room.roomId = roomId;
        room.roomType = GameTypes.RoomType.Bot;
        room.player1 = GameTypes.Player(msg.sender, hub.getOrInitElo(msg.sender), true);
        room.player2 = GameTypes.Player(address(this), 400, true);
        room.betAmount = 0;
        room.botDifficulty = difficulty;
        room.payoutCompleted = true;
        
        hub.registerRoom(roomId, msg.sender, address(this));
        _startGame(roomId);
        
        emit GameTypes.RoomCreated(roomId, GameTypes.RoomType.Bot, msg.sender, 0);
        return roomId;
    }
    
    function _startGame(string memory roomId) private {
        GameTypes.Room storage room = rooms[roomId];
        room.status = GameTypes.GameStatus.Active;
        room.currentTurn = room.player1.playerAddress;
        room.lastMoveTime = block.timestamp;
        
        _initializeGameBoard(roomId);
        hub.addToActiveRooms(roomId);
        
        emit GameTypes.PlayerJoined(roomId, room.player2.playerAddress);
    }
    
    function makeMove(string memory roomId, uint8 from, uint8 to) external {
        GameTypes.Room storage room = rooms[roomId];
        
        if (room.status != GameTypes.GameStatus.Active) revert GameErrors.GameNotActive();
        if (msg.sender != room.currentTurn) revert GameErrors.NotYourTurn();
        
        int8 piece = room.board[from];
        if (piece == 0) revert GameErrors.NoPieceAtPosition();
        if (piece != 1) revert GameErrors.NotYourPiece();
        
        (bool isValid, GameTypes.MoveType moveType) = _validateMove(roomId, from, to, piece);
        if (!isValid) revert GameErrors.InvalidMove();
        
        bool captureAvailable = _hasCaptureMove(roomId, piece);
        if (captureAvailable && moveType != GameTypes.MoveType.Capture) {
            revert GameErrors.MustCaptureWhenAvailable();
        }
        
        _executeMove(roomId, from, to, moveType);
        
        gameHistory[roomId].push(GameTypes.Move(from, to, moveType, block.timestamp));
        room.moveCount++;
        
        if (moveType == GameTypes.MoveType.Capture) {
            room.movesWithoutCapture = 0;
            
            if (_hasChainCapture(roomId, to, piece)) {
                emit GameTypes.MoveMade(roomId, msg.sender, from, to, moveType);
                return;
            }
        } else {
            room.movesWithoutCapture++;
        }
        
        if (_checkWinCondition(roomId)) {
            return;
        }
        
        if (room.movesWithoutCapture >= GameTypes.MOVE_LIMIT_FOR_DRAW) {
            _handleDrawByMoveLimit(roomId);
            return;
        }
        
        room.currentTurn = address(this);
        room.lastMoveTime = block.timestamp;
        
        emit GameTypes.MoveMade(roomId, msg.sender, from, to, moveType);
        
        _makeBotMove(roomId);
    }
    
    function _makeBotMove(string memory roomId) private {
        GameTypes.Room storage room = rooms[roomId];
        
        uint8 bestFrom = 0;
        uint8 bestTo = 0;
        bool foundMove = false;
        
        for (uint8 pos = 0; pos < 37; pos++) {
            if (room.board[pos] == 2) {
                uint8[] memory adjacent = adjacentNodes[pos];
                for (uint i = 0; i < adjacent.length; i++) {
                    (bool isValid, GameTypes.MoveType moveType) = _validateMove(roomId, pos, adjacent[i], 2);
                    if (isValid && moveType == GameTypes.MoveType.Capture) {
                        bestFrom = pos;
                        bestTo = adjacent[i];
                        foundMove = true;
                        break;
                    }
                }
                if (foundMove) break;
            }
        }
        
        if (!foundMove) {
            for (uint8 pos = 0; pos < 37; pos++) {
                if (room.board[pos] == 2) {
                    uint8[] memory adjacent = adjacentNodes[pos];
                    for (uint i = 0; i < adjacent.length; i++) {
                        (bool isValid,) = _validateMove(roomId, pos, adjacent[i], 2);
                        if (isValid) {
                            bestFrom = pos;
                            bestTo = adjacent[i];
                            foundMove = true;
                            break;
                        }
                    }
                    if (foundMove) break;
                }
            }
        }
        
        if (foundMove) {
            (, GameTypes.MoveType moveType) = _validateMove(roomId, bestFrom, bestTo, 2);
            _executeMove(roomId, bestFrom, bestTo, moveType);
            gameHistory[roomId].push(GameTypes.Move(bestFrom, bestTo, moveType, block.timestamp));
            room.moveCount++;
            
            if (moveType != GameTypes.MoveType.Capture) {
                room.movesWithoutCapture++;
            }
            
            emit GameTypes.MoveMade(roomId, address(this), bestFrom, bestTo, moveType);
            
            if (!_checkWinCondition(roomId)) {
                room.currentTurn = room.player1.playerAddress;
                room.lastMoveTime = block.timestamp;
            }
        }
    }
    
    function resign(string memory roomId) external {
        GameTypes.Room storage room = rooms[roomId];
        if (room.status != GameTypes.GameStatus.Active) revert GameErrors.GameNotActive();
        if (msg.sender != room.player1.playerAddress) revert GameErrors.NotAPlayer();
        
        endGame(roomId, address(this), GameTypes.GameStatus.Resigned);
        emit GameTypes.GameResigned(roomId, msg.sender, address(this));
    }
    
    function _handleDrawByMoveLimit(string memory roomId) private {
        GameTypes.Room storage room = rooms[roomId];
        
        (uint8 player1Pieces, uint8 player2Pieces) = _countPieces(roomId);
        
        address winner;
        if (player1Pieces > player2Pieces) {
            winner = room.player1.playerAddress;
        } else if (player2Pieces > player1Pieces) {
            winner = address(this);
        } else {
            winner = address(0);
        }
        
        endGame(roomId, winner, GameTypes.GameStatus.Completed);
    }
    
    function _beforeEndGame(string memory roomId, address winner, GameTypes.GameStatus status) internal override {
        endGame(roomId, winner, status);
    }
    
    function endGame(string memory roomId, address winner, GameTypes.GameStatus status) public {
        GameTypes.Room storage room = rooms[roomId];
        if (room.payoutCompleted) revert GameErrors.PayoutAlreadyCompleted();
        
        room.status = status;
        room.winner = winner;
        room.payoutCompleted = true;
        
        hub.removeFromActiveRooms(roomId);
        emit GameTypes.GameCompleted(roomId, winner, status, room.player1.elo, 400);
    }
    
    function getRoomDetails(string memory roomId) external view returns (GameTypes.RoomData memory) {
        GameTypes.Room storage room = rooms[roomId];
        (uint8 p1Count, uint8 p2Count) = _countPieces(roomId);
        
        return GameTypes.RoomData({
            roomId: room.roomId,
            roomType: room.roomType,
            player1: room.player1.playerAddress,
            player2: room.player2.playerAddress,
            player1Elo: room.player1.elo,
            player2Elo: room.player2.elo,
            status: room.status,
            currentTurn: room.currentTurn,
            moveCount: room.moveCount,
            betAmount: room.betAmount,
            movesWithoutCapture: room.movesWithoutCapture,
            lastMoveTime: room.lastMoveTime,
            winner: room.winner,
            drawOfferedBy1: room.drawOfferedBy1,
            drawOfferedBy2: room.drawOfferedBy2,
            botDifficulty: room.botDifficulty,
            player1PieceCount: p1Count,
            player2PieceCount: p2Count
        });
    }
}
