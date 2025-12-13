// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UnimonRefunds is ReentrancyGuard, Ownable {
    mapping(address => uint256) public refundsForAddress;
    mapping(address => bool) public hasClaimed;

    bool public claimsEnabled;

    error AlreadyClaimed();
    error NoRefund();
    error InsufficientContractBalance();
    error ClaimsDisabled();

    constructor() Ownable(msg.sender) {}

    function toggleClaims(bool enabled) external onlyOwner {
        claimsEnabled = enabled;
    }

    function getClaimStatus(address user) external view returns (bool canClaim, uint256 amount, string memory reason) {
        if (!claimsEnabled) {
            return (false, 0, "Claims are disabled");
        }
        if (hasClaimed[user]) {
            return (false, 0, "Already claimed");
        }
        uint256 refundAmount = refundsForAddress[user];
        if (refundAmount == 0) {
            return (false, 0, "No refund available");
        }
        if (address(this).balance < refundAmount) {
            return (false, refundAmount, "Insufficient contract balance");
        }
        return (true, refundAmount, "Ready to claim");
    }

    function setRefunds(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        require(users.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            refundsForAddress[users[i]] = amounts[i];
        }
    }

    function claimRefund() external nonReentrant {
        if (!claimsEnabled) revert ClaimsDisabled();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 refundAmount = refundsForAddress[msg.sender];
        if (refundAmount == 0) revert NoRefund();
        if (address(this).balance < refundAmount) revert InsufficientContractBalance();

        hasClaimed[msg.sender] = true;

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Transfer failed");
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    receive() external payable {}
}
