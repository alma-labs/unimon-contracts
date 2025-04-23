// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestEnergy} from "./TestEnergy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UnimonTesting is Ownable, ERC721Enumerable {
    /// @notice Minimum level a Unimon can have
    uint256 public constant MIN_LEVEL = 1;
    /// @notice Maximum level a Unimon can have
    uint256 public constant MAX_LEVEL = 10;

    /// @notice Base URI for token metadata
    string public baseURI;
    /// @notice Next token ID to be minted
    uint256 public nextTokenId;
    /// @notice Reference to the UnimonEnergy token contract
    TestEnergy public unimonEnergy;

    /// @notice Mapping of token ID to Unimon data
    mapping(uint256 => UnimonData) public unimons;

    /// @notice Enum representing the status of a Unimon
    enum Status {
        UNHATCHED,
        HATCHED
    }

    /// @notice Struct containing Unimon data
    struct UnimonData {
        Status status;
        uint256 level;
    }

    /// @notice Error thrown when contract is already initialized
    error AlreadyInitialized();
    /// @notice Error thrown when router is not verified
    error UnverifiedRouter();
    /// @notice Error thrown when caller is not the token owner
    error NotOwnerOfToken();
    /// @notice Error thrown when token amount is invalid
    error InvalidTokenAmount();
    /// @notice Error thrown when Unimon is already hatched
    error AlreadyHatched();
    /// @notice Error thrown when token balance is insufficient
    error InsufficientTokenBalance();
    /// @notice Error thrown when token transfer fails
    error TokenTransferFailed();
    /// @notice Error thrown when name is too long
    error NameTooLong();
    /// @notice Error thrown when name is empty
    error EmptyName();

    /// @notice Event emitted when a Unimon is hatched
    event UnimonHatched(uint256 indexed tokenId, uint256 tokenIncrement, uint256 level, bytes32 seed);
    /// @notice Event emitted when a Unimon's name is changed
    event NameChanged(uint256 indexed tokenId, string newName);

    constructor(address _owner) Ownable(_owner) ERC721("Test", "Test1") {}

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              View Functions                               //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns the token URI for a given token ID
     * @param tokenId The ID of the token
     * @return The complete token URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory baseURI_ = _baseURI();
        return bytes(baseURI_).length > 0 ? string(abi.encodePacked(baseURI_, Strings.toString(tokenId))) : "";
    }

    /**
     * @notice Returns the base URI for token metadata
     * @return The base URI string
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @notice Returns the complete data of a Unimon
     * @param tokenId The ID of the Unimon
     * @return The UnimonData struct containing status and level
     */
    function getUnimonData(uint256 tokenId) external view returns (UnimonData memory) {
        return unimons[tokenId];
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              Game Functions                               //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Hatches a Unimon, increasing its level
     * @param tokenId The ID of the Unimon to hatch
     * @param tokenIncrement The amount of tokens to burn for hatching
     */
    function hatch(uint256 tokenId, uint256 tokenIncrement) external {
        if (ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken();
        if (tokenIncrement < 1 || tokenIncrement > 10) revert InvalidTokenAmount();
        if (unimons[tokenId].status != Status.UNHATCHED) revert AlreadyHatched();

        uint256 tokenAmount = tokenIncrement * (10 ** unimonEnergy.decimals());
        if (unimonEnergy.balanceOf(msg.sender) < tokenAmount) revert InsufficientTokenBalance();
        unimonEnergy.burn(msg.sender, tokenAmount);

        bytes32 seed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, tokenId));
        uint256 level = _calculateLevel(tokenIncrement, seed);
        unimons[tokenId].status = Status.HATCHED;
        unimons[tokenId].level = level;

        emit UnimonHatched(tokenId, tokenIncrement, level, seed);
    }

    /**
     * @notice Calculates the level of a Unimon based on token increment and seed
     * @param tokenIncrement The amount of tokens burned
     * @param seed The random seed for level calculation
     * @return The calculated level
     */
    function _calculateLevel(uint256 tokenIncrement, bytes32 seed) internal view returns (uint256) {
        uint256 hash = uint256(keccak256(abi.encodePacked(seed, block.timestamp, msg.sender)));

        uint256 baseLevel = MIN_LEVEL + (tokenIncrement / 2);
        uint256 maxBonus = tokenIncrement - baseLevel;
        uint256 bonusRoll = hash % 100;
        uint256 bonusLevel = 0;

        if (bonusRoll < 20 + (tokenIncrement * 6)) {
            bonusLevel = maxBonus > 0 ? 1 + (hash % maxBonus) : 0;
        }

        uint256 finalLevel = baseLevel + bonusLevel;
        return finalLevel > MAX_LEVEL ? MAX_LEVEL : finalLevel;
    }

    function mint() external {
        uint256 tokenId = nextTokenId++;
        _mint(msg.sender, tokenId);
        unimons[tokenId] = UnimonData({status: Status.UNHATCHED, level: 0});
    }

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              Admin Functions                              //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////s

    /**
     * @notice Sets the base URI for token metadata
     * @param newBaseURI The new base URI to set
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    /**
     * @notice Sets the UnimonEnergy token contract address
     * @param _unimonEnergy The address of the UnimonEnergy contract
     */
    function setUnimonEnergy(address _unimonEnergy) external onlyOwner {
        unimonEnergy = TestEnergy(_unimonEnergy);
    }

    /*
    ERC721Enumerable overrides
    */

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
