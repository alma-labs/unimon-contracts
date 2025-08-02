// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./UnimonItems.sol";

contract UnimonGachaSimple is AccessControl, ReentrancyGuard {
    UnimonItems public immutable unimonItems;

    uint256[] public itemIds;
    uint256[] public weights;
    uint256 public totalWeight;
    uint256 public maxBulkOperations = 50;
    uint256[] public backupItemIds = [3, 4, 5];
    uint256 private backupIndex = 0;

    mapping(uint256 => uint256) public maxSupply;
    mapping(uint256 => uint256) public currentSupply;
    mapping(address => bool) public pendingGacha;
    mapping(address => uint256) public pendingAmount;
    mapping(address => uint256) public storedRandomness;

    event GachaBulkOpened(address indexed player, uint256[] itemIds, uint256[] amounts);
    event GachaUpdated(uint256[] itemIds, uint256[] weights);
    event GachaRequested(address indexed player, uint256 amount);

    constructor(address _unimonItems) {
        unimonItems = UnimonItems(_unimonItems);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*
        VIEW FUNCTIONS
    */

    function isRandomnessFulfilled(address user) external view returns (bool) {
        return storedRandomness[user] != 0;
    }

    function getPendingRequest(address user) external view returns (bool isPending, uint256 amount) {
        return (pendingGacha[user], pendingAmount[user]);
    }

    function getGacha()
        external
        view
        returns (uint256[] memory _itemIds, uint256[] memory _weights, uint256 _totalWeight)
    {
        return (itemIds, weights, totalWeight);
    }

    function getSupplyInfo(uint256 itemId) external view returns (uint256 current, uint256 max) {
        return (currentSupply[itemId], maxSupply[itemId]);
    }

    function getBackupItemIds() external view returns (uint256[] memory) {
        return backupItemIds;
    }

    /*
        USER FUNCTIONS
    */

    function requestGacha(uint256 amount) external nonReentrant {
        require(amount > 0 && amount <= maxBulkOperations, "Invalid amount");
        require(unimonItems.balanceOf(msg.sender, unimonItems.UNIKEY_ID()) >= amount, "Insufficient keys");
        require(totalWeight > 0, "No items configured");
        require(!pendingGacha[msg.sender], "Pending request exists");

        unimonItems.spendItem(msg.sender, unimonItems.UNIKEY_ID(), amount);
        pendingGacha[msg.sender] = true;
        pendingAmount[msg.sender] = amount;

        // Generate randomness internally using block data and user address
        storedRandomness[msg.sender] = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, blockhash(block.number - 1), amount)
            )
        );

        emit GachaRequested(msg.sender, amount);
    }

    function claimGacha() external nonReentrant {
        require(pendingGacha[msg.sender], "No pending request");
        require(storedRandomness[msg.sender] != 0, "Randomness not fulfilled");

        uint256 amount = pendingAmount[msg.sender];
        uint256 randomness = storedRandomness[msg.sender];

        pendingGacha[msg.sender] = false;
        pendingAmount[msg.sender] = 0;
        storedRandomness[msg.sender] = 0;

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

    function _getNextBackupItem() internal returns (uint256) {
        uint256 backupItemId = backupItemIds[backupIndex % backupItemIds.length];
        backupIndex++;
        return backupItemId;
    }

    /*
        ADMIN FUNCTIONS
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

    function setBackupItemIds(uint256[] memory _backupItemIds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_backupItemIds.length > 0, "Empty backup items array");
        backupItemIds = _backupItemIds;
        backupIndex = 0;
    }

    function setMaxBulkOperations(uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxBulkOperations = _max;
    }
}
