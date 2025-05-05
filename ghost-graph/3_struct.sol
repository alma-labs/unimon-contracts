// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./gen_schema.sol";
import "./gen_events.sol";
import "./gen_base.sol";
import "./gen_helpers.sol";

contract MyIndex is GhostGraph {
    using StringHelpers for EventDetails;
    using StringHelpers for uint256;
    using StringHelpers for address;

    function registerHandles() external {
        graph.registerHandle(0x7F7d7E4a9D4DA8997730997983C5Ca64846868C0);
        graph.registerHandle(0xbd597d13F325cD777AD80f6348844957f22eD7F0);
    }

    function onEncounterResolved(EventDetails memory details, EncounterResolvedEvent memory ev) external {
        EncounterResolved memory encounter = graph.getEncounterResolved(details.uniqueId());
        encounter.encounterId = ev.encounterId;
        encounter.winnerId = ev.winnerId;
        encounter.loserId = ev.loserId;
        encounter.winnerPlayer = ev.winnerPlayer;
        encounter.loserPlayer = ev.loserPlayer;
        encounter.timestamp = ev.timestamp;
        encounter.battleCycle = ev.battleCycle;
        encounter.transactionHash = details.transactionHash;

        graph.saveEncounterResolved(encounter);
    }
    function onTransfer(EventDetails memory details, TransferEvent memory ev) external {
        Transfer memory transfer = graph.getTransfer(details.uniqueId());
        transfer.from = ev.from;
        transfer.to = ev.to;
        transfer.tokenId = ev.tokenId;

        transfer.transactionHash = details.transactionHash;
        graph.saveTransfer(transfer);
    }
}
