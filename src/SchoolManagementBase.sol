// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Custom errors
error InvalidAddress();
error ContractRecovered(address by, uint256 timestamp);
error SubscriptionExpiredError(uint256 expiredAt);
error InvalidInput();
error OperationTooFrequent();
error InsufficientPayment();
error WithdrawalFailed();

/**
 * @title IRoleRegistry
 * @dev Interface for centralized role management
 */
interface IRoleRegistry {
    function checkRole(bytes32 role, address account, address school) external view returns (bool);
    function grantSchoolRole(bytes32 role, address account, address school) external;
    function revokeSchoolRole(bytes32 role, address account, address school) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

interface IRevenueSystem {
    function certificateFee() external view returns (uint256);
    function programCreationFee() external view returns (uint256);
    function issueCertificate(address studentAddress, uint256 batchId) external payable;
    function processTuitionPayment(address student, uint256 amount) external payable;
}

interface IStudentProfile {
    function isStudentOfSchool(address student, address school) external view returns (bool);
    function getStudentProgram(address student) external view returns (uint256);
    function updateReputation(
        address student,
        uint256 attendancePoints,
        uint256 behaviorPoints,
        uint256 academicPoints
    ) external;
}

interface ITuitionSystem {
    function checkTuitionStatus(address organization, address student, uint256 term) external view returns (bool isPaid, uint256 dueDate);
    function recordTuitionPayment(address student, uint256 term) external;
}

/**
 * @title SchoolManagementBase
 * @dev Base contract with shared functionality for school management
 */
contract SchoolManagementBase is Pausable, Initializable, ReentrancyGuard {
    // Constants
    uint256 public constant MAX_STRING_LENGTH = 50;
    uint256 public constant MIN_TERM_FEE = 0.01 ether;
    uint256 public constant MAX_TERM_FEE = 100 ether;
    uint256 public constant OPERATION_COOLDOWN = 1 hours;
    uint256 public constant GRACE_PERIOD = 7 days;
    uint256 public constant REGISTRATION_COOLDOWN = 1 seconds;
    uint256 public constant GENERAL_COOLDOWN = 1 hours;
    uint256 public constant REGISTRATION_BURST_LIMIT = 50;
    uint256 public constant BURST_WINDOW = 1 hours;
    
    // Role definitions - kept for readability but used via registry
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    
    // State variables
    bool public isRecovered;
    uint64 public subscriptionEndTime;
    address public masterAdmin;
    mapping(address => uint256) public lastGeneralOperationTime;
    
    // Interface instances
    IRevenueSystem public revenueSystem;
    IStudentProfile public studentProfile;
    ITuitionSystem public tuitionSystem;
    IRoleRegistry public roleRegistry;
    
    // Events
    event ContractRecoveredEvent(address indexed recoveredBy, uint256 timestamp);
    event SubscriptionRenewed(uint256 newEndTime);
    event SubscriptionEnded(uint256 timestamp);
    event ContractPaused(address indexed pauser);
    event ContractUnpaused(address indexed unpauser);
    event InitializationComplete(
        address indexed revenueSystem,
        address indexed studentProfile, 
        address indexed tuitionSystem,
        address masterAdmin
    );
    event EthReceived(address indexed sender, uint256 amount);
    event FallbackCalled(address indexed sender, uint256 amount);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    
    /**
     * @dev Initialize the base contract
     */
    function initialize(
        address _revenueSystem,
        address _studentProfile,
        address _tuitionSystem,
        address _roleRegistry,
        address _masterAdmin
    ) public virtual initializer {
        if (_revenueSystem == address(0) || 
            _studentProfile == address(0) || 
            _tuitionSystem == address(0) || 
            _roleRegistry == address(0) ||
            _masterAdmin == address(0)) {
            revert InvalidAddress();
        }
        
        revenueSystem = IRevenueSystem(_revenueSystem);
        studentProfile = IStudentProfile(_studentProfile);
        tuitionSystem = ITuitionSystem(_tuitionSystem);
        roleRegistry = IRoleRegistry(_roleRegistry);
        masterAdmin = _masterAdmin;
        
        subscriptionEndTime = uint64(block.timestamp + 30 days);
        
        emit InitializationComplete(
            _revenueSystem,
            _studentProfile,
            _tuitionSystem, 
            _masterAdmin
        );
    }
    
    /**
     * @dev Modifier to check role authorization via the RoleRegistry
     */
    modifier onlyRole(bytes32 role) {
        require(roleRegistry.checkRole(role, msg.sender, address(this)), 
                "Missing required role");
        _;
    }
    
    /**
     * @dev Modifier to check if contract is not recovered
     */
    modifier notRecovered() {
        if (isRecovered) revert ContractRecovered(msg.sender, block.timestamp);
        _;
    }
    
    /**
     * @dev Modifier to check if subscription is active
     */
    modifier subscriptionActive() {
        if (block.timestamp > subscriptionEndTime) revert SubscriptionExpiredError(subscriptionEndTime);
        _;
    }
    
    /**
     * @dev Modifier to validate string length
     */
    modifier validString(string memory str) {
        if (bytes(str).length == 0 || bytes(str).length > MAX_STRING_LENGTH) 
            revert InvalidInput();
        _;
    }
    
    /**
     * @dev Modifier to limit general operations frequency
     */
    modifier generalRateLimited() {
        if (block.timestamp < lastGeneralOperationTime[msg.sender] + GENERAL_COOLDOWN)
            revert OperationTooFrequent();
        lastGeneralOperationTime[msg.sender] = block.timestamp;
        _;
    }
    
    /**
     * @dev Recover contract in case of emergency
     */
    function recoverContract() external onlyRole(MASTER_ADMIN_ROLE) {
        if (isRecovered) revert ContractRecovered(msg.sender, block.timestamp);
        isRecovered = true;
        _pause();
        emit ContractRecoveredEvent(msg.sender, block.timestamp);
    }
    
    /**
     * @dev Renew subscription
     */
    function renewSubscription() external payable {
        if (msg.value < revenueSystem.programCreationFee()) 
            revert InsufficientPayment();
        subscriptionEndTime = uint64(block.timestamp + 30 days);
        emit SubscriptionRenewed(subscriptionEndTime);
    }
    
    /**
     * @dev Handle subscription expiration
     */
    function handleSubscriptionExpiration() external onlyRole(ADMIN_ROLE) {
        if (block.timestamp <= subscriptionEndTime) revert SubscriptionExpiredError(subscriptionEndTime);
        _pause();
        emit SubscriptionEnded(block.timestamp);
    }
    
    /**
     * @dev Emergency withdraw funds
     */
    function emergencyWithdraw() external onlyRole(MASTER_ADMIN_ROLE) nonReentrant {
        if (address(this).balance == 0) revert InsufficientPayment();
        uint256 amount = address(this).balance;
        (bool success, ) = payable(masterAdmin).call{value: amount}("");
        if (!success) revert WithdrawalFailed();
        emit EmergencyWithdrawal(masterAdmin, amount);
    }
    
    /**
     * @dev Pause contract
     */
    function pause() external onlyRole(MASTER_ADMIN_ROLE) {
        _pause();
        emit ContractPaused(msg.sender);
    }
    
    /**
     * @dev Unpause contract
     */
    function unpause() external onlyRole(MASTER_ADMIN_ROLE) {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
    
    /**
     * @dev Handle incoming ETH
     */
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }
    
    /**
     * @dev Handle unknown function calls
     */
    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value);
    }
}