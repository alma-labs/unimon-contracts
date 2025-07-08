// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UnimonPrizes is ReentrancyGuard, Ownable {
    mapping(address => uint256) public prizesForAddress;
    mapping(address => bool) public hasClaimed;

    bool public claimsEnabled;

    error AlreadyClaimed();
    error NoPrize();
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
        uint256 prizeAmount = prizesForAddress[user];
        if (prizeAmount == 0) {
            return (false, 0, "No prize available");
        }
        if (address(this).balance < prizeAmount) {
            return (false, prizeAmount, "Insufficient contract balance");
        }
        return (true, prizeAmount, "Ready to claim");
    }

    function setPrizes(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        require(users.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            prizesForAddress[users[i]] = amounts[i];
        }
    }

    function claimPrize() external nonReentrant {
        if (!claimsEnabled) revert ClaimsDisabled();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 prizeAmount = prizesForAddress[msg.sender];
        if (prizeAmount == 0) revert NoPrize();
        if (address(this).balance < prizeAmount) revert InsufficientContractBalance();

        hasClaimed[msg.sender] = true;

        (bool success, ) = payable(msg.sender).call{value: prizeAmount}("");
        require(success, "Transfer failed");
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    receive() external payable {}
}
