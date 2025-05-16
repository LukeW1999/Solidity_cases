// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Simplified IERC20 interface without OpenZeppelin
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IFlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

contract BMCVerificationContract {
    // 策略数据结构
    struct StrategyData {
        uint256 balance;
    }
    
    // 状态变量
    mapping(IERC20 => StrategyData) public strategyData;
    address public harnessFrom;
    IERC20 public harnessToken;
    IFlashBorrower public harnessBorrower;
    
    // 用于BMC验证的映射，跟踪每个token和地址的余额
    mapping(address => mapping(address => uint256)) private balances;
    
    // 事件用于BMC跟踪
    event BalanceChanged(address indexed token, address indexed account, uint256 oldBalance, uint256 newBalance);
    
    constructor() {
        // 初始化harness变量 - 在BMC中这些会是符号变量
        harnessFrom = address(0x1); // 符号地址
        harnessToken = IERC20(address(0x2)); // 符号token
        harnessBorrower = IFlashBorrower(address(0x3)); // 符号borrower
    }
    
    // 获取token余额的函数
    function balanceOf(address token, address account) public view returns (uint256) {
        return balances[token][account];
    }
    
    // 内部函数：获取token总余额
    function _tokenBalanceOf(IERC20 token) internal view returns (uint256 amount) {
        amount = token.balanceOf(address(this)) + strategyData[token].balance;
    }
    
    // 转账函数
    function transfer(address token, address from, address to, uint256 amount) external {
        require(balances[token][from] >= amount, "Insufficient balance");
        
        uint256 oldFromBalance = balances[token][from];
        uint256 oldToBalance = balances[token][to];
        
        balances[token][from] -= amount;
        balances[token][to] += amount;
        
        emit BalanceChanged(token, from, oldFromBalance, balances[token][from]);
        emit BalanceChanged(token, to, oldToBalance, balances[token][to]);
    }
    
    // 提取函数
    function withdraw(address token, address from, address to, uint256 amount, uint256 share) external {
        require(balances[token][from] >= amount, "Insufficient balance");
        
        uint256 oldFromBalance = balances[token][from];
        uint256 oldToBalance = balances[token][to];
        
        balances[token][from] -= amount;
        balances[token][to] += amount;
        
        // 减少策略余额
        if (strategyData[IERC20(token)].balance >= share) {
            strategyData[IERC20(token)].balance -= share;
        }
        
        emit BalanceChanged(token, from, oldFromBalance, balances[token][from]);
        emit BalanceChanged(token, to, oldToBalance, balances[token][to]);
    }
    
    // 批量转账函数
    function transferMultiple(address token, address from, address to, address[] calldata recipients, uint256[] calldata amounts) external {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        require(balances[token][from] >= totalAmount, "Insufficient balance");
        
        uint256 oldFromBalance = balances[token][from];
        balances[token][from] -= totalAmount;
        emit BalanceChanged(token, from, oldFromBalance, balances[token][from]);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 oldBalance = balances[token][recipients[i]];
            balances[token][recipients[i]] += amounts[i];
            emit BalanceChanged(token, recipients[i], oldBalance, balances[token][recipients[i]]);
        }
    }
    
    // 闪贷函数
    function flashLoan(IFlashBorrower borrower, address receiver, IERC20 token, uint256 amount, bytes calldata data) external {
        require(harnessToken == token, "Invalid token");
        require(harnessBorrower == borrower, "Invalid borrower");
        
        // 执行闪贷逻辑
        uint256 oldBalance = token.balanceOf(address(this));
        
        // 发送代币给borrower
        require(token.transfer(receiver, amount), "Transfer failed");
        
        // 调用borrower的回调函数
        borrower.onFlashLoan(msg.sender, address(token), amount, 0, data);
        
        // 验证代币已归还
        uint256 newBalance = token.balanceOf(address(this));
        require(newBalance >= oldBalance, "Loan not repaid");
    }
    
    // BMC验证的主要函数
    function verifyValidDecreaseToBalanceOf(
        address token,
        address a,
        address from,
        address to,
        address other,
        bytes4 functionSelector,
        uint256 amount,
        uint256 share
    ) external {
        // BMC前置条件
        require(from == harnessFrom, "from must equal harnessFrom");
        
        // 记录调用前的余额
        uint256 vBefore = balanceOf(token, a);
        
        // 根据函数选择器调用相应函数
        if (functionSelector == this.transfer.selector) {
            this.transfer(token, from, to, amount);
        } else if (functionSelector == this.withdraw.selector) {
            this.withdraw(token, from, to, amount, share);
        } else if (functionSelector == this.transferMultiple.selector) {
            // 为了简化，创建单元素数组
            address[] memory recipients = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            recipients[0] = to;
            amounts[0] = amount;
            this.transferMultiple(token, from, to, recipients, amounts);
        }
        
        // 记录调用后的余额
        uint256 vAfter = balanceOf(token, a);
        
        // BMC断言：如果余额减少，则必须满足特定条件
        if (vBefore > vAfter) {
            assert(from == a && (
                functionSelector == this.transfer.selector ||
                functionSelector == this.withdraw.selector ||
                functionSelector == this.transferMultiple.selector
            ));
        }
    }
    
    // 辅助函数：设置初始余额（用于BMC测试）
    function setBalance(address token, address account, uint256 amount) external {
        balances[token][account] = amount;
    }
    
    // 辅助函数：设置harness变量（用于BMC测试）
    function setHarnessFrom(address _from) external {
        harnessFrom = _from;
    }
    
    function setHarnessToken(IERC20 _token) external {
        harnessToken = _token;
    }
    
    function setHarnessBorrower(IFlashBorrower _borrower) external {
        harnessBorrower = _borrower;
    }
    
    // 获取函数选择器的辅助函数
    function getTransferSelector() external pure returns (bytes4) {
        return this.transfer.selector;
    }
    
    function getWithdrawSelector() external pure returns (bytes4) {
        return this.withdraw.selector;
    }
    
    function getTransferMultipleSelector() external pure returns (bytes4) {
        return this.transferMultiple.selector;
    }
}
