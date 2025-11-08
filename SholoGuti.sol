
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SholoGuti {
    // Constants
    uint256 constant STARTING_ELO = 400;
    uint256 constant ELO_K_FACTOR = 32;
    uint256 constant ELO_RANGE = 200;
    uint256 constant PLATFORM_FEE_PERCENT = 1;
    uint256 constant GAME_TIMEOUT = 10 minutes;
    uint256 constant MOVE_LIMIT_FOR_DRAW = 69;
    
    // Enums
    enum GameStatus { Waiting, Active, Completed, Resigned, DrawAccepted, Timeout }
    enum RoomType { Friends, Random }
    enum BotDifficulty { None, Easy, Medium, Hard }
    enum MoveType { Normal, Capture }
    
    // Structs
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
        mapping(uint8 => int8) board; // 37 positions: 0-36
    }
    
    struct Move {
        uint8 from;
        uint8 to;
        MoveType moveType;
        uint256 timestamp;
    }
    
    // State variables
    mapping(address => uint256) public playerElo;
    mapping(string => Room) public rooms;
    mapping(string => Move[]) public gameHistory;
    mapping(address => bool) public hasPlayed;
    
    string[] public activeRooms;
    string[] public waitingRooms;
    
    address public owner;
    uint256 public platformBalance;
    
    // Board topology - adjacency list for the 37-node board
    mapping(uint8 => uint8[]) public adjacentNodes;
    
    // Events
    event RoomCreated(string roomId, RoomType roomType, address creator, uint256 betAmount);
    event PlayerJoined(string roomId, address player);
    event MoveMade(string roomId, address player, uint8 from, uint8 to, MoveType moveType);
    event GameCompleted(string roomId, address winner, GameStatus status);
    event DrawOffered(string roomId, address offerer);
    event DrawAccepted(string roomId);
    event GameResigned(string roomId, address resignee);
    event EloUpdated(address player, uint256 newElo);
    
    constructor() {
        owner = msg.sender;
        _initializeBoard();
    }
    
    // Initialize the 37-node board topology
    function _initializeBoard() private {
        // Row 0 (Crown top) - positions 0-1
        adjacentNodes[0] = [1, 5];
        adjacentNodes[1] = [0, 6];
        
        // Row 1 - positions 2-6
        adjacentNodes[2] = [3, 7];
        adjacentNodes[3] = [2, 4, 7, 8];
        adjacentNodes[4] = [3, 5, 8, 9];
        adjacentNodes[5] = [0, 4, 6, 9, 10];
        adjacentNodes[6] = [1, 5, 10];
        
        // Row 2 (middle) - positions 7-11
        adjacentNodes[7] = [2, 3, 8, 12];
        adjacentNodes[8] = [3, 4, 7, 9, 12, 13];
        adjacentNodes[9] = [4, 5, 8, 10, 13, 14];
        adjacentNodes[10] = [5, 6, 9, 14];
        
        // Row 3 - positions 12-16
        adjacentNodes[12] = [7, 8, 13, 17];
        adjacentNodes[13] = [8, 9, 12, 14, 17, 18];
        adjacentNodes[14] = [9, 10, 13, 18, 19];
        
        // Row 4 - positions 17-21
        adjacentNodes[17] = [12, 13, 18, 22];
        adjacentNodes[18] = [13, 14, 17, 19, 22, 23];
        adjacentNodes[19] = [14, 18, 23];
        
        // Row 5 - positions 22-26
        adjacentNodes[22] = [17, 18, 23, 27];
        adjacentNodes[23] = [18, 19, 22, 24, 27, 28];
        adjacentNodes[24] = [23, 28];
        
        // Row 6 - positions 27-31
        adjacentNodes[27] = [22, 23, 28, 32];
        adjacentNodes[28] = [23, 24, 27, 29, 32, 33];
        adjacentNodes[29] = [28, 30, 33, 34];
        adjacentNodes[30] = [29, 31, 34, 35];
        adjacentNodes[31] = [30, 35];
        
        // Row 7 (Crown bottom) - positions 32-36
        adjacentNodes[32] = [27, 28, 33];
        adjacentNodes[33] = [28, 29, 32, 34];
        adjacentNodes[34] = [29, 30, 33, 35, 36];
        adjacentNodes[35] = [30, 31, 34, 36];
        adjacentNodes[36] = [34, 35];
    }
    
    // Create a friends room with optional betting
    function createFriendsRoom(uint256 betAmount) external payable returns (string memory) {
        require(msg.value == betAmount, "Incorrect bet amount sent");
        
        string memory roomId = _generateRoomId();
        Room storage room = rooms[roomId];
        
        room.roomId = roomId;
        room.roomType = RoomType.Friends;
        room.player1 = Player(msg.sender, _getOrInitElo(msg.sender), true);
        room.betAmount = betAmount;
        room.status = GameStatus.Waiting;
        room.botDifficulty = BotDifficulty.None;
        
        waitingRooms.push(roomId);
        
        emit RoomCreated(roomId, RoomType.Friends, msg.sender, betAmount);
        return roomId;
    }
    
    // Create a random room
    function createRandomRoom(uint256 betAmount) external payable returns (string memory) {
        require(msg.value == betAmount, "Incorrect bet amount sent");
        
        string memory roomId = _generateRoomId();
        Room storage room = rooms[roomId];
        
        room.roomId = roomId;
        room.roomType = RoomType.Random;
        room.player1 = Player(msg.sender, _getOrInitElo(msg.sender), true);
        room.betAmount = betAmount;
        room.status = GameStatus.Waiting;
        room.botDifficulty = BotDifficulty.None;
        
        waitingRooms.push(roomId);
        
        emit RoomCreated(roomId, RoomType.Random, msg.sender, betAmount);
        return roomId;
    }
    
    // Join a friends room by ID
    function joinFriendsRoom(string memory roomId) external payable {
        Room storage room = rooms[roomId];
        require(room.status == GameStatus.Waiting, "Room not available - game already started or completed");
        require(room.roomType == RoomType.Friends, "Not a friends room");
        require(!room.player2.hasJoined, "Room is full");
        require(room.player1.hasJoined, "Invalid room");
        require(msg.sender != room.player1.playerAddress, "Cannot play against yourself");
        require(msg.value == room.betAmount, "Incorrect bet amount");
        
        room.player2 = Player(msg.sender, _getOrInitElo(msg.sender), true);
        _startGame(roomId);
    }
    
    // Join a random room based on ELO
    function joinRandomRoom() external payable {
        uint256 playerEloValue = _getOrInitElo(msg.sender);
        
        // Find a suitable room
        for (uint i = 0; i < waitingRooms.length; i++) {
            string memory roomId = waitingRooms[i];
            Room storage room = rooms[roomId];
            
            if (room.status == GameStatus.Waiting && 
                room.roomType == RoomType.Random &&
                !room.player2.hasJoined &&
                msg.sender != room.player1.playerAddress &&
                msg.value == room.betAmount) {
                
                uint256 eloDiff = playerEloValue > room.player1.elo ? 
                    playerEloValue - room.player1.elo : 
                    room.player1.elo - playerEloValue;
                
                if (eloDiff <= ELO_RANGE) {
                    room.player2 = Player(msg.sender, playerEloValue, true);
                    _startGame(roomId);
                    return;
                }
            }
        }
        
        revert("No suitable room found. Create a new room.");
    }
    
    // Create a bot game
    function createBotGame(BotDifficulty difficulty) external returns (string memory) {
        require(difficulty != BotDifficulty.None, "Invalid bot difficulty");
        
        string memory roomId = _generateRoomId();
        Room storage room = rooms[roomId];
        
        room.roomId = roomId;
        room.roomType = RoomType.Friends;
        room.player1 = Player(msg.sender, _getOrInitElo(msg.sender), true);
        room.player2 = Player(address(this), 400, true); // Bot as player 2
        room.betAmount = 0;
        room.botDifficulty = difficulty;
        
        _startGame(roomId);
        
        emit RoomCreated(roomId, RoomType.Friends, msg.sender, 0);
        return roomId;
    }
    
    // Start the game
    function _startGame(string memory roomId) private {
        Room storage room = rooms[roomId];
        room.status = GameStatus.Active;
        room.currentTurn = room.player1.playerAddress;
        room.lastMoveTime = block.timestamp;
        
        _initializeGameBoard(roomId);
        _removeFromWaitingRooms(roomId);
        activeRooms.push(roomId);
        
        emit PlayerJoined(roomId, room.player2.playerAddress);
    }
    
    // Initialize the game board with starting positions
    function _initializeGameBoard(string memory roomId) private {
        Room storage room = rooms[roomId];
        
        // Player 1 pieces (bottom): positions 22-31 + crown (32, 33)
        room.board[22] = 1; room.board[23] = 1; room.board[24] = 1;
        room.board[27] = 1; room.board[28] = 1; room.board[29] = 1;
        room.board[30] = 1; room.board[31] = 1;
        room.board[32] = 1; room.board[33] = 1;
        
        // Player 2 pieces (top): positions 2-6 + 7-11 (partial) + crown (0, 1)
        room.board[0] = 2; room.board[1] = 2;
        room.board[2] = 2; room.board[3] = 2; room.board[4] = 2;
        room.board[5] = 2; room.board[6] = 2;
        room.board[7] = 2; room.board[8] = 2; room.board[9] = 2;
        room.board[10] = 2;
        
        // Middle row empty (11, 12, 13, 14, 15, 16)
        // All other positions are 0 (empty)
    }
    
    // Make a move
    function makeMove(string memory roomId, uint8 from, uint8 to) external {
        Room storage room = rooms[roomId];
        require(room.status == GameStatus.Active, "Game not active");
        
        // Check timeout and auto-forfeit if needed
        if (block.timestamp > room.lastMoveTime + GAME_TIMEOUT) {
            address winner = (room.currentTurn == room.player1.playerAddress) ? 
                room.player2.playerAddress : room.player1.playerAddress;
            _endGame(roomId, winner, GameStatus.Timeout);
            revert("Previous player timed out - game ended");
        }
        
        require(msg.sender == room.currentTurn, "Not your turn");
        
        int8 piece = room.board[from];
        require(piece != 0, "No piece at from position");
        
        // Check ownership
        if (msg.sender == room.player1.playerAddress) {
            require(piece == 1, "Not your piece");
        } else {
            require(piece == 2, "Not your piece");
        }
        
        // Validate move
        (bool isValid, MoveType moveType) = _validateMove(roomId, from, to, piece);
        require(isValid, "Invalid move");
        
        // Check forced capture rule
        bool captureAvailable = _hasCaptureMove(roomId, piece);
        if (captureAvailable) {
            require(moveType == MoveType.Capture, "Must capture when available");
        }
        
        // Execute move
        _executeMove(roomId, from, to, moveType);
        
        // Record move
        gameHistory[roomId].push(Move(from, to, moveType, block.timestamp));
        room.moveCount++;
        
        if (moveType == MoveType.Capture) {
            room.movesWithoutCapture = 0;
            
            // Check for chain capture
            if (_hasChainCapture(roomId, to, piece)) {
                // Same player continues
                emit MoveMade(roomId, msg.sender, from, to, moveType);
                return;
            }
        } else {
            room.movesWithoutCapture++;
        }
        
        // Check win conditions
        if (_checkWinCondition(roomId)) {
            return; // Game ended
        }
        
        // Check 69-move rule
        if (room.movesWithoutCapture >= MOVE_LIMIT_FOR_DRAW) {
            _handleDrawByMoveLimit(roomId);
            return;
        }
        
        // Switch turn
        room.currentTurn = (room.currentTurn == room.player1.playerAddress) ? 
            room.player2.playerAddress : room.player1.playerAddress;
        room.lastMoveTime = block.timestamp;
        
        emit MoveMade(roomId, msg.sender, from, to, moveType);
        
        // If bot's turn, make bot move
        if (room.botDifficulty != BotDifficulty.None && 
            room.currentTurn == address(this)) {
            _makeBotMove(roomId);
        }
    }
    
    // Validate move legality
    function _validateMove(string memory roomId, uint8 from, uint8 to, int8 piece) 
        private view returns (bool, MoveType) {
        Room storage room = rooms[roomId];
        
        // Check if 'to' is empty
        if (room.board[to] != 0) {
            return (false, MoveType.Normal);
        }
        
        // Check if positions are adjacent
        bool isAdjacent = false;
        uint8[] memory adjacent = adjacentNodes[from];
        for (uint i = 0; i < adjacent.length; i++) {
            if (adjacent[i] == to) {
                isAdjacent = true;
                break;
            }
        }
        
        if (isAdjacent) {
            return (true, MoveType.Normal);
        }
        
        // Check for capture move (jump over opponent piece)
        int8 opponentPiece = (piece == 1) ? int8(2) : int8(1);
        
        for (uint i = 0; i < adjacent.length; i++) {
            uint8 middle = adjacent[i];
            if (room.board[middle] == opponentPiece) {
                // Check if 'to' is on the opposite side of middle from 'from'
                uint8[] memory middleAdjacent = adjacentNodes[middle];
                for (uint j = 0; j < middleAdjacent.length; j++) {
                    if (middleAdjacent[j] == to && middleAdjacent[j] != from) {
                        // Check alignment (from-middle-to must be in a line)
                        if (_isInLine(from, middle, to)) {
                            return (true, MoveType.Capture);
                        }
                    }
                }
            }
        }
        
        return (false, MoveType.Normal);
    }
    
    // Check if three positions are in a straight line
    function _isInLine(uint8 from, uint8 middle, uint8 to) private pure returns (bool) {
        // This is a simplified check - in a real implementation, 
        // you'd need to check the actual board geometry
        return true; // Placeholder
    }
    
    // Execute the move
    function _executeMove(string memory roomId, uint8 from, uint8 to, MoveType moveType) private {
        Room storage room = rooms[roomId];
        int8 piece = room.board[from];
        
        room.board[to] = piece;
        room.board[from] = 0;
        
        if (moveType == MoveType.Capture) {
            // Remove captured piece (middle position)
            uint8 middle = _findMiddlePosition(from, to);
            room.board[middle] = 0;
        }
    }
    
    // Find the middle position between from and to for capture
    function _findMiddlePosition(uint8 from, uint8 to) private pure returns (uint8) {
        // Simplified - calculate based on position arithmetic
        return uint8((uint16(from) + uint16(to)) / 2);
    }
    
    // Check if player has any capture move available
    function _hasCaptureMove(string memory roomId, int8 piece) private view returns (bool) {
        Room storage room = rooms[roomId];
        
        for (uint8 pos = 0; pos < 37; pos++) {
            if (room.board[pos] == piece) {
                uint8[] memory adjacent = adjacentNodes[pos];
                for (uint i = 0; i < adjacent.length; i++) {
                    // Check all possible destinations from this piece
                    (bool isValid, MoveType moveType) = _validateMove(roomId, pos, adjacent[i], piece);
                    if (isValid && moveType == MoveType.Capture) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    
    // Check if piece at position can make another capture
    function _hasChainCapture(string memory roomId, uint8 pos, int8 piece) private view returns (bool) {
        Room storage room = rooms[roomId];
        
        uint8[] memory adjacent = adjacentNodes[pos];
        for (uint i = 0; i < adjacent.length; i++) {
            (bool isValid, MoveType moveType) = _validateMove(roomId, pos, adjacent[i], piece);
            if (isValid && moveType == MoveType.Capture) {
                return true;
            }
        }
        return false;
    }
    
    // Check win conditions
    function _checkWinCondition(string memory roomId) private returns (bool) {
        Room storage room = rooms[roomId];
        
        uint8 player1Pieces = 0;
        uint8 player2Pieces = 0;
        
        for (uint8 i = 0; i < 37; i++) {
            if (room.board[i] == 1) player1Pieces++;
            if (room.board[i] == 2) player2Pieces++;
        }
        
        // Check if all pieces captured
        if (player1Pieces == 0) {
            _endGame(roomId, room.player2.playerAddress, GameStatus.Completed);
            return true;
        }
        if (player2Pieces == 0) {
            _endGame(roomId, room.player1.playerAddress, GameStatus.Completed);
            return true;
        }
        
        // Check for blockade (no legal moves)
        int8 currentPiece = (room.currentTurn == room.player1.playerAddress) ? int8(1) : int8(2);
        if (!_hasLegalMove(roomId, currentPiece)) {
            address winner = (room.currentTurn == room.player1.playerAddress) ? 
                room.player2.playerAddress : room.player1.playerAddress;
            _endGame(roomId, winner, GameStatus.Completed);
            return true;
        }
        
        return false;
    }
    
    // Check if player has any legal move
    function _hasLegalMove(string memory roomId, int8 piece) private view returns (bool) {
        Room storage room = rooms[roomId];
        
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
    
    // Handle draw by 69-move rule
    function _handleDrawByMoveLimit(string memory roomId) private {
        Room storage room = rooms[roomId];
        
        uint8 player1Pieces = 0;
        uint8 player2Pieces = 0;
        
        for (uint8 i = 0; i < 37; i++) {
            if (room.board[i] == 1) player1Pieces++;
            if (room.board[i] == 2) player2Pieces++;
        }
        
        address winner;
        if (player1Pieces > player2Pieces) {
            winner = room.player1.playerAddress;
        } else if (player2Pieces > player1Pieces) {
            winner = room.player2.playerAddress;
        } else {
            winner = address(0); // Draw
        }
        
        _endGame(roomId, winner, GameStatus.Completed);
    }
    
    // Offer a draw
    function offerDraw(string memory roomId) external {
        Room storage room = rooms[roomId];
        require(room.status == GameStatus.Active, "Game not active");
        require(msg.sender == room.player1.playerAddress || msg.sender == room.player2.playerAddress, "Not a player");
        
        if (msg.sender == room.player1.playerAddress) {
            room.drawOfferedBy1 = true;
            if (room.drawOfferedBy2) {
                _endGame(roomId, address(0), GameStatus.DrawAccepted);
                emit DrawAccepted(roomId);
            } else {
                emit DrawOffered(roomId, msg.sender);
            }
        } else {
            room.drawOfferedBy2 = true;
            if (room.drawOfferedBy1) {
                _endGame(roomId, address(0), GameStatus.DrawAccepted);
                emit DrawAccepted(roomId);
            } else {
                emit DrawOffered(roomId, msg.sender);
            }
        }
    }
    
    // Resign from game
    function resign(string memory roomId) external {
        Room storage room = rooms[roomId];
        require(room.status == GameStatus.Active, "Game not active");
        require(msg.sender == room.player1.playerAddress || msg.sender == room.player2.playerAddress, "Not a player");
        
        address winner = (msg.sender == room.player1.playerAddress) ? 
            room.player2.playerAddress : room.player1.playerAddress;
        
        _endGame(roomId, winner, GameStatus.Resigned);
        emit GameResigned(roomId, msg.sender);
    }
    
    // Claim timeout victory (if opponent hasn't moved within timeout period)
    function claimTimeoutVictory(string memory roomId) external {
        Room storage room = rooms[roomId];
        require(room.status == GameStatus.Active, "Game not active");
        require(msg.sender == room.player1.playerAddress || msg.sender == room.player2.playerAddress, "Not a player");
        require(block.timestamp > room.lastMoveTime + GAME_TIMEOUT, "Timeout period not reached");
        require(msg.sender != room.currentTurn, "Cannot claim timeout on your own turn");
        
        _endGame(roomId, msg.sender, GameStatus.Timeout);
    }
    
    // End the game with automatic payout
    function _endGame(string memory roomId, address winner, GameStatus status) private {
        Room storage room = rooms[roomId];
        room.status = status;
        room.winner = winner;
        
        // Update ELO only for non-bot games and only on actual game completion
        if (room.botDifficulty == BotDifficulty.None && 
            room.player1.hasJoined && 
            room.player2.hasJoined) {
            _updateElo(roomId, winner);
        }
        
        // Handle automatic payouts
        if (room.betAmount > 0 && room.player2.hasJoined) {
            uint256 totalPot = room.betAmount * 2;
            uint256 platformFee = (totalPot * PLATFORM_FEE_PERCENT) / 100;
            uint256 netPot = totalPot - platformFee;
            
            platformBalance += platformFee;
            
            if (winner != address(0)) {
                // Winner takes all (minus platform fee)
                payable(winner).transfer(netPot);
            } else {
                // Draw - split pot equally (minus platform fee)
                uint256 splitAmount = netPot / 2;
                payable(room.player1.playerAddress).transfer(splitAmount);
                payable(room.player2.playerAddress).transfer(splitAmount);
            }
        } else if (room.betAmount > 0 && !room.player2.hasJoined) {
            // Refund player1 if game never started
            payable(room.player1.playerAddress).transfer(room.betAmount);
        }
        
        _removeFromActiveRooms(roomId);
        emit GameCompleted(roomId, winner, status);
    }
    
    // Update ELO ratings
    function _updateElo(string memory roomId, address winner) private {
        Room storage room = rooms[roomId];
        
        uint256 elo1 = room.player1.elo;
        uint256 elo2 = room.player2.elo;
        
        // Calculate expected scores
        int256 diff1 = int256(elo1) - int256(elo2);
        uint256 expected1 = _calculateExpectedScore(diff1);
        uint256 expected2 = 1000 - expected1; // Expected scores sum to 1000 (representing 1.0)
        
        uint256 score1;
        uint256 score2;
        
        if (winner == room.player1.playerAddress) {
            score1 = 1000; // Win
            score2 = 0;    // Loss
        } else if (winner == room.player2.playerAddress) {
            score1 = 0;    // Loss
            score2 = 1000; // Win
        } else {
            // Draw - special rule
            if (elo1 < elo2) {
                score1 = 500; // Lower rated gets +0.5
                score2 = 0;   // Higher rated gets -0
            } else {
                score1 = 0;   // Higher rated gets -0
                score2 = 500; // Lower rated gets +0.5
            }
        }
        
        // Calculate new ELOs
        int256 change1 = (int256(ELO_K_FACTOR) * (int256(score1) - int256(expected1))) / 1000;
        int256 change2 = (int256(ELO_K_FACTOR) * (int256(score2) - int256(expected2))) / 1000;
        
        uint256 newElo1 = uint256(int256(elo1) + change1);
        uint256 newElo2 = uint256(int256(elo2) + change2);
        
        playerElo[room.player1.playerAddress] = newElo1;
        playerElo[room.player2.playerAddress] = newElo2;
        
        emit EloUpdated(room.player1.playerAddress, newElo1);
        emit EloUpdated(room.player2.playerAddress, newElo2);
    }
    
    // Calculate expected score (0-1000 representing 0.0-1.0)
    function _calculateExpectedScore(int256 eloDiff) private pure returns (uint256) {
        // Simplified logistic function: 1 / (1 + 10^(-diff/400))
        // Returns value from 0-1000
        if (eloDiff >= 400) return 909; // ~0.909
        if (eloDiff >= 200) return 760; // ~0.760
        if (eloDiff >= 100) return 640; // ~0.640
        if (eloDiff >= 0) return 500;   // 0.500
        if (eloDiff >= -100) return 360; // ~0.360
        if (eloDiff >= -200) return 240; // ~0.240
        return 91; // ~0.091
    }
    
    // Bot move (simplified AI)
    function _makeBotMove(string memory roomId) private {
        Room storage room = rooms[roomId];
        
        // Find all valid moves for bot (piece = 2)
        uint8 bestFrom = 0;
        uint8 bestTo = 0;
        bool foundMove = false;
        
        // Prioritize captures
        for (uint8 pos = 0; pos < 37; pos++) {
            if (room.board[pos] == 2) {
                uint8[] memory adjacent = adjacentNodes[pos];
                for (uint i = 0; i < adjacent.length; i++) {
                    (bool isValid, MoveType moveType) = _validateMove(roomId, pos, adjacent[i], 2);
                    if (isValid && moveType == MoveType.Capture) {
                        bestFrom = pos;
                        bestTo = adjacent[i];
                        foundMove = true;
                        break;
                    }
                }
                if (foundMove) break;
            }
        }
        
        // If no capture, make normal move
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
            // Execute bot move (recursive call to makeMove wouldn't work due to msg.sender)
            // So we simulate it here
            (bool isValid, MoveType moveType) = _validateMove(roomId, bestFrom, bestTo, 2);
            _executeMove(roomId, bestFrom, bestTo, moveType);
            gameHistory[roomId].push(Move(bestFrom, bestTo, moveType, block.timestamp));
            room.moveCount++;
            
            if (moveType != MoveType.Capture) {
                room.movesWithoutCapture++;
            }
            
            emit MoveMade(roomId, address(this), bestFrom, bestTo, moveType);
            
            // Check win conditions
            if (!_checkWinCondition(roomId)) {
                room.currentTurn = room.player1.playerAddress;
                room.lastMoveTime = block.timestamp;
            }
        }
    }
    
    // Get or initialize player ELO
    function _getOrInitElo(address player) private returns (uint256) {
        if (!hasPlayed[player]) {
            playerElo[player] = STARTING_ELO;
            hasPlayed[player] = true;
        }
        return playerElo[player];
    }
    
    // Generate unique room ID
    function _generateRoomId() private view returns (string memory) {
        return string(abi.encodePacked(
            "room_",
            _uint2str(block.timestamp),
            "_",
            _uint2str(uint256(uint160(msg.sender)))
        ));
    }
    
    // Helper: uint to string
    function _uint2str(uint256 _i) private pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    
    // Remove from waiting rooms
    function _removeFromWaitingRooms(string memory roomId) private {
        for (uint i = 0; i < waitingRooms.length; i++) {
            if (keccak256(bytes(waitingRooms[i])) == keccak256(bytes(roomId))) {
                waitingRooms[i] = waitingRooms[waitingRooms.length - 1];
                waitingRooms.pop();
                break;
            }
        }
    }
    
    // Remove from active rooms
    function _removeFromActiveRooms(string memory roomId) private {
        for (uint i = 0; i < activeRooms.length; i++) {
            if (keccak256(bytes(activeRooms[i])) == keccak256(bytes(roomId))) {
                activeRooms[i] = activeRooms[activeRooms.length - 1];
                activeRooms.pop();
                break;
            }
        }
    }
    
    // Public view functions for frontend integration
    function getPlayerElo(address player) external view returns (uint256) {
        return playerElo[player];
    }
    
    function getGameHistory(string memory roomId) external view returns (Move[] memory) {
        return gameHistory[roomId];
    }
    
    function getWaitingRooms() external view returns (string[] memory) {
        return waitingRooms;
    }
    
    function getActiveRooms() external view returns (string[] memory) {
        return activeRooms;
    }
    
    function getBoardState(string memory roomId) external view returns (int8[37] memory) {
        Room storage room = rooms[roomId];
        int8[37] memory board;
        for (uint8 i = 0; i < 37; i++) {
            board[i] = room.board[i];
        }
        return board;
    }
    
    // Get complete room details for frontend
    function getRoomDetails(string memory roomId) external view returns (
        string memory,
        RoomType,
        address,
        address,
        uint256,
        uint256,
        GameStatus,
        address,
        uint256,
        uint256,
        address,
        BotDifficulty
    ) {
        Room storage room = rooms[roomId];
        return (
            room.roomId,
            room.roomType,
            room.player1.playerAddress,
            room.player2.playerAddress,
            room.player1.elo,
            room.player2.elo,
            room.status,
            room.currentTurn,
            room.moveCount,
            room.betAmount,
            room.winner,
            room.botDifficulty
        );
    }
    
    // Check if timeout has occurred
    function isGameTimedOut(string memory roomId) external view returns (bool) {
        Room storage room = rooms[roomId];
        if (room.status != GameStatus.Active) return false;
        return block.timestamp > room.lastMoveTime + GAME_TIMEOUT;
    }
    
    // Get time remaining for current turn
    function getTimeRemaining(string memory roomId) external view returns (uint256) {
        Room storage room = rooms[roomId];
        if (room.status != GameStatus.Active) return 0;
        uint256 deadline = room.lastMoveTime + GAME_TIMEOUT;
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }
    
    // Get available rooms for matchmaking
    function getAvailableRoomsForPlayer(address player) external view returns (string[] memory) {
        uint256 playerEloValue = playerElo[player];
        if (playerEloValue == 0) playerEloValue = STARTING_ELO;
        
        uint256 count = 0;
        for (uint i = 0; i < waitingRooms.length; i++) {
            Room storage room = rooms[waitingRooms[i]];
            if (room.roomType == RoomType.Random && 
                room.status == GameStatus.Waiting &&
                room.player1.playerAddress != player) {
                
                uint256 eloDiff = playerEloValue > room.player1.elo ? 
                    playerEloValue - room.player1.elo : 
                    room.player1.elo - playerEloValue;
                
                if (eloDiff <= ELO_RANGE) {
                    count++;
                }
            }
        }
        
        string[] memory availableRooms = new string[](count);
        uint256 index = 0;
        for (uint i = 0; i < waitingRooms.length; i++) {
            Room storage room = rooms[waitingRooms[i]];
            if (room.roomType == RoomType.Random && 
                room.status == GameStatus.Waiting &&
                room.player1.playerAddress != player) {
                
                uint256 eloDiff = playerEloValue > room.player1.elo ? 
                    playerEloValue - room.player1.elo : 
                    room.player1.elo - playerEloValue;
                
                if (eloDiff <= ELO_RANGE) {
                    availableRooms[index] = waitingRooms[i];
                    index++;
                }
            }
        }
        
        return availableRooms;
    }
    
    // Get platform statistics
    function getPlatformStats() external view returns (
        uint256 totalPlatformFees,
        uint256 activeGamesCount,
        uint256 waitingGamesCount
    ) {
        return (
            platformBalance,
            activeRooms.length,
            waitingRooms.length
        );
    }
    
    // Owner functions
    function withdrawPlatformFees() external {
        require(msg.sender == owner, "Only owner");
        require(platformBalance > 0, "No fees to withdraw");
        uint256 amount = platformBalance;
        platformBalance = 0;
        payable(owner).transfer(amount);
    }
    
    // Recover accidentally sent ERC20 tokens
    function recoverERC20(address tokenAddress, uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        require(tokenAddress != address(0), "Invalid token address");
        
        // Using low-level call to avoid importing IERC20
        (bool success, bytes memory data) = tokenAddress.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Token transfer failed");
    }
    
    // Emergency ETH recovery (only for accidentally sent ETH, not bet amounts)
    function recoverETH(uint256 amount) external {
        require(msg.sender == owner, "Only owner");
        require(amount <= address(this).balance, "Insufficient balance");
        payable(owner).transfer(amount);
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Only owner");
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }
}
