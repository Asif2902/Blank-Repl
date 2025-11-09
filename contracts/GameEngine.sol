
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameTypes.sol";
import "./GameErrors.sol";

abstract contract GameEngine {
    using GameTypes for *;
    
    mapping(uint8 => uint8[]) public adjacentNodes;
    mapping(string => GameTypes.Room) internal rooms;
    mapping(string => GameTypes.Move[]) public gameHistory;
    mapping(string => uint8) public lastMovedPiecePosition;
    
    constructor() {
        _initializeBoard();
    }
    
    function _initializeBoard() private {
        // Main 5x5 grid (nodes 0-24)
        adjacentNodes[0] = [1, 5, 6];
        adjacentNodes[1] = [0, 2, 5, 6, 7];
        adjacentNodes[2] = [1, 3, 6, 7, 8];
        adjacentNodes[3] = [2, 4, 7, 8, 9];
        adjacentNodes[4] = [3, 8, 9];
        adjacentNodes[5] = [0, 1, 6, 10, 11];
        adjacentNodes[6] = [0, 1, 2, 5, 7, 10, 11, 12];
        adjacentNodes[7] = [1, 2, 3, 6, 8, 11, 12, 13];
        adjacentNodes[8] = [2, 3, 4, 7, 9, 12, 13, 14];
        adjacentNodes[9] = [3, 4, 8, 13, 14];
        adjacentNodes[10] = [5, 6, 11, 15, 16];
        adjacentNodes[11] = [5, 6, 7, 10, 12, 15, 16, 17];
        adjacentNodes[12] = [6, 7, 8, 11, 13, 16, 17, 18];
        adjacentNodes[13] = [7, 8, 9, 12, 14, 17, 18, 19];
        adjacentNodes[14] = [8, 9, 13, 18, 19];
        adjacentNodes[15] = [10, 11, 16, 20, 21];
        adjacentNodes[16] = [10, 11, 12, 15, 17, 20, 21, 22, 34];
        adjacentNodes[17] = [11, 12, 13, 16, 18, 21, 22, 23, 35];
        adjacentNodes[18] = [12, 13, 14, 17, 19, 22, 23, 24];
        adjacentNodes[19] = [13, 14, 18, 23, 24];
        adjacentNodes[20] = [15, 16, 21, 25, 26];
        adjacentNodes[21] = [15, 16, 17, 20, 22, 25, 26, 27, 34, 35];
        adjacentNodes[22] = [16, 17, 18, 21, 23, 26, 27, 28, 35, 36];
        adjacentNodes[23] = [17, 18, 19, 22, 24, 27, 28, 29, 36];
        adjacentNodes[24] = [18, 19, 23, 28, 29];
        
        // Player 2's crown (bottom): (1,-1)=25, (2,-1)=26, (3,-1)=27, (2,-2)=33
        adjacentNodes[25] = [20, 21, 26, 30, 31];
        adjacentNodes[26] = [20, 21, 22, 25, 27, 30, 31, 32];
        adjacentNodes[27] = [21, 22, 23, 26, 28, 31, 32];
        adjacentNodes[28] = [22, 23, 24, 27, 29, 32];
        adjacentNodes[29] = [23, 24, 28];
        adjacentNodes[30] = [25, 26, 31];
        adjacentNodes[31] = [25, 26, 27, 30, 32, 33];
        adjacentNodes[32] = [26, 27, 28, 31, 33];
        adjacentNodes[33] = [31, 32];
        
        // Player 1's crown (top): (1,5)=34, (2,5)=35, (3,5)=36, (2,6)=37 (but we only have 37 nodes, 0-36)
        // Adjusted: nodes 34, 35, 36 connect to row 3 of main grid
        adjacentNodes[34] = [16, 21, 35];
        adjacentNodes[35] = [17, 21, 22, 34, 36];
        adjacentNodes[36] = [22, 23, 35];
    }
    
    function _initializeGameBoard(string memory roomId) internal {
        GameTypes.Room storage room = rooms[roomId];
        
        // Player 1 (16 pieces): bottom half + crown
        // Row 3 (nodes 15-19): 5 pieces
        room.board[15] = 1; room.board[16] = 1; room.board[17] = 1; room.board[18] = 1; room.board[19] = 1;
        // Row 4 (nodes 20-24): 5 pieces  
        room.board[20] = 1; room.board[21] = 1; room.board[22] = 1; room.board[23] = 1; room.board[24] = 1;
        // Crown top (nodes 34-36): 3 pieces
        room.board[34] = 1; room.board[35] = 1; room.board[36] = 1;
        // Row 2 additional (nodes 10-14): 3 pieces to make 16 total
        room.board[11] = 1; room.board[12] = 1; room.board[13] = 1;
        
        // Player 2 (16 pieces): top half + crown
        // Row 0 (nodes 0-4): 5 pieces
        room.board[0] = 2; room.board[1] = 2; room.board[2] = 2; room.board[3] = 2; room.board[4] = 2;
        // Row 1 (nodes 5-9): 5 pieces
        room.board[5] = 2; room.board[6] = 2; room.board[7] = 2; room.board[8] = 2; room.board[9] = 2;
        // Crown bottom (nodes 25-27, 33): 4 pieces
        room.board[25] = 2; room.board[26] = 2; room.board[27] = 2; room.board[33] = 2;
        // Row 2 additional: 2 pieces to make 16 total  
        room.board[10] = 2; room.board[14] = 2;
    }
    
    function _validateMove(string memory roomId, uint8 from, uint8 to, int8 piece) 
        internal view returns (bool, GameTypes.MoveType) {
        GameTypes.Room storage room = rooms[roomId];
        
        if (to > 36) return (false, GameTypes.MoveType.Normal);
        if (room.board[to] != 0) return (false, GameTypes.MoveType.Normal);
        
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
            uint8 middle = _findCapturedPiece(roomId, from, to, piece);
            room.board[middle] = 0;
        }
        
        lastMovedPiecePosition[roomId] = to;
    }
    
    function _findCapturedPiece(string memory roomId, uint8 from, uint8 to, int8 piece) internal view returns (uint8) {
        GameTypes.Room storage room = rooms[roomId];
        int8 opponentPiece = (piece == 1) ? int8(2) : int8(1);
        
        uint8[] memory adjacentFrom = adjacentNodes[from];
        uint8[] memory adjacentTo = adjacentNodes[to];
        
        for (uint i = 0; i < adjacentFrom.length; i++) {
            uint8 candidate = adjacentFrom[i];
            if (room.board[candidate] == opponentPiece) {
                for (uint j = 0; j < adjacentTo.length; j++) {
                    if (adjacentTo[j] == candidate && candidate != from) {
                        return candidate;
                    }
                }
            }
        }
        revert("No opponent piece found in capture path");
    }
    
    function _hasCaptureMove(string memory roomId, int8 piece) internal view returns (bool) {
        GameTypes.Room storage room = rooms[roomId];
        
        for (uint8 pos = 0; pos <= 36; pos++) {
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
        
        if (room.movesWithoutCapture >= 69) {
            if (player1Pieces == player2Pieces) {
                _beforeEndGame(roomId, address(0), GameTypes.GameStatus.DrawAccepted);
            } else if (player1Pieces > player2Pieces) {
                _beforeEndGame(roomId, room.player1.playerAddress, GameTypes.GameStatus.Completed);
            } else {
                _beforeEndGame(roomId, room.player2.playerAddress, GameTypes.GameStatus.Completed);
            }
            return true;
        }
        
        return false;
    }
    
    function _hasLegalMove(string memory roomId, int8 piece) internal view returns (bool) {
        GameTypes.Room storage room = rooms[roomId];
        
        for (uint8 pos = 0; pos <= 36; pos++) {
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
        
        for (uint8 i = 0; i <= 36; i++) {
            if (room.board[i] == 1) player1Pieces++;
            if (room.board[i] == 2) player2Pieces++;
        }
        
        return (player1Pieces, player2Pieces);
    }
    
    function _beforeEndGame(string memory roomId, address winner, GameTypes.GameStatus status) internal virtual;
    
    function getBoardState(string memory roomId) external view returns (int8[37] memory) {
        GameTypes.Room storage room = rooms[roomId];
        int8[37] memory board;
        for (uint8 i = 0; i <= 36; i++) {
            board[i] = room.board[i];
        }
        return board;
    }
    
    function getGameHistory(string memory roomId) external view returns (GameTypes.Move[] memory) {
        return gameHistory[roomId];
    }
}
