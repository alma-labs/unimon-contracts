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
        graph.registerHandle(0xD292945e0Aa30346A416c583d9Fd2616C712Ee4d);
        graph.registerHandle(0x3f2386e192f5FAB3cdc013E652586fE2Ca49973A);
        graph.registerHandle(0xE5c8B5C8a75f49eFeC86AFc4367E8c914b143192); // GM
        graph.registerHandle(0x3513d29eD9A790C4b0c81829055927eBE9CD7159); // UnimonSlayer
    }

    function onGoodMorning(EventDetails memory details, GoodMorningEvent memory ev) external {
        GoodMorning memory gm = graph.getGoodMorning(details.uniqueId());
        gm.user = ev.user;
        gm.tokenId = ev.tokenId;
        gm.day = ev.day;
        gm.timestamp = ev.timestamp;
        gm.currentStreak = ev.currentStreak;
        gm.bestStreak = ev.bestStreak;
        gm.transactionHash = details.transactionHash;

        graph.saveGoodMorning(gm);
    }

    function onMonsterFought(EventDetails memory details, MonsterFoughtEvent memory ev) external {
        MonsterFought memory fight = graph.getMonsterFought(details.uniqueId());
        fight.user = ev.user;
        fight.tokenId = ev.tokenId;
        fight.monsterId = ev.monsterId;
        fight.won = ev.won;
        fight.power = ev.power;
        fight.difficulty = ev.difficulty;
        fight.transactionHash = details.transactionHash;

        graph.saveMonsterFought(fight);
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
