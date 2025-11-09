// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameEngine.sol";
import "./GameTypes.sol";
import "./GameErrors.sol";
import "./GameUtils.sol";
import "./MainHub.sol";

contract RoomWithFriends is GameEngine {
    MainHub public hub;
    
    constructor(address _hub) {
        hub = MainHub(_hub);
    }
    
    function createFriendsRoom(uint256 betAmount) external payable returns (string memory) {
        if (msg.value != betAmount) revert GameErrors.IncorrectBetAmount();
        if (betAmount > 0 && msg.value == 0) revert GameErrors.IncorrectBetAmount();
        
        string memory roomId = GameUtils.generateRoomId(block.timestamp, msg.sender);
        GameTypes.Room storage room = rooms[roomId];
        
        room.roomId = roomId;
        room.roomType = GameTypes.RoomType.Friends;
        room.player1 = GameTypes.Player(msg.sender, hub.getOrInitElo(msg.sender), true);
        room.betAmount = betAmount;
        room.status = GameTypes.GameStatus.Waiting;
        room.botDifficulty = GameTypes.BotDifficulty.None;
        room.payoutCompleted = false;
        
        hub.registerRoom(roomId, msg.sender, address(this));
        hub.addToWaitingRooms(roomId);
        
        emit GameTypes.RoomCreated(roomId, GameTypes.RoomType.Friends, msg.sender, betAmount);
        return roomId;
    }
    
    function joinFriendsRoom(string memory roomId) external payable {
        GameTypes.Room storage room = rooms[roomId];
        if (room.status != GameTypes.GameStatus.Waiting) revert GameErrors.RoomNotAvailable();
        if (room.roomType != GameTypes.RoomType.Friends) revert GameErrors.NotFriendsRoom();
        if (room.player2.hasJoined) revert GameErrors.RoomIsFull();
        if (!room.player1.hasJoined) revert GameErrors.InvalidRoom();
        if (msg.sender == room.player1.playerAddress) revert GameErrors.CannotPlayYourself();
        if (msg.value != room.betAmount) revert GameErrors.IncorrectBetAmount();
        
        room.player2 = GameTypes.Player(msg.sender, hub.getOrInitElo(msg.sender), true);
        hub.addPlayerRoom(msg.sender, roomId);
        _startGame(roomId);
    }
    
    function _startGame(string memory roomId) private {
        GameTypes.Room storage room = rooms[roomId];
        room.status = GameTypes.GameStatus.Active;
        room.currentTurn = room.player1.playerAddress;
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
    
    receive() external payable {}
}
