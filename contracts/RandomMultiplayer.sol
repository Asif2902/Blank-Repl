
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameEngine.sol";
import "./GameTypes.sol";
import "./GameErrors.sol";
import "./GameUtils.sol";
import "./MainHub.sol";

contract RandomMultiplayer is GameEngine {
    MainHub public hub;
    
    constructor(address _hub) {
        hub = MainHub(_hub);
    }
    
    // Single function to find/create and join a room
    function findOrCreateRoom() external returns (string memory) {
        // Try to find an available waiting room with similar ELO
        string[] memory waiting = hub.getWaitingRooms();
        uint256 playerElo = hub.getOrInitElo(msg.sender);
        
        // Try to join existing waiting room
        for (uint i = 0; i < waiting.length; i++) {
            string memory roomId = waiting[i];
            GameTypes.Room storage room = rooms[roomId];
            
            // Skip if room is not in waiting state or wrong type
            if (room.status != GameTypes.GameStatus.Waiting || 
                room.roomType != GameTypes.RoomType.Random) {
                continue;
            }
            
            // Skip if player trying to join their own room
            if (room.player1.playerAddress == msg.sender) {
                continue;
            }
            
            // Check ELO difference
            uint256 eloDiff = playerElo > room.player1.elo ? 
                playerElo - room.player1.elo : 
                room.player1.elo - playerElo;
            
            if (eloDiff <= GameTypes.ELO_RANGE) {
                // Join this room
                room.player2 = GameTypes.Player(msg.sender, playerElo, true);
                hub.addPlayerRoom(msg.sender, roomId);
                _startGame(roomId);
                return roomId;
            }
        }
        
        // No suitable room found, create a new one
        string memory roomId = GameUtils.generateRoomId(block.timestamp, msg.sender);
        GameTypes.Room storage room = rooms[roomId];
        
        room.roomId = roomId;
        room.roomType = GameTypes.RoomType.Random;
        room.player1 = GameTypes.Player(msg.sender, playerElo, true);
        room.betAmount = 0;
        room.status = GameTypes.GameStatus.Waiting;
        room.botDifficulty = GameTypes.BotDifficulty.None;
        room.payoutCompleted = false;
        
        hub.registerRoom(roomId, msg.sender, address(this));
        hub.addToWaitingRooms(roomId);
        
        emit GameTypes.RoomCreated(roomId, GameTypes.RoomType.Random, msg.sender, 0);
        return roomId;
    }
    
    function _startGame(string memory roomId) private {
        GameTypes.Room storage room = rooms[roomId];
        room.status = GameTypes.GameStatus.Active;
        
        // Randomly determine who goes first using block data
        uint256 randomValue = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            room.player1.playerAddress,
            room.player2.playerAddress
        )));
        
        // If random value is even, player1 goes first, otherwise player2
        if (randomValue % 2 == 0) {
            room.currentTurn = room.player1.playerAddress;
        } else {
            room.currentTurn = room.player2.playerAddress;
        }
        
        room.lastMoveTime = block.timestamp;
        
        _initializeGameBoard(roomId);
        hub.removeFromWaitingRooms(roomId);
        hub.addToActiveRooms(roomId);
        
        emit GameTypes.PlayerJoined(roomId, room.player2.playerAddress);
    }
    
    function makeMove(string memory roomId, uint8 from, uint8 to) external {
        GameTypes.Room storage room = rooms[roomId];
        
        if (room.status == GameTypes.GameStatus.Active && block.timestamp > room.lastMoveTime + GameTypes.GAME_TIMEOUT) {
            address winner = (room.currentTurn == room.player1.playerAddress) ? 
                room.player2.playerAddress : room.player1.playerAddress;
            endGame(roomId, winner, GameTypes.GameStatus.Timeout);
            revert GameErrors.GameTimedOut();
        }
        
        if (room.status != GameTypes.GameStatus.Active) revert GameErrors.GameNotActive();
        if (msg.sender != room.currentTurn) revert GameErrors.NotYourTurn();
        
        int8 piece = room.board[from];
        if (piece == 0) revert GameErrors.NoPieceAtPosition();
        
        if (msg.sender == room.player1.playerAddress) {
            if (piece != 1) revert GameErrors.NotYourPiece();
        } else {
            if (piece != 2) revert GameErrors.NotYourPiece();
        }
        
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
            
            // Chain capture: same piece must continue if more captures available
            if (_hasChainCapture(roomId, to, piece)) {
                emit GameTypes.MoveMade(roomId, msg.sender, from, to, moveType);
                // Don't switch turns - same player continues with same piece
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
        
        room.currentTurn = (room.currentTurn == room.player1.playerAddress) ? 
            room.player2.playerAddress : room.player1.playerAddress;
        room.lastMoveTime = block.timestamp;
        
        emit GameTypes.MoveMade(roomId, msg.sender, from, to, moveType);
    }
    
    function offerDraw(string memory roomId) external {
        GameTypes.Room storage room = rooms[roomId];
        if (room.status != GameTypes.GameStatus.Active) revert GameErrors.GameNotActive();
        if (msg.sender != room.player1.playerAddress && msg.sender != room.player2.playerAddress) {
            revert GameErrors.NotAPlayer();
        }
        
        if (msg.sender == room.player1.playerAddress) {
            room.drawOfferedBy1 = true;
            if (room.drawOfferedBy2) {
                endGame(roomId, address(0), GameTypes.GameStatus.DrawAccepted);
                emit GameTypes.DrawAccepted(roomId);
            } else {
                emit GameTypes.DrawOffered(roomId, msg.sender);
            }
        } else {
            room.drawOfferedBy2 = true;
            if (room.drawOfferedBy1) {
                endGame(roomId, address(0), GameTypes.GameStatus.DrawAccepted);
                emit GameTypes.DrawAccepted(roomId);
            } else {
                emit GameTypes.DrawOffered(roomId, msg.sender);
            }
        }
    }
    
    function resign(string memory roomId) external {
        GameTypes.Room storage room = rooms[roomId];
        if (room.status != GameTypes.GameStatus.Active) revert GameErrors.GameNotActive();
        if (msg.sender != room.player1.playerAddress && msg.sender != room.player2.playerAddress) {
            revert GameErrors.NotAPlayer();
        }
        
        address winner = (msg.sender == room.player1.playerAddress) ? 
            room.player2.playerAddress : room.player1.playerAddress;
        
        endGame(roomId, winner, GameTypes.GameStatus.Resigned);
        emit GameTypes.GameResigned(roomId, msg.sender, winner);
    }
    
    function _handleDrawByMoveLimit(string memory roomId) private {
        GameTypes.Room storage room = rooms[roomId];
        
        (uint8 player1Pieces, uint8 player2Pieces) = _countPieces(roomId);
        
        address winner;
        if (player1Pieces > player2Pieces) {
            winner = room.player1.playerAddress;
        } else if (player2Pieces > player1Pieces) {
            winner = room.player2.playerAddress;
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
        
        uint256 newElo1 = room.player1.elo;
        uint256 newElo2 = room.player2.elo;
        
        // Only update ELO if both players joined (actual match happened)
        if (room.player1.hasJoined && room.player2.hasJoined) {
            (newElo1, newElo2) = hub.updateElo(
                room.player1.playerAddress,
                room.player2.playerAddress,
                room.player1.elo,
                room.player2.elo,
                winner
            );
        }
        
        if (room.betAmount > 0) {
            hub.processPayout{value: address(this).balance}(
                roomId,
                room.player1.playerAddress,
                room.player2.playerAddress,
                room.betAmount,
                winner,
                room.player2.hasJoined
            );
        }
        
        hub.removeFromActiveRooms(roomId);
        emit GameTypes.GameCompleted(roomId, winner, status, newElo1, newElo2);
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
