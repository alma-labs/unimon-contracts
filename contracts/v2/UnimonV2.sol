// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {UnimonItems} from "./UnimonItems.sol";

contract UnimonV2 is ERC721, ERC721Enumerable, AccessControl, ERC721Burnable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    UnimonItems public unimonItems;
    uint256 private _nextTokenId;

    mapping(uint256 => UnimonStats) public unimonStats;

    struct UnimonStats {
        uint256 attackLevel;
        uint256 defenseLevel;
        bool evolved;
        string name;
    }

    event UnimonEvolved(uint256 indexed tokenId, uint256 newAttackLevel, uint256 newDefenseLevel);
    event UnimonNameSet(uint256 indexed tokenId, string name);

    constructor(address _unimonItems) ERC721("UnimonV2", "UNIMON") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        unimonItems = UnimonItems(_unimonItems);
    }

    /* 
        VIEW FUNCTIONS
    */

    function _baseURI() internal pure override returns (string memory) {
        return "https://v2.unimon.app/";
    }

    function safeMint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        unimonStats[tokenId] = UnimonStats({attackLevel: 1, defenseLevel: 1, evolved: false, name: ""});

        return tokenId;
    }

    function getUnimonStats(
        uint256 tokenId
    ) external view returns (uint256 attackLevel, uint256 defenseLevel, bool evolved, string memory name) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        UnimonStats memory stats = unimonStats[tokenId];
        return (stats.attackLevel, stats.defenseLevel, stats.evolved, stats.name);
    }

    function getUnimonName(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return unimonStats[tokenId].name;
    }

    function getAllUnimonForAddress(
        address owner
    )
        external
        view
        returns (
            uint256[] memory tokenIds,
            uint256[] memory attackLevels,
            uint256[] memory defenseLevels,
            bool[] memory evolvedStates,
            string[] memory names
        )
    {
        uint256 balance = balanceOf(owner);
        tokenIds = new uint256[](balance);
        attackLevels = new uint256[](balance);
        defenseLevels = new uint256[](balance);
        evolvedStates = new bool[](balance);
        names = new string[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            tokenIds[i] = tokenId;

            UnimonStats memory stats = unimonStats[tokenId];
            attackLevels[i] = stats.attackLevel;
            defenseLevels[i] = stats.defenseLevel;
            evolvedStates[i] = stats.evolved;
            names[i] = stats.name;
        }
    }

    /*
        USER WRITE FUNCTIONS
    */

    function evolve(uint256 tokenId, uint256 energyAmount) external {
        require(ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(energyAmount >= 1 && energyAmount <= 10, "Energy amount must be 1-10");

        uint256 energyId = unimonItems.ENERGY_ID();
        require(unimonItems.balanceOf(msg.sender, energyId) > 0, "Insufficient energy");
        unimonItems.spendItem(msg.sender, energyId, 1);

        // TODO: Add evolution logic
        uint256 newAttackLevel = unimonStats[tokenId].attackLevel + energyAmount;
        uint256 newDefenseLevel = unimonStats[tokenId].defenseLevel + energyAmount;

        unimonStats[tokenId].attackLevel = newAttackLevel;
        unimonStats[tokenId].defenseLevel = newDefenseLevel;
        unimonStats[tokenId].evolved = true;

        emit UnimonEvolved(tokenId, newAttackLevel, newDefenseLevel);
    }

    function setUnimonName(uint256 tokenId, string calldata name) external {
        require(ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(name).length <= 24, "Name too long");

        unimonStats[tokenId].name = name;
        emit UnimonNameSet(tokenId, name);
    }

    /*
        OVERRIDES
    */

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
