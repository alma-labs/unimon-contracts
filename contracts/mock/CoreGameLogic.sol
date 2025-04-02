// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnimonEnergy} from "../UnimonEnergy.sol";

// Isolating the core game logic for testing purposes
contract UnimonHook is Ownable, ERC721 {
    address public constant NATIVE = address(0);
    uint256 public constant MAX_SUPPLY = 10000;
    uint256 public constant MAX_PER_SWAP = 2000;
    uint256 public constant MINT_PRICE = 0.00000111 ether;
    uint256 public constant MIN_LEVEL = 1;
    uint256 public constant MAX_LEVEL = 10;

    string public baseURI;
    uint256 public nextTokenId;
    bool public hatchingEnabled;
    UnimonEnergy public unimonEnergy;

    mapping(uint256 => UnimonData) public unimons;

    enum Status {
        UNHATCHED,
        HATCHED
    }

    struct UnimonData {
        Status status;
        uint256 level;
    }

    error AlreadyInitialized();
    error UnverifiedRouter();
    error NotOwnerOfToken();
    error HatchingDisabled();
    error InvalidTokenAmount();
    error AlreadyHatched();
    error InsufficientTokenBalance();
    error TokenTransferFailed();

    event UnimonHatched(uint256 indexed tokenId, uint256 tokenIncrement, uint256 level, bytes32 seed);

    constructor() Ownable(msg.sender) ERC721("Unimon", "UNIMON") {}

    /*
        View & Helper Functions
    */

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (tokenId >= nextTokenId) revert();
        return string(abi.encodePacked(baseURI, tokenId));
    }

    function getUnimonStatus(uint256 tokenId) external view returns (Status) {
        return unimons[tokenId].status;
    }

    function getUnimonData(uint256 tokenId) external view returns (UnimonData memory) {
        return unimons[tokenId];
    }

    /*
        Game Functions
    */

    function hatch(uint256 tokenId, uint256 tokenIncrement) external {
        if (!hatchingEnabled) revert HatchingDisabled();
        if (ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken();
        if (tokenIncrement < 1 || tokenIncrement > 10) revert InvalidTokenAmount();
        if (unimons[tokenId].status != Status.UNHATCHED) revert AlreadyHatched();

        // Token Burning Logic
        uint256 tokenAmount = tokenIncrement * (10 ** unimonEnergy.decimals());
        if (unimonEnergy.balanceOf(msg.sender) < tokenAmount) revert InsufficientTokenBalance();
        unimonEnergy.burn(msg.sender, tokenAmount);

        // Status Assignment & Level Calculation
        bytes32 seed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, tokenId));
        uint256 level = _calculateLevel(tokenIncrement, seed);
        unimons[tokenId].status = Status.HATCHED;
        unimons[tokenId].level = level;

        emit UnimonHatched(tokenId, tokenIncrement, level, seed);
    }

    // Uses pseudo-random number generator to calculate level, which is OK for the use case :)
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

    /*
        Admin Functions
    */

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setHatchingEnabled(bool _hatchingEnabled) external onlyOwner {
        hatchingEnabled = _hatchingEnabled;
    }

    function setUnimonEnergy(address _unimonEnergy) external onlyOwner {
        unimonEnergy = UnimonEnergy(_unimonEnergy);
    }

    function mint(uint256 amount) external payable {
        if (amount == 0 || amount > MAX_PER_SWAP) revert InvalidTokenAmount();
        if (msg.value != amount * MINT_PRICE) revert InvalidTokenAmount();
        if (nextTokenId + amount > MAX_SUPPLY) revert InvalidTokenAmount();

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, nextTokenId);
            unimons[nextTokenId] = UnimonData({status: Status.UNHATCHED, level: 0});
            nextTokenId++;
        }
    }
}
