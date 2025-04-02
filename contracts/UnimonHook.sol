// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook, Hooks, IPoolManager, PoolKey} from "../lib/uniswap-hooks/src/base/BaseHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UnimonEnergy} from "./UnimonEnergy.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface IMsgSender {
    function msgSender() external view returns (address);
}

/**
 * @title UnimonHook
 * @notice A Uniswap V4 hook contract that implements NFT minting and game mechanics
 * @dev Extends BaseHook, Ownable, and ERC721 to provide NFT functionality with Uniswap integration
 */
contract UnimonHook is BaseHook, Ownable, ERC721Enumerable {
    /// @notice Native token address (ETH)
    address public constant NATIVE = address(0);
    /// @notice Maximum number of NFTs that can be minted
    uint256 public constant MAX_SUPPLY = 10000;
    /// @notice Maximum number of NFTs that can be minted in a single swap
    uint256 public constant MAX_PER_SWAP = 100;
    /// @notice Price in ETH required to mint one NFT
    uint256 public constant MINT_PRICE = 0.0111 ether;
    /// @notice Minimum level a Unimon can have
    uint256 public constant MIN_LEVEL = 1;
    /// @notice Maximum level a Unimon can have
    uint256 public constant MAX_LEVEL = 10;
    /// @notice Maximum length for a Unimon's name
    uint256 public constant MAX_NAME_LENGTH = 32;

    /// @notice Base URI for token metadata
    string public baseURI;
    /// @notice Next token ID to be minted
    uint256 public nextTokenId;
    /// @notice Whether hatching is currently enabled
    bool public hatchingEnabled;
    /// @notice Whether initial liquidity has been added
    bool public initialLiquidityAdded;
    /// @notice Pool key for the Uniswap pool
    PoolKey public poolKey;
    /// @notice Reference to the UnimonEnergy token contract
    UnimonEnergy public unimonEnergy;

    /// @notice Mapping of token ID to Unimon data
    mapping(uint256 => UnimonData) public unimons;
    /// @notice Mapping of router addresses to verification status
    mapping(address => bool) public verifiedRouters;
    /// @notice Mapping of swap keys to actual sender addresses
    mapping(bytes32 => address) public swapSenders;

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
    /// @notice Error thrown when hatching is disabled
    error HatchingDisabled();
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

    /**
     * @notice Constructor for UnimonHook
     * @param _poolManager Address of the Uniswap pool manager
     * @param _owner Address of the contract owner
     */
    constructor(
        IPoolManager _poolManager,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) ERC721("UnimonHook", "UNIMON") {
        verifiedRouters[0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3] = true;
    }

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
     * @notice Returns the status of a Unimon
     * @param tokenId The ID of the Unimon
     * @return The status of the Unimon
     */
    function getUnimonStatus(uint256 tokenId) external view returns (Status) {
        return unimons[tokenId].status;
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
    //                              Hook Functions                               //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns the hook permissions for this contract
     * @return permissions The Hooks.Permissions struct containing permission flags
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /**
     * @notice Hook function called before a swap
     * @param sender The address initiating the swap
     * @param key The pool key
     * @param params The swap parameters
     * @return The selector, swap delta, and hook fee
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!verifiedRouters[sender]) {
            revert UnverifiedRouter();
        }

        address actualSender = IMsgSender(sender).msgSender();
        bytes32 swapKey = keccak256(abi.encodePacked(block.timestamp, actualSender, params.amountSpecified));
        swapSenders[swapKey] = actualSender;

        bool isNativeInput = params.zeroForOne
            ? Currency.unwrap(key.currency0) == NATIVE
            : Currency.unwrap(key.currency1) == NATIVE;
        require(isNativeInput, "Input token must be native currency");

        return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
    }

    /**
     * @notice Hook function called after a swap
     * @param sender The address initiating the swap
     * @param params The swap parameters
     * @return The selector and hook fee
     */
    function _afterSwap(
        address sender,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, int128) {
        bytes32 swapKey = keccak256(
            abi.encodePacked(block.timestamp, IMsgSender(sender).msgSender(), params.amountSpecified)
        );
        address actualSender = swapSenders[swapKey];
        uint256 amountToMint = uint256(-params.amountSpecified) / MINT_PRICE;

        if (amountToMint == 0) {
            delete swapSenders[swapKey];
            return (this.afterSwap.selector, 0);
        }

        require(actualSender != address(0), "Invalid swap sender");
        require(amountToMint <= MAX_PER_SWAP, "Too many NFTs minted in a single swap");
        require(nextTokenId + amountToMint < MAX_SUPPLY, "Cannot mint more than max supply");

        for (uint256 i = 0; i < amountToMint; i++) {
            uint256 tokenId = nextTokenId;
            _mint(actualSender, tokenId);
            unimons[tokenId] = UnimonData({status: Status.UNHATCHED, level: 0});
            nextTokenId++;
        }

        delete swapSenders[swapKey];
        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Hook function called before adding liquidity
     * @return The selector
     */
    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        require(!initialLiquidityAdded, "Can only add liquidity once, don't fuck up.");
        initialLiquidityAdded = true;
        return this.beforeAddLiquidity.selector;
    }

    /**
     * @notice Hook function called before initializing the pool
     * @param key The pool key
     * @return The selector
     */
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (address(poolKey.hooks) != address(0)) revert AlreadyInitialized();
        poolKey = key;
        return this.beforeInitialize.selector;
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
        if (!hatchingEnabled) revert HatchingDisabled();
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

    ///////////////////////////////////////////////////////////////////////////////
    //                                                                           //
    //                              Admin Functions                              //
    //                                                                           //
    ///////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Toggles the verification status of a router
     * @param router The address of the router to toggle
     */
    function toggleRouter(address router) external onlyOwner {
        verifiedRouters[router] = !verifiedRouters[router];
    }

    /**
     * @notice Sets the base URI for token metadata
     * @param newBaseURI The new base URI to set
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    /**
     * @notice Sets whether hatching is enabled
     * @param _hatchingEnabled The new hatching status
     */
    function setHatchingEnabled(bool _hatchingEnabled) external onlyOwner {
        hatchingEnabled = _hatchingEnabled;
    }

    /**
     * @notice Sets the UnimonEnergy token contract address
     * @param _unimonEnergy The address of the UnimonEnergy contract
     */
    function setUnimonEnergy(address _unimonEnergy) external onlyOwner {
        unimonEnergy = UnimonEnergy(_unimonEnergy);
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
