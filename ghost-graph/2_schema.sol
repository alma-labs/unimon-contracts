struct Transfer {
    string id;
    address from;
    address to;
    uint256 tokenId;
    bytes32 transactionHash;
}

struct EncounterResolved {
    string id;
    uint256 encounterId;
    uint256 winnerId;
    uint256 loserId;
    address winnerPlayer;
    address loserPlayer;
    uint256 timestamp;
    uint256 battleCycle;
    bytes32 transactionHash;
}

struct GoodMorning {
    string id;
    address user;
    uint256 tokenId;
    uint256 day;
    uint40 timestamp;
    uint32 currentStreak;
    uint32 bestStreak;
    bytes32 transactionHash;
}

struct MonsterFought {
    string id;
    address user;
    uint256 tokenId;
    uint256 monsterId;
    bool won;
    uint256 power;
    uint8 difficulty;
    bytes32 transactionHash;
}
