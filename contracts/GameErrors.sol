// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library GameErrors {
    error IncorrectBetAmount();
    error RoomNotAvailable();
    error RoomIsFull();
    error InvalidRoom();
    error CannotPlayYourself();
    error GameNotActive();
    error NotYourTurn();
    error NoPieceAtPosition();
    error NotYourPiece();
    error InvalidMove();
    error MustCaptureWhenAvailable();
    error NotAPlayer();
    error PayoutAlreadyCompleted();
    error OnlyOwner();
    error InvalidBotDifficulty();
    error NoSuitableRoomFound();
    error NotFriendsRoom();
    error GameTimedOut();
}
