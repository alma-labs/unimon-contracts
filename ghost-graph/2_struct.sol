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

/*    event EncounterResolved(
        uint256 indexed encounterId,
        uint256 indexed winnerId,
        uint256 indexed loserId,
        address winnerPlayer,
        address loserPlayer,
        uint256 timestamp,
        uint256 battleCycle
    );*/
