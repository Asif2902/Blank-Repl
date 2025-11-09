// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameTypes.sol";
import "./GameErrors.sol";

abstract contract GameEngine {
    using GameTypes for *;
    
    mapping(uint8 => uint8[]) public adjacentNodes;
    mapping(string => GameTypes.Room) internal rooms;
    mapping(string => GameTypes.Move[]) public gameHistory;
    
    constructor() {
        _initializeBoard();
    }
    
    function _initializeBoard() private {
        adjacentNodes[0] = [1, 5];
        adjacentNodes[1] = [0, 6];
        adjacentNodes[2] = [3, 7];
        adjacentNodes[3] = [2, 4, 7, 8];
        adjacentNodes[4] = [3, 5, 8, 9];
        adjacentNodes[5] = [0, 4, 6, 9, 10];
        adjacentNodes[6] = [1, 5, 10];
        adjacentNodes[7] = [2, 3, 8, 12];
        adjacentNodes[8] = [3, 4, 7, 9, 12, 13];
        adjacentNodes[9] = [4, 5, 8, 10, 13, 14];
        adjacentNodes[10] = [5, 6, 9, 14];
        adjacentNodes[12] = [7, 8, 13, 17];
        adjacentNodes[13] = [8, 9, 12, 14, 17, 18];
        adjacentNodes[14] = [9, 10, 13, 18, 19];
        adjacentNodes[17] = [12, 13, 18, 22];
        adjacentNodes[18] = [13, 14, 17, 19, 22, 23];
        adjacentNodes[19] = [14, 18, 23];
        adjacentNodes[22] = [17, 18, 23, 27];
        adjacentNodes[23] = [18, 19, 22, 24, 27, 28];
        adjacentNodes[24] = [23, 28];
        adjacentNodes[27] = [22, 23, 28, 32];
        adjacentNodes[28] = [23, 24, 27, 29, 32, 33];
        adjacentNodes[29] = [28, 30, 33, 34];
        adjacentNodes[30] = [29, 31, 34, 35];
        adjacentNodes[31] = [30, 35];
        adjacentNodes[32] = [27, 28, 33];
        adjacentNodes[33] = [28, 29, 32, 34];
        adjacentNodes[34] = [29, 30, 33, 35, 36];
        adjacentNodes[35] = [30, 31, 34, 36];
        adjacentNodes[36] = [34, 35];
    }
    
    function _initializeGameBoard(string memory roomId) internal {
        GameTypes.Room storage room = rooms[roomId];
        
        room.board[22] = 1; room.board[23] = 1; room.board[24] = 1;
        room.board[27] = 1; room.board[28] = 1; room.board[29] = 1;
        room.board[30] = 1; room.board[31] = 1;
        room.board[32] = 1; room.board[33] = 1;
        
        room.board[0] = 2; room.board[1] = 2;
        room.board[2] = 2; room.board[3] = 2; room.board[4] = 2;
        room.board[5] = 2; room.board[6] = 2;
        room.board[7] = 2; room.board[8] = 2; room.board[9] = 2;
        room.board[10] = 2;
    }
    
    function _validateMove(string memory roomId, uint8 from, uint8 to, int8 piece) 
        internal view returns (bool, GameTypes.MoveType) {
        GameTypes.Room storage room = rooms[roomId];
        
        if (room.board[to] != 0) {
            return (false, GameTypes.MoveType.Normal);
        }
        
        bool isAdjacent = false;
        uint8[] memory adjacent = adjacentNodes[from];
        for (uint i = 0; i < adjacent.length; i++) {
            if (adjacent[i] == to) {
                isAdjacent = true;
                break;
            }
        }
        
        if (isAdjacent) {
            return (true, GameTypes.MoveType.Normal);
        }
        
        int8 opponentPiece = (piece == 1) ? int8(2) : int8(1);
        
        for (uint i = 0; i < adjacent.length; i++) {
            uint8 middle = adjacent[i];
            if (room.board[middle] == opponentPiece) {
                uint8[] memory middleAdjacent = adjacentNodes[middle];
                for (uint j = 0; j < middleAdjacent.length; j++) {
                    if (middleAdjacent[j] == to && middleAdjacent[j] != from) {
                        return (true, GameTypes.MoveType.Capture);
                    }
                }
            }
        }
        
        return (false, GameTypes.MoveType.Normal);
    }
    
    function _executeMove(string memory roomId, uint8 from, uint8 to, GameTypes.MoveType moveType) internal {
        GameTypes.Room storage room = rooms[roomId];
        int8 piece = room.board[from];
        
        room.board[to] = piece;
        room.board[from] = 0;
        
        if (moveType == GameTypes.MoveType.Capture) {
            uint8 middle = uint8((uint16(from) + uint16(to)) / 2);
            room.board[middle] = 0;
        }
    }
    
    function _hasCaptureMove(string memory roomId, int8 piece) internal view returns (bool) {
        GameTypes.Room storage room = rooms[roomId];
        
        for (uint8 pos = 0; pos < 37; pos++) {
            if (room.board[pos] == piece) {
                uint8[] memory adjacent = adjacentNodes[pos];
                for (uint i = 0; i < adjacent.length; i++) {
                    (bool isValid, GameTypes.MoveType moveType) = _validateMove(roomId, pos, adjacent[i], piece);
                    if (isValid && moveType == GameTypes.MoveType.Capture) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    
    function _hasChainCapture(string memory roomId, uint8 pos, int8 piece) internal view returns (bool) {
        uint8[] memory adjacent = adjacentNodes[pos];
        for (uint i = 0; i < adjacent.length; i++) {
            (bool isValid, GameTypes.MoveType moveType) = _validateMove(roomId, pos, adjacent[i], piece);
            if (isValid && moveType == GameTypes.MoveType.Capture) {
                return true;
            }
        }
        return false;
    }
    
    function _checkWinCondition(string memory roomId) internal returns (bool) {
        GameTypes.Room storage room = rooms[roomId];
        
        (uint8 player1Pieces, uint8 player2Pieces) = _countPieces(roomId);
        
        if (player1Pieces == 0) {
            _beforeEndGame(roomId, room.player2.playerAddress, GameTypes.GameStatus.Completed);
            return true;
        }
        if (player2Pieces == 0) {
            _beforeEndGame(roomId, room.player1.playerAddress, GameTypes.GameStatus.Completed);
            return true;
        }
        
        int8 currentPiece = (room.currentTurn == room.player1.playerAddress) ? int8(1) : int8(2);
        if (!_hasLegalMove(roomId, currentPiece)) {
            address winner = (room.currentTurn == room.player1.playerAddress) ? 
                room.player2.playerAddress : room.player1.playerAddress;
            _beforeEndGame(roomId, winner, GameTypes.GameStatus.Completed);
            return true;
        }
        
        return false;
    }
    
    function _hasLegalMove(string memory roomId, int8 piece) internal view returns (bool) {
        GameTypes.Room storage room = rooms[roomId];
        
        for (uint8 pos = 0; pos < 37; pos++) {
            if (room.board[pos] == piece) {
                uint8[] memory adjacent = adjacentNodes[pos];
                for (uint i = 0; i < adjacent.length; i++) {
                    (bool isValid,) = _validateMove(roomId, pos, adjacent[i], piece);
                    if (isValid) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    
    function _countPieces(string memory roomId) internal view returns (uint8, uint8) {
        GameTypes.Room storage room = rooms[roomId];
        uint8 player1Pieces = 0;
        uint8 player2Pieces = 0;
        
        for (uint8 i = 0; i < 37; i++) {
            if (room.board[i] == 1) player1Pieces++;
            if (room.board[i] == 2) player2Pieces++;
        }
        
        return (player1Pieces, player2Pieces);
    }
    
    function _beforeEndGame(string memory roomId, address winner, GameTypes.GameStatus status) internal virtual;
    
    function getBoardState(string memory roomId) external view returns (int8[37] memory) {
        GameTypes.Room storage room = rooms[roomId];
        int8[37] memory board;
        for (uint8 i = 0; i < 37; i++) {
            board[i] = room.board[i];
        }
        return board;
    }
    
    function getGameHistory(string memory roomId) external view returns (GameTypes.Move[] memory) {
        return gameHistory[roomId];
    }
}
