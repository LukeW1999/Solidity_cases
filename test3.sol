// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BMCExitTest {
    uint256 public constant MAX_UNSIGNED_INT = type(uint256).max;
    
    // Mock token interface
    mapping(address => uint256) public tokenBalances;
    address public tokenInstance = address(this);
    address public receiverInstance;
    address public currentContract = address(this);
    
    constructor() {
        receiverInstance = address(0x1234);
    }
    
    // Test function that includes all verification logic
    function testIntegrityExit(uint256 balance) public {
        // Setup initial state
        require(receiver() == receiverInstance, "receiver check failed");
        
        uint256 strategyBalanceBefore = balanceOf(currentContract);
        uint256 balanceBefore = balanceOf(receiverInstance);
        
        // Call the function under test
        int256 amountAdded = exit(balance);
        
        uint256 strategyBalanceAfter = balanceOf(currentContract);
        uint256 balanceAfter = balanceOf(receiverInstance);
        
        // The actual amount transferred is what getCurrentBalance returns
        uint256 actualTransferred = getCurrentBalance(balance);
        
        // Verify overflow protection for the actual transfer
        uint256 t = balanceBefore + actualTransferred;
        require(t <= MAX_UNSIGNED_INT, "overflow check");
        uint256 expectedBalance = balanceBefore + actualTransferred;
        
        // Main assertions from CVL
        assert(checkAplusBeqC(expectedBalance, amountAdded, balanceAfter));
        assert(compareLTzero(amountAdded) ? strategyBalanceBefore < balance : true);
    }
    
    // Function under test
    function exit(uint256 balance) public returns (int256 amountAdded) {
        uint256 b = getCurrentBalance(balance);
        transfer(receiver(), b);
        return safeSub(b, balance);
    }
    
    // Helper functions
    function receiver() public view returns (address) {
        return receiverInstance;
    }
    
    function getCurrentBalance(uint256 balance) public view returns (uint256) {
        uint256 currentBalance = balanceOf(currentContract);
        return currentBalance < balance ? currentBalance : balance;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return tokenBalances[account];
    }
    
    function transfer(address to, uint256 amount) public {
        require(tokenBalances[msg.sender] >= amount, "insufficient balance");
        tokenBalances[msg.sender] -= amount;
        tokenBalances[to] += amount;
    }
    
    function safeSub(uint256 a, uint256 b) public pure returns (int256) {
        if (a >= b) {
            return int256(a - b);
        } else {
            return -int256(b - a);
        }
    }
    
    function checkAplusBeqC(uint256 a, int256 b, uint256 c) public pure returns (bool) {
        if (b >= 0) {
            uint256 b_ = uint256(b);
            return a + b_ == c;
        } else {
            uint256 b_ = uint256(-b);
            return a - b_ == c;
        }
    }
    
    function compareLTzero(int256 value) public pure returns (bool) {
        return value < 0;
    }
    
    // Setup functions for testing
    function setBalance(address account, uint256 amount) public {
        tokenBalances[account] = amount;
    }
    
    function setReceiver(address _receiver) public {
        receiverInstance = _receiver;
    }
}
