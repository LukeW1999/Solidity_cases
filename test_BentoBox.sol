// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.12 <0.9.0;
pragma experimental ABIEncoderV2;

import "BentoBox.sol";

// Mock interfaces for testing
interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

// Simplified BentoBox implementation for model checking
contract BentoBoxModelTest {
    using SafeMath for uint256;
    
    // Events to match the original
    event LogDeposit(IERC20 indexed token, address indexed from, address indexed to, uint256 amount, uint256 share);
    event LogWithdraw(IERC20 indexed token, address indexed from, address indexed to, uint256 amount, uint256 share);
    event LogTransfer(IERC20 indexed token, address indexed from, address indexed to, uint256 share);
    
    // State variables matching original
    mapping(IERC20 => mapping(address => uint256)) public balanceOf;
    
    // Simplified Rebase struct
    struct Rebase {
        uint128 elastic;
        uint128 base;
    }
    
    mapping(IERC20 => Rebase) public totals;
    
    // For testing purposes
    mapping(address => bool) public masterContractApproved;
    mapping(address => address) public masterContractOf;
    address public owner;
    
    // Mock WETH
    IERC20 private immutable wethToken;
    IERC20 private constant USE_ETHEREUM = IERC20(0);
    uint256 private constant MINIMUM_SHARE_BALANCE = 1000;
    
    constructor(IERC20 _wethToken) public {
        wethToken = _wethToken;
        owner = msg.sender;
    }
    
    // Harness function for testing - represents the 'from' parameter
    function harnessFrom() public pure returns (address) {
        return address(0x1234567890123456789012345678901234567890);
    }
    
    // Simplified allowed modifier for testing
    modifier allowed(address from) {
        if (from != msg.sender && from != address(this)) {
            address masterContract = masterContractOf[msg.sender];
            require(masterContract != address(0), "BentoBox: no masterContract");
            require(masterContractApproved[masterContract][from], "BentoBox: Transfer not approved");
        }
        _;
    }
    
    // Helper functions to convert between shares and amounts
    function toAmount(IERC20 token, uint256 share, bool roundUp) public view returns (uint256 amount) {
        Rebase memory total = totals[token];
        if (total.base == 0) {
            amount = share;
        } else {
            amount = share.mul(total.elastic) / total.base;
            if (roundUp && amount.mul(total.base) / total.elastic < share) {
                amount = amount.add(1);
            }
        }
    }
    
    function toShare(IERC20 token, uint256 amount, bool roundUp) public view returns (uint256 share) {
        Rebase memory total = totals[token];
        if (total.elastic == 0) {
            share = amount;
        } else {
            share = amount.mul(total.base) / total.elastic;
            if (roundUp && share.mul(total.elastic) / total.base < amount) {
                share = share.add(1);
            }
        }
    }
    
    /// @notice Simplified transfer function for testing
    function transfer(
        IERC20 token,
        address from,
        address to,
        uint256 share
    ) public allowed(from) {
        require(to != address(0), "BentoBox: to not set");
        
        balanceOf[token][from] = balanceOf[token][from].sub(share);
        balanceOf[token][to] = balanceOf[token][to].add(share);
        
        emit LogTransfer(token, from, to, share);
    }
    
    /// @notice Simplified withdraw function for testing
    function withdraw(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) public allowed(from) returns (uint256 amountOut, uint256 shareOut) {
        require(to != address(0), "BentoBox: to not set");
        
        IERC20 token = token_ == USE_ETHEREUM ? wethToken : token_;
        Rebase memory total = totals[token];
        
        if (share == 0) {
            share = toShare(token, amount, true);
        } else {
            amount = toAmount(token, share, false);
        }
        
        balanceOf[token][from] = balanceOf[token][from].sub(share);
        total.elastic = total.elastic.sub(uint128(amount));
        total.base = total.base.sub(uint128(share));
        
        require(total.base >= MINIMUM_SHARE_BALANCE || total.base == 0, "BentoBox: cannot empty");
        totals[token] = total;
        
        // Simplified - just emit event, don't actually transfer tokens
        emit LogWithdraw(token, from, to, amount, share);
        
        amountOut = amount;
        shareOut = share;
    }
    
    /// @notice Simplified transferMultiple for testing
    function transferMultiple(
        IERC20 token,
        address from,
        address[] calldata tos,
        uint256[] calldata shares
    ) public allowed(from) {
        require(tos.length > 0 && tos[0] != address(0), "BentoBox: to[0] not set");
        require(tos.length == shares.length, "BentoBox: length mismatch");
        
        uint256 totalAmount;
        for (uint256 i = 0; i < tos.length; i++) {
            address to = tos[i];
            require(to != address(0), "BentoBox: to not set");
            balanceOf[token][to] = balanceOf[token][to].add(shares[i]);
            totalAmount = totalAmount.add(shares[i]);
            emit LogTransfer(token, from, to, shares[i]);
        }
        balanceOf[token][from] = balanceOf[token][from].sub(totalAmount);
    }
    
    /// @notice Simplified deposit function for testing
    function deposit(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) public payable allowed(from) returns (uint256 amountOut, uint256 shareOut) {
        require(to != address(0), "BentoBox: to not set");
        
        IERC20 token = token_ == USE_ETHEREUM ? wethToken : token_;
        Rebase memory total = totals[token];
        
        // Initialize totals if first deposit
        if (total.elastic == 0) {
            if (share == 0) {
                share = amount;
            }
            total.elastic = uint128(amount);
            total.base = uint128(share);
        } else {
            if (share == 0) {
                share = toShare(token, amount, false);
                if (total.base.add(uint128(share)) < MINIMUM_SHARE_BALANCE) {
                    return (0, 0);
                }
            } else {
                amount = toAmount(token, share, true);
            }
            total.base = total.base.add(uint128(share));
            total.elastic = total.elastic.add(uint128(amount));
        }
        
        balanceOf[token][to] = balanceOf[token][to].add(share);
        totals[token] = total;
        
        emit LogDeposit(token, from, to, amount, share);
        amountOut = amount;
        shareOut = share;
    }
    
    // Helper function for testing the CVL rule
    function callFunctionWithParams(
        IERC20 token,
        address from,
        address to,
        uint256 amount,
        uint256 share,
        bytes4 selector
    ) public {
        if (selector == this.transfer.selector) {
            this.transfer(token, from, to, share);
        } else if (selector == this.withdraw.selector) {
            this.withdraw(token, from, to, amount, share);
        } else if (selector == this.transferMultiple.selector) {
            // For transferMultiple, create arrays with single element for simplicity
            address[] memory tos = new address[](1);
            uint256[] memory shares = new uint256[](1);
            tos[0] = to;
            shares[0] = share;
            this.transferMultiple(token, from, tos, shares);
        }
    }
    
    // Setup functions for testing
    function setBalance(IERC20 token, address user, uint256 amount) public {
        balanceOf[token][user] = amount;
    }
    
    function setTotal(IERC20 token, uint128 elastic, uint128 base) public {
        totals[token] = Rebase(elastic, base);
    }
    
    function setMasterContractApproval(address masterContract, address user, bool approved) public {
        masterContractApproved[masterContract][user] = approved;
    }
    
    function setMasterContractOf(address clone, address masterContract) public {
        masterContractOf[clone] = masterContract;
    }
}

// SafeMath library for safe arithmetic operations
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
    
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }
    
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}
