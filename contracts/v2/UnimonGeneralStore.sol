// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./UnimonItems.sol";

// Interface for ERC20 tokens with metadata
interface IERC20Metadata is IERC20 {
    function symbol() external view returns (string memory);
}

/**
 * @title UnimonGeneralStore
 * @notice A contract for redeeming Unimon items for ERC20 tokens at configured rates
 * @dev This contract allows users to turn in specific items for different ERC20 tokens
 *
 * Key features:
 * - Configure redemption rates for any item ID to any ERC20 token
 * - Single and bulk redemption functions
 * - Owner can withdraw tokens and configure redemptions
 * - View functions to check redemption info and token balances
 *
 * @custom:security This contract uses OpenZeppelin's Ownable, ReentrancyGuard, and SafeERC20
 */
contract UnimonGeneralStore is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Reference to the UnimonItems contract
    UnimonItems public immutable items;

    /// @notice Mapping from item ID to token redemption configuration
    mapping(uint256 => TokenRedemption) public tokenRedemptions;

    /**
     * @notice Token redemption configuration for an item
     * @param token ERC20 token address to give in exchange
     * @param amount Amount of tokens to give per item redeemed
     * @param isActive Whether this redemption is currently active
     */
    struct TokenRedemption {
        address token;
        uint256 amount;
        bool isActive;
    }

    /**
     * @notice Extended redemption info including token metadata and contract balance
     * @param token ERC20 token address
     * @param amount Amount of tokens per item
     * @param isActive Whether redemption is active
     * @param tokenSymbol Symbol of the ERC20 token
     * @param contractBalance Current balance of tokens in this contract
     */
    struct TokenRedemptionInfo {
        address token;
        uint256 amount;
        bool isActive;
        string tokenSymbol;
        uint256 contractBalance;
    }

    /// @notice Emitted when a token redemption configuration is set
    event TokenRedemptionSet(uint256 indexed itemId, address indexed token, uint256 amount);

    /// @notice Emitted when tokens are redeemed for items
    event TokensRedeemed(
        address indexed redeemer,
        uint256 indexed itemId,
        uint256 amount,
        uint256 totalTokenAmount,
        address token
    );

    /// @notice Emitted when token redemption configurations are deleted
    event TokenRedemptionsDeleted(uint256[] itemIds);

    /**
     * @notice Constructor for UnimonGeneralStore
     * @param _items Address of the UnimonItems contract
     * @dev The deployer becomes the owner
     */
    constructor(address _items) Ownable(msg.sender) {
        items = UnimonItems(_items);
    }

    /*
        VIEW FUNCTIONS
    */

    /**
     * @notice Get detailed redemption info for a specific item
     * @param itemId Item ID to check redemption for
     * @return TokenRedemptionInfo struct with all redemption details
     */
    function getTokenRedemptionInfo(uint256 itemId) external view returns (TokenRedemptionInfo memory) {
        return _getTokenRedemptionInfo(itemId);
    }

    /**
     * @notice Get detailed redemption info for multiple items
     * @param itemIds Array of item IDs to check
     * @return Array of TokenRedemptionInfo structs
     */
    function getBulkTokenRedemptionInfo(
        uint256[] calldata itemIds
    ) external view returns (TokenRedemptionInfo[] memory) {
        TokenRedemptionInfo[] memory infos = new TokenRedemptionInfo[](itemIds.length);

        for (uint256 i = 0; i < itemIds.length; i++) {
            infos[i] = _getTokenRedemptionInfo(itemIds[i]);
        }

        return infos;
    }

    /**
     * @notice Internal function to get token redemption info with metadata
     * @param itemId Item ID to check
     * @return TokenRedemptionInfo struct with all details
     */
    function _getTokenRedemptionInfo(uint256 itemId) internal view returns (TokenRedemptionInfo memory) {
        TokenRedemption memory redemption = tokenRedemptions[itemId];

        string memory symbol = "";
        uint256 contractBalance = 0;

        if (redemption.isActive && redemption.token != address(0)) {
            try IERC20Metadata(redemption.token).symbol() returns (string memory _symbol) {
                symbol = _symbol;
            } catch {}

            contractBalance = IERC20(redemption.token).balanceOf(address(this));
        }

        return
            TokenRedemptionInfo({
                token: redemption.token,
                amount: redemption.amount,
                isActive: redemption.isActive,
                tokenSymbol: symbol,
                contractBalance: contractBalance
            });
    }

    /*
        PUBLIC FUNCTIONS
    */

    /**
     * @notice Redeem items for ERC20 tokens
     * @param itemId Item ID to redeem
     * @param amount Amount of items to redeem
     * @dev Burns the items from user's balance and transfers tokens
     */
    function redeemForToken(uint256 itemId, uint256 amount) public nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        TokenRedemption memory redemption = tokenRedemptions[itemId];
        require(redemption.isActive, "Token redemption not active for this item");
        require(redemption.token != address(0), "Invalid token address");

        // Calculate total token amount to give
        uint256 totalTokenAmount = amount * redemption.amount;
        require(IERC20(redemption.token).balanceOf(address(this)) >= totalTokenAmount, "Insufficient token balance");

        // Burn the items from the user
        items.spendItem(msg.sender, itemId, amount);

        // Transfer tokens to the user
        IERC20(redemption.token).safeTransfer(msg.sender, totalTokenAmount);

        emit TokensRedeemed(msg.sender, itemId, amount, totalTokenAmount, redemption.token);
    }

    /**
     * @notice Redeem multiple different items for their respective tokens in one transaction
     * @param itemIds Array of item IDs to redeem
     * @param amounts Array of amounts for each item
     * @dev Arrays must have the same length
     */
    function bulkRedeemForToken(uint256[] calldata itemIds, uint256[] calldata amounts) external {
        require(itemIds.length == amounts.length, "Array lengths must match");
        require(itemIds.length > 0, "Must redeem at least one item");

        for (uint256 i = 0; i < itemIds.length; i++) {
            redeemForToken(itemIds[i], amounts[i]);
        }
    }

    /*
        OWNER FUNCTIONS
    */

    /**
     * @notice Set or update token redemption configuration for an item
     * @param itemId Item ID to configure redemption for
     * @param token ERC20 token address to give in exchange
     * @param amount Amount of tokens to give per item redeemed
     * @dev Only callable by owner
     */
    function setTokenRedemption(uint256 itemId, address token, uint256 amount) public onlyOwner {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");

        tokenRedemptions[itemId] = TokenRedemption({token: token, amount: amount, isActive: true});

        emit TokenRedemptionSet(itemId, token, amount);
    }

    /**
     * @notice Set multiple token redemptions in one transaction
     * @param itemIds Array of item IDs
     * @param tokens Array of token addresses
     * @param amounts Array of token amounts per item
     * @dev All arrays must have the same length
     */
    function setBulkTokenRedemptions(
        uint256[] calldata itemIds,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(itemIds.length == tokens.length && itemIds.length == amounts.length, "Array lengths must match");

        for (uint256 i = 0; i < itemIds.length; i++) {
            setTokenRedemption(itemIds[i], tokens[i], amounts[i]);
        }
    }

    /**
     * @notice Disable token redemptions for specific items
     * @param itemIds Array of item IDs to disable redemption for
     * @dev Only callable by owner
     */
    function deleteTokenRedemptions(uint256[] calldata itemIds) external onlyOwner {
        require(itemIds.length > 0, "Must provide at least one item ID");

        for (uint256 i = 0; i < itemIds.length; i++) {
            delete tokenRedemptions[itemIds[i]];
        }

        emit TokenRedemptionsDeleted(itemIds);
    }

    /**
     * @notice Withdraw ERC20 tokens from the contract
     * @param token Token address to withdraw
     * @param to Address to send tokens to
     * @param amount Amount to withdraw
     * @dev Only callable by owner
     */
    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Withdraw ETH from the contract
     * @param to Address to send ETH to
     * @param amount Amount to withdraw
     * @dev Only callable by owner
     */
    function withdrawETH(address to, uint256 amount) external onlyOwner {
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Emergency function to toggle redemption status without changing other parameters
     * @param itemId Item ID to toggle
     * @param isActive New active status
     * @dev Only callable by owner
     */
    function toggleRedemptionStatus(uint256 itemId, bool isActive) external onlyOwner {
        require(tokenRedemptions[itemId].token != address(0), "Redemption not configured");
        tokenRedemptions[itemId].isActive = isActive;
    }

    /// @notice Allow contract to receive ETH
    receive() external payable {}
}
