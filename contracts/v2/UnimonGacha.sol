// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./UnimonItems.sol";

/**
 * @title UnimonGacha
 * @author Unimon Team
 * @notice A gacha system for Unimon that allows players to spend keys to receive random items
 * @dev This contract implements a weighted random selection system with supply limits and backup items
 * 
 * The gacha system works as follows:
 * 1. Players request gacha pulls by spending UNIKEY tokens
 * 2. A randomness handler provides verifiable randomness
 * 3. Players claim their items based on the provided randomness
 * 4. Items are selected using weighted random distribution
 * 5. If an item reaches max supply, backup items are used instead
 * 
 * @custom:security This contract uses OpenZeppelin's AccessControl and ReentrancyGuard for security
 */
contract UnimonGacha is AccessControl, ReentrancyGuard {
    /// @notice Role for entities that can provide randomness for gacha pulls
    bytes32 public constant RANDOMNESS_HANDLER = keccak256("RANDOMNESS_HANDLER");

    /// @notice Reference to the UnimonItems contract for minting items
    UnimonItems public immutable unimonItems;

    /// @notice Array of item IDs available in the gacha pool
    uint256[] public itemIds;
    
    /// @notice Array of weights corresponding to each item ID (higher weight = higher chance)
    uint256[] public weights;
    
    /// @notice Total weight of all items in the gacha pool
    uint256 public totalWeight;
    
    /// @notice Maximum number of gacha pulls that can be requested in a single transaction
    uint256 public maxBulkOperations = 50;
    
    /// @notice Array of backup item IDs used when main items reach max supply
    uint256[] public backupItemIds = [9, 10, 11];
    
    /// @notice Index for cycling through backup items
    uint256 private backupIndex = 0;

    /// @notice Maximum supply for each item ID (0 means unlimited)
    mapping(uint256 => uint256) public maxSupply;
    
    /// @notice Current supply minted for each item ID
    mapping(uint256 => uint256) public currentSupply;
    
    /// @notice Whether a user has a pending gacha request
    mapping(address => bool) public pendingGacha;
    
    /// @notice Amount of gacha pulls requested by a user
    mapping(address => uint256) public pendingAmount;
    
    /// @notice Randomness value provided for a user's gacha request
    mapping(address => uint256) public requestedRandomness;

    /// @notice Emitted when a player successfully claims their gacha items
    /// @param player The address of the player
    /// @param itemIds Array of item IDs received
    /// @param amounts Array of amounts for each item (typically 1 for each)
    event GachaBulkOpened(address indexed player, uint256[] itemIds, uint256[] amounts);
    
    /// @notice Emitted when the gacha pool is updated by admin
    /// @param itemIds New array of item IDs
    /// @param weights New array of weights
    event GachaUpdated(uint256[] itemIds, uint256[] weights);
    
    /// @notice Emitted when a player requests gacha pulls
    /// @param player The address of the player
    /// @param amount Number of gacha pulls requested
    event GachaRequested(address indexed player, uint256 amount);
    
    /// @notice Emitted when randomness is fulfilled for a player
    /// @param player The address of the player
    /// @param randomness The randomness value provided
    event RandomnessFulfilled(address indexed player, uint256 randomness);

    /**
     * @notice Constructor for UnimonGacha contract
     * @param _unimonItems Address of the UnimonItems contract
     */
    constructor(address _unimonItems) {
        unimonItems = UnimonItems(_unimonItems);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RANDOMNESS_HANDLER, msg.sender);
    }

    /*
        VIEW FUNCTIONS
    */

    /**
     * @notice Check if randomness has been fulfilled for a user
     * @param user Address of the user to check
     * @return True if randomness has been fulfilled, false otherwise
     */
    function isRandomnessFulfilled(address user) external view returns (bool) {
        return requestedRandomness[user] != 0;
    }

    /**
     * @notice Get the pending gacha request for a user
     * @param user Address of the user to check
     * @return isPending Whether the user has a pending request
     * @return amount Number of gacha pulls requested
     */
    function getPendingRequest(address user) external view returns (bool isPending, uint256 amount) {
        return (pendingGacha[user], pendingAmount[user]);
    }

    /**
     * @notice Get the current gacha pool configuration
     * @return _itemIds Array of item IDs in the pool
     * @return _weights Array of weights for each item
     * @return _totalWeight Total weight of all items
     */
    function getGacha()
        external
        view
        returns (uint256[] memory _itemIds, uint256[] memory _weights, uint256 _totalWeight)
    {
        return (itemIds, weights, totalWeight);
    }

    /**
     * @notice Get supply information for a specific item
     * @param itemId The item ID to check
     * @return current Current supply minted
     * @return max Maximum supply allowed (0 means unlimited)
     */
    function getSupplyInfo(uint256 itemId) external view returns (uint256 current, uint256 max) {
        return (currentSupply[itemId], maxSupply[itemId]);
    }

    /**
     * @notice Get the current backup item IDs
     * @return Array of backup item IDs
     */
    function getBackupItemIds() external view returns (uint256[] memory) {
        return backupItemIds;
    }

    /*
        USER FUNCTIONS
    */

    /**
     * @notice Request gacha pulls by spending UNIKEY tokens
     * @param amount Number of gacha pulls to request (1 to maxBulkOperations)
     * @dev This function:
     * - Checks if user has enough UNIKEY tokens
     * - Spends the required amount of UNIKEY tokens
     * - Sets up a pending request for randomness fulfillment
     * - Emits GachaRequested event
     */
    function requestGacha(uint256 amount) external nonReentrant {
        require(amount > 0 && amount <= maxBulkOperations, "Invalid amount");
        require(unimonItems.balanceOf(msg.sender, unimonItems.UNIKEY_ID()) >= amount, "Insufficient keys");
        require(totalWeight > 0, "No items configured");
        require(!pendingGacha[msg.sender], "Pending request exists");

        unimonItems.spendItem(msg.sender, unimonItems.UNIKEY_ID(), amount);
        pendingGacha[msg.sender] = true;
        pendingAmount[msg.sender] = amount;
        requestedRandomness[msg.sender] = 0;

        emit GachaRequested(msg.sender, amount);
    }

    /**
     * @notice Claim gacha items after randomness has been fulfilled
     * @dev This function:
     * - Verifies randomness has been provided
     * - Uses weighted random selection to determine items
     * - Handles max supply limits by using backup items
     * - Mints items to the player
     * - Emits GachaBulkOpened event
     */
    function claimGacha() external nonReentrant {
        require(pendingGacha[msg.sender], "No pending request");
        require(requestedRandomness[msg.sender] != 0, "Randomness not fulfilled");

        uint256 amount = pendingAmount[msg.sender];
        uint256 randomness = requestedRandomness[msg.sender];

        pendingGacha[msg.sender] = false;
        pendingAmount[msg.sender] = 0;
        requestedRandomness[msg.sender] = 0;

        uint256[] memory itemIds_ = new uint256[](amount);
        uint256[] memory amounts_ = new uint256[](amount);

        for (uint256 i = 0; i < amount; i++) {
            uint256 selectedItemId = _getRandomItem(randomness, i);

            // Check if item has reached max supply
            if (maxSupply[selectedItemId] > 0 && currentSupply[selectedItemId] >= maxSupply[selectedItemId]) {
                // Use backup item
                uint256 backupItemId = _getNextBackupItem();
                itemIds_[i] = backupItemId;
                currentSupply[backupItemId]++;
            } else {
                itemIds_[i] = selectedItemId;
                currentSupply[selectedItemId]++;
            }
            amounts_[i] = 1;
        }

        unimonItems.mintBatch(msg.sender, itemIds_, amounts_);

        emit GachaBulkOpened(msg.sender, itemIds_, amounts_);
    }

    /*
        INTERNAL FUNCTIONS
    */

    /**
     * @notice Select a random item based on weighted distribution
     * @param baseRandomness The base randomness value provided
     * @param index Index to create unique randomness for each pull
     * @return itemId The selected item ID
     * @dev Uses keccak256 hash of baseRandomness and index to generate unique randomness
     * for each pull in a bulk operation
     */
    function _getRandomItem(uint256 baseRandomness, uint256 index) internal view returns (uint256 itemId) {
        uint256 randomValue = uint256(keccak256(abi.encodePacked(baseRandomness, index))) % totalWeight;

        uint256 currentWeight = 0;
        for (uint256 i = 0; i < itemIds.length; i++) {
            currentWeight += weights[i];
            if (randomValue < currentWeight) {
                return itemIds[i];
            }
        }

        return itemIds[0];
    }

    /**
     * @notice Get the next backup item in rotation
     * @return The backup item ID
     * @dev Cycles through backup items sequentially
     */
    function _getNextBackupItem() internal returns (uint256) {
        uint256 backupItemId = backupItemIds[backupIndex % backupItemIds.length];
        backupIndex++;
        return backupItemId;
    }

    /*
        ADMIN FUNCTIONS
    */

    /**
     * @notice Fulfill randomness for a user's gacha request
     * @param user Address of the user
     * @param randomness The randomness value to provide
     * @dev Only callable by RANDOMNESS_HANDLER role
     */
    function fulfillRandomness(address user, uint256 randomness) external onlyRole(RANDOMNESS_HANDLER) {
        require(pendingGacha[user], "No pending request");

        requestedRandomness[user] = randomness;
        emit RandomnessFulfilled(user, randomness);
    }

    /**
     * @notice Update the gacha pool with new items and weights
     * @param _itemIds Array of new item IDs
     * @param _weights Array of weights corresponding to each item ID
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Arrays must have the same length and weights must be greater than 0
     */
    function updateGacha(uint256[] memory _itemIds, uint256[] memory _weights) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_itemIds.length == _weights.length, "Array length mismatch");
        require(_itemIds.length > 0, "Empty arrays");

        uint256 _totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            require(_weights[i] > 0, "Invalid weight");
            _totalWeight += _weights[i];
        }

        itemIds = _itemIds;
        weights = _weights;
        totalWeight = _totalWeight;

        emit GachaUpdated(_itemIds, _weights);
    }

    /**
     * @notice Set maximum supply for multiple items
     * @param _itemIds Array of item IDs
     * @param _maxSupplies Array of maximum supplies (0 means unlimited)
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Arrays must have the same length
     */
    function setMaxSupply(
        uint256[] memory _itemIds,
        uint256[] memory _maxSupplies
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_itemIds.length == _maxSupplies.length, "Array length mismatch");
        require(_itemIds.length > 0, "Empty arrays");

        for (uint256 i = 0; i < _itemIds.length; i++) {
            maxSupply[_itemIds[i]] = _maxSupplies[i];
        }
    }

    /**
     * @notice Set new backup item IDs
     * @param _backupItemIds Array of new backup item IDs
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Resets the backup index to 0
     */
    function setBackupItemIds(uint256[] memory _backupItemIds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_backupItemIds.length > 0, "Empty backup items array");
        backupItemIds = _backupItemIds;
        backupIndex = 0;
    }

    /**
     * @notice Set the maximum number of bulk operations allowed
     * @param _max Maximum number of gacha pulls per transaction
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function setMaxBulkOperations(uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxBulkOperations = _max;
    }
}
