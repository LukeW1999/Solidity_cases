pragma solidity ^0.8.0;

interface IProofOfReserveAggregator {
    function areAllReservesBacked(address[] memory assets) 
        external view returns (bool areReservesBacked, bool[] memory unbackedAssetsFlags);
}

interface IConfigurator {
    function freezeReserve(address asset) external;
}

contract ProofOfReserveVerification {
    address[] internal _assets;
    bool private _borrowingDisabled;
    
    IProofOfReserveAggregator internal _proofOfReserveAggregator;
    IConfigurator internal _configurator;
    
    event AssetIsNotBacked(address indexed asset);
    event EmergencyActionExecuted();
    
    constructor(address[] memory assets, address aggregator, address configurator) {
        _assets = assets;
        _proofOfReserveAggregator = IProofOfReserveAggregator(aggregator);
        _configurator = IConfigurator(configurator);
        _borrowingDisabled = false;
    }
    
    function _disableBorrowing() internal {
        _borrowingDisabled = true;
    }
    
    function _disableBorrowingCalled() internal view returns (bool) {
        return _borrowingDisabled;
    }
    
    function areAllReservesBacked() external view returns (bool) {
        if (_assets.length == 0) {
            return true;
        }
        (bool areReservesBacked, ) = _proofOfReserveAggregator.areAllReservesBacked(_assets);
        return areReservesBacked;
    }
    
    function executeEmergencyAction() external {
        (
            bool areReservesBacked,
            bool[] memory unbackedAssetsFlags
        ) = _proofOfReserveAggregator.areAllReservesBacked(_assets);
        
        if (!areReservesBacked) {
            _disableBorrowing();
            
            uint256 assetsLength = _assets.length;
            
            for (uint256 i = 0; i < assetsLength; ++i) {
                if (unbackedAssetsFlags[i]) {
                    _configurator.freezeReserve(_assets[i]);
                    emit AssetIsNotBacked(_assets[i]);
                }
            }
            
            emit EmergencyActionExecuted();
        }
    }
    
    function verifyIntegrityOfExecuteEmergencyAction() external {
        bool initialBorrowingState = _disableBorrowingCalled();
        
        require(!initialBorrowingState, "Initial condition: borrowing should not be disabled");
        
        bool allReservesBacked = this.areAllReservesBacked();
        
        this.executeEmergencyAction();
        
        bool disableBorrowingCalled = _disableBorrowingCalled();
        
        if (!allReservesBacked) {
            assert(disableBorrowingCalled);
        } else {
            assert(!disableBorrowingCalled);
        }
    }
    
    function resetState() external {
        _borrowingDisabled = false;
    }
    
    function getAssetsLength() external view returns (uint256) {
        return _assets.length;
    }
}
