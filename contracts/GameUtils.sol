// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./GameTypes.sol";

library GameUtils {
    function generateRoomId(uint256 timestamp, address sender) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "R",
            uint2str(timestamp),
            uint2str(uint256(uint160(sender)) % 10000)
        ));
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
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

    function calculateExpectedScore(int256 eloDiff) internal pure returns (uint256) {
        if (eloDiff >= 400) return 909;
        if (eloDiff >= 200) return 760;
        if (eloDiff >= 100) return 640;
        if (eloDiff >= 0) return 500;
        if (eloDiff >= -100) return 360;
        if (eloDiff >= -200) return 240;
        return 91;
    }

    function calculateEloChange(
        uint256 elo1,
        uint256 elo2,
        address winner,
        address player1,
        address player2
    ) internal pure returns (uint256 newElo1, uint256 newElo2) {
        int256 expected1 = int256(calculateExpectedScore(int256(elo1) - int256(elo2)));
        int256 expected2 = int256(calculateExpectedScore(int256(elo2) - int256(elo1)));

        int256 score1;
        int256 score2;

        if (winner == player1) {
            score1 = 100;
            score2 = 0;
        } else if (winner == player2) {
            score1 = 0;
            score2 = 100;
        } else {
            // Draw: 0.5 ELO to lower rated player, 0 to higher rated player
            if (elo1 < elo2) {
                // Player 1 is lower rated, gets +0.5 ELO, Player 2 gets 0
                newElo1 = elo1 + 1; // +0.5 rounded to 1
                newElo2 = elo2;
                return (newElo1, newElo2);
            } else if (elo2 < elo1) {
                // Player 2 is lower rated, gets +0.5 ELO, Player 1 gets 0
                newElo1 = elo1;
                newElo2 = elo2 + 1; // +0.5 rounded to 1
                return (newElo1, newElo2);
            } else {
                // Equal ELO, both get 0 change
                return (elo1, elo2);
            }
        }

        int256 change1 = (int256(GameTypes.ELO_K_FACTOR) * (score1 - expected1)) / 100;
        int256 change2 = (int256(GameTypes.ELO_K_FACTOR) * (score2 - expected2)) / 100;

        newElo1 = uint256(int256(elo1) + change1);
        newElo2 = uint256(int256(elo2) + change2);
    }
}