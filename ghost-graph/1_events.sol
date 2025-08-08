interface Events {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    event EncounterResolved(
        uint256 indexed encounterId,
        uint256 indexed winnerId,
        uint256 indexed loserId,
        address winnerPlayer,
        address loserPlayer,
        uint256 timestamp,
        uint256 battleCycle
    );

    event GoodMorning(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed day,
        uint40 timestamp,
        uint32 currentStreak,
        uint32 bestStreak
    );

    event MonsterFought(
        address indexed user,
        uint256 indexed tokenId,
        uint256 indexed monsterId,
        bool won,
        uint256 power,
        uint8 difficulty
    );
}
