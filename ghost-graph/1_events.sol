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
}
