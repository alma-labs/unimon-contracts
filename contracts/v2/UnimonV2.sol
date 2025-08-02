// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {UnimonItems} from "./UnimonItems.sol";

/**
 * @title UnimonV2
 * @author Unimon Team
 * @notice ERC721 NFT contract for Unimon characters with evolution mechanics
 * @dev This contract implements the core Unimon NFT functionality
 * 
 * Key features:
 * - ERC721 standard with enumeration and burnable extensions
 * - Evolution system using energy tokens
 * - Customizable names for each Unimon
 * - Attack and defense stats with random evolution bonuses
 * - Supply management with configurable max supply
 * - Role-based access control for minting
 * 
 * @custom:security This contract uses OpenZeppelin's AccessControl, ERC721Burnable, and ERC721Enumerable
 */
contract UnimonV2 is ERC721, ERC721Enumerable, AccessControl, ERC721Burnable {
    /// @notice Role for entities that can mint new Unimon NFTs
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @notice Reference to the UnimonItems contract for energy consumption
    UnimonItems public unimonItems;
    
    /// @notice Next token ID to be minted
    uint256 private _nextTokenId;
    
    /// @notice Maximum supply of Unimon NFTs
    uint256 public maxSupply = 10000;
    
    /// @notice Whether evolution functionality is currently enabled
    bool public evolutionsEnabled = true;

    /// @notice Mapping of token ID to Unimon stats
    mapping(uint256 => UnimonStats) public unimonStats;

    /// @notice Structure containing Unimon character statistics
    /// @param attackLevel Current attack level (1-10)
    /// @param defenseLevel Current defense level (1-10)
    /// @param evolved Whether this Unimon has been evolved
    /// @param name Custom name given to this Unimon
    struct UnimonStats {
        uint256 attackLevel;
        uint256 defenseLevel;
        bool evolved;
        string name;
    }

    /// @notice Emitted when a Unimon is evolved
    /// @param tokenId ID of the evolved Unimon
    /// @param energyAmount Amount of energy used for evolution
    /// @param newAttackLevel New attack level after evolution
    /// @param newDefenseLevel New defense level after evolution
    event UnimonEvolved(uint256 indexed tokenId, uint256 energyAmount, uint256 newAttackLevel, uint256 newDefenseLevel);
    
    /// @notice Emitted when a Unimon's name is set
    /// @param tokenId ID of the Unimon
    /// @param name New name for the Unimon
    event UnimonNameSet(uint256 indexed tokenId, string name);
    
    /// @notice Emitted when max supply is updated
    /// @param oldMaxSupply Previous max supply value
    /// @param newMaxSupply New max supply value
    event MaxSupplyUpdated(uint256 oldMaxSupply, uint256 newMaxSupply);
    
    /// @notice Emitted when evolution functionality is toggled
    /// @param enabled Whether evolutions are now enabled or disabled
    event EvolutionsToggled(bool enabled);

    /**
     * @notice Constructor for UnimonV2 contract
     * @param _unimonItems Address of the UnimonItems contract
     */
    constructor(address _unimonItems) ERC721("UnimonV2", "UNIMON") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        unimonItems = UnimonItems(_unimonItems);
    }

    /* 
        VIEW FUNCTIONS
    */

    /**
     * @notice Get the base URI for token metadata
     * @return Base URI string for token metadata
     * @dev Override of ERC721 _baseURI function
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://v2.unimon.app/unimon/";
    }

    /**
     * @notice Mint a new Unimon NFT to an address
     * @param to Address to mint the NFT to
     * @return tokenId ID of the newly minted NFT
     * @dev Only callable by MINTER_ROLE
     * @dev Creates default stats (attack: 1, defense: 1, evolved: false)
     * @dev Assigns default name "Unimon #[tokenId]"
     */
    function safeMint(address to) public onlyRole(MINTER_ROLE) returns (uint256) {
        require(_nextTokenId < maxSupply, "Hard cap reached");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        string memory defaultName = string(abi.encodePacked("Unimon #", Strings.toString(tokenId)));
        unimonStats[tokenId] = UnimonStats({attackLevel: 1, defenseLevel: 1, evolved: false, name: defaultName});

        return tokenId;
    }

    /**
     * @notice Get the stats for a specific Unimon
     * @param tokenId ID of the Unimon to get stats for
     * @return attackLevel Current attack level
     * @return defenseLevel Current defense level
     * @return evolved Whether the Unimon has been evolved
     * @return name Custom name of the Unimon
     * @dev Reverts if token does not exist
     */
    function getUnimonStats(
        uint256 tokenId
    ) external view returns (uint256 attackLevel, uint256 defenseLevel, bool evolved, string memory name) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        UnimonStats memory stats = unimonStats[tokenId];
        return (stats.attackLevel, stats.defenseLevel, stats.evolved, stats.name);
    }

    /**
     * @notice Get the name of a specific Unimon
     * @param tokenId ID of the Unimon to get name for
     * @return name Custom name of the Unimon
     * @dev Reverts if token does not exist
     */
    function getUnimonName(uint256 tokenId) external view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return unimonStats[tokenId].name;
    }

    /**
     * @notice Get all Unimon owned by an address with their stats
     * @param owner Address to get Unimon for
     * @return tokenIds Array of token IDs owned by the address
     * @return attackLevels Array of attack levels for each Unimon
     * @return defenseLevels Array of defense levels for each Unimon
     * @return evolvedStates Array of evolution states for each Unimon
     * @return names Array of names for each Unimon
     */
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

    /**
     * @notice Set the maximum supply of Unimon NFTs
     * @param _maxSupply New maximum supply value
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Cannot be set below current supply
     */
    function setMaxSupply(uint256 _maxSupply) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSupply >= _nextTokenId, "Cannot set max supply below current supply");
        uint256 oldMaxSupply = maxSupply;
        maxSupply = _maxSupply;
        emit MaxSupplyUpdated(oldMaxSupply, _maxSupply);
    }

    /**
     * @notice Get the current number of minted Unimon
     * @return Current supply count
     */
    function getCurrentSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice Get the remaining number of Unimon that can be minted
     * @return Remaining supply available for minting
     */
    function getRemainingSupply() external view returns (uint256) {
        return maxSupply - _nextTokenId;
    }

    /*
        INTERNAL FUNCTIONS
    */

    /**
     * @notice Calculate evolution stat bonuses based on energy amount
     * @param energyAmount Amount of energy used for evolution (1-10)
     * @param tokenId ID of the Unimon being evolved
     * @return attackBonus Bonus attack points to add
     * @return defenseBonus Bonus defense points to add
     * @dev Uses deterministic randomness based on tokenId, timestamp, sender, and energy amount
     * @dev Total stats range from energyAmount to 2x energyAmount (capped at 18)
     * @dev Each stat is capped at 9 bonus points (total stat max 10)
     * @dev Higher energy amounts have 40% chance to reduce total stats by 1
     */
    function _calculateEvolutionStats(
        uint256 energyAmount,
        uint256 tokenId
    ) internal view returns (uint256 attackBonus, uint256 defenseBonus) {
        bytes32 seed = keccak256(abi.encodePacked(tokenId, block.timestamp, msg.sender, energyAmount));
        uint256 hash = uint256(seed);

        // Choose total stats between energyAmount and 2x energy amount
        uint256 minStats = energyAmount;
        uint256 maxStats = energyAmount * 2;

        uint256 totalStats = minStats + (hash % (maxStats - minStats + 1));

        // Cap totalStats at 18 (max possible with 9+9)
        if (totalStats > 18) {
            totalStats = 18;
        }

        if (energyAmount >= 9) {
            // 40% chance to reduce totalStats by 1
            uint256 biasSeed = uint256(keccak256(abi.encodePacked(seed, "bias")));
            if (biasSeed % 100 < 40) {
                if (totalStats > minStats + 1) {
                    totalStats -= 1;
                }
            }
        }

        // Randomly distribute between attack and defense
        uint256 attackSeed = uint256(keccak256(abi.encodePacked(seed, "attack")));
        attackBonus = attackSeed % (totalStats + 1); // 0 to totalStats
        defenseBonus = totalStats - attackBonus;

        // Cap each skill at 9 bonus (since base is 1, total will be 10)
        // Redistribute excess to ensure no stats are lost
        if (attackBonus > 9) {
            uint256 excess = attackBonus - 9;
            attackBonus = 9;
            defenseBonus = defenseBonus + excess;
        }
        if (defenseBonus > 9) {
            uint256 excess = defenseBonus - 9;
            defenseBonus = 9;
            attackBonus = attackBonus + excess > 9 ? 9 : attackBonus + excess;
        }

        return (attackBonus, defenseBonus);
    }

    /*
        USER WRITE FUNCTIONS
    */

    /**
     * @notice Evolve a Unimon using energy tokens
     * @param tokenId ID of the Unimon to evolve
     * @param energyAmount Amount of energy to use for evolution (1-10)
     * @dev This function:
     * - Verifies ownership of the Unimon
     * - Validates energy amount and availability
     * - Consumes energy tokens
     * - Calculates random stat bonuses
     * - Updates Unimon stats and marks as evolved
     * - Emits UnimonEvolved event
     */
    function evolve(uint256 tokenId, uint256 energyAmount) external {
        require(ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(energyAmount >= 1 && energyAmount <= 10, "Energy amount must be 1-10");
        require(!unimonStats[tokenId].evolved, "Unimon already evolved");
        require(evolutionsEnabled, "Evolutions are currently disabled");

        uint256 energyId = unimonItems.ENERGY_ID();
        require(unimonItems.balanceOf(msg.sender, energyId) > 0, "Insufficient energy");
        unimonItems.spendItem(msg.sender, energyId, energyAmount);

        (uint256 attackBonus, uint256 defenseBonus) = _calculateEvolutionStats(energyAmount, tokenId);
        uint256 newAttackLevel = unimonStats[tokenId].attackLevel + attackBonus;
        uint256 newDefenseLevel = unimonStats[tokenId].defenseLevel + defenseBonus;

        unimonStats[tokenId].attackLevel = newAttackLevel;
        unimonStats[tokenId].defenseLevel = newDefenseLevel;
        unimonStats[tokenId].evolved = true;

        emit UnimonEvolved(tokenId, energyAmount, newAttackLevel, newDefenseLevel);
    }

    /**
     * @notice Set a custom name for a Unimon
     * @param tokenId ID of the Unimon to name
     * @param name New name for the Unimon (1-24 characters)
     * @dev Only the owner of the Unimon can set its name
     * @dev Name cannot be empty or longer than 24 characters
     */
    function setUnimonName(uint256 tokenId, string calldata name) external {
        require(ownerOf(tokenId) == msg.sender, "You don't own this Unimon");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(name).length <= 24, "Name too long");

        unimonStats[tokenId].name = name;
        emit UnimonNameSet(tokenId, name);
    }

    /**
     * @notice Toggle whether evolution functionality is enabled
     * @param _enabled Whether to enable or disable evolutions
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function toggleEvolutions(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        evolutionsEnabled = _enabled;
        emit EvolutionsToggled(_enabled);
    }

    /*
        OVERRIDES
    */

    /**
     * @dev Override to support both ERC721 and ERC721Enumerable
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override to support both ERC721 and ERC721Enumerable
     */
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /**
     * @dev Override to support ERC721, ERC721Enumerable, and AccessControl interfaces
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
