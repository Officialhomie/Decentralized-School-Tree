// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "node_modules/@openzeppelin/contracts/proxy/Clones.sol";
import "node_modules/@openzeppelin/contracts/utils/Pausable.sol";
import "node_modules/@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "node_modules/@openzeppelin/contracts/utils/ReentrancyGuard.sol";


error InvalidImplementation();
error InvalidRevenueSystem();
error InvalidStudentProfile();
error InvalidMasterAdmin();
error InvalidOrganizationAddress();
error OrganizationCannotBeContract();
error OrganizationNotActive();
error SubscriptionExpiredBeyondGracePeriod();
error OrganizationAlreadyHasContract();
error InsufficientSubscriptionFee();
error InvalidRecipient();
error InsufficientBalance();
error TransferFailed();
error SameImplementation();
error NotContractAddress();
error InvalidRevenueShare();
error InvalidSubscriptionFee();
error InvalidSubscriptionDuration();
error DirectPaymentsNotAllowed();
error InvalidRoleRegistry();

/**
 * @title IRoleRegistry
 * @dev Interface for role registry
 */
interface IRoleRegistry {
    function grantSchoolRole(bytes32 role, address account, address school) external;
    function grantGlobalRole(bytes32 role, address account) external;
    function initialize(address masterAdmin) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function checkRole(bytes32 role, address account, address school) external view returns (bool);
}

/**
 * @title ISchoolManagement
 * @dev Interface for school management initialization
 */
interface ISchoolManagement {
    function initialize(
        address revenueSystem,
        address studentProfile,
        address tuitionSystem,
        address roleRegistry,
        address masterAdmin
    ) external;
}

/**
 * @title IStudentProfile
 * @dev Interface for student profile activation
 */
interface IStudentProfile {
    function activateSchool(address school) external;
}

/**
 * @title IRevenueSystem
 * @dev Interface for custom fee structure
 */
interface IRevenueSystem {
    function setCustomFeeStructure(
        address school,
        uint256 programFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueShare
    ) external;
}

/**
 * @title SchoolManagementFactory
 * @dev Factory for deploying school management system contracts
 */
contract SchoolManagementFactory is Pausable, Initializable, ReentrancyGuard {
    using Clones for address;

    // Role constants
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Constants for validation
    uint256 public constant GRACE_PERIOD = 3 days;
    uint256 public constant MIN_SUBSCRIPTION_DURATION = 30 days;
    uint256 public constant MAX_SUBSCRIPTION_DURATION = 365 days;

    /**
     * @dev Deployment configuration structure
     */
    struct DeploymentConfig {
        uint256 programFee;
        uint256 subscriptionFee;
        uint256 certificateFee;
        uint256 revenueShare;
        uint256 subscriptionDuration;
    }

    /**
     * @dev School information structure
     */
    struct SchoolInfo {
        bool isDeployed;
        bool isActive;
        uint256 subscriptionEnd;
        uint256 subscriptionDuration;
    }

    // Implementation contracts
    address public roleRegistryImpl;
    address public schoolManagementImpl;
    address public programManagementImpl;
    address public studentManagementImpl;
    address public attendanceTrackingImpl;
    address public certificateManagementImpl;
    
    // Shared contracts
    address public roleRegistry;
    address public revenueSystem;
    address public studentProfile;
    address public tuitionSystem;
    
    // Storage
    address[] public deployedSchools;
    mapping(address => SchoolInfo) public schoolInfo;
    mapping(address => address) public organizationToSchool;
    
    uint256 public totalFeesCollected;
    DeploymentConfig public defaultConfig;
    address public masterAdmin;

    // Events
    event SchoolDeployed(
        address indexed school, 
        address indexed organization,
        uint256 deploymentTime,
        uint256 subscriptionEnd,
        uint256 subscriptionDuration
    );

    event SchoolDeactivated(address indexed school, uint256 timestamp);
    
    event SubscriptionRenewed(
        address indexed school, 
        uint256 newEndTime,
        uint256 amountPaid
    );
    
    event ConfigurationUpdated(DeploymentConfig config);
    
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    
    event ContractPaused(address indexed pauser);
    
    event ContractUnpaused(address indexed unpauser);
    
    event ImplementationUpdated(
        string implementationType,
        address indexed oldImplementation, 
        address indexed newImplementation
    );
    
    event FactoryInitialized(
        address roleRegistry,
        address revenueSystem,
        address studentProfile,
        address tuitionSystem,
        address masterAdmin
    );
    
    /**
     * @dev Constructor
     */
    constructor() {
        // No setup in constructor, use initialize instead
    }

    /**
     * @dev Initialize the factory
     */
    function initialize(
        address _roleRegistryImpl,
        address _schoolManagementImpl,
        address _programManagementImpl,
        address _studentManagementImpl,
        address _attendanceTrackingImpl,
        address _certificateManagementImpl,
        address _revenueSystem,
        address _studentProfile,
        address _tuitionSystem,
        address _masterAdmin,
        DeploymentConfig memory _defaultConfig
    ) public initializer {
        if(_roleRegistryImpl == address(0)) revert InvalidImplementation();
        if(_schoolManagementImpl == address(0)) revert InvalidImplementation();
        if(_revenueSystem == address(0)) revert InvalidRevenueSystem();
        if(_studentProfile == address(0)) revert InvalidStudentProfile();
        if(_masterAdmin == address(0)) revert InvalidMasterAdmin();
        
        // Store implementation addresses
        roleRegistryImpl = _roleRegistryImpl;
        schoolManagementImpl = _schoolManagementImpl;
        programManagementImpl = _programManagementImpl;
        studentManagementImpl = _studentManagementImpl;
        attendanceTrackingImpl = _attendanceTrackingImpl;
        certificateManagementImpl = _certificateManagementImpl;
        
        // Store shared contracts
        revenueSystem = _revenueSystem;
        studentProfile = _studentProfile;
        tuitionSystem = _tuitionSystem;
        masterAdmin = _masterAdmin;
        defaultConfig = _defaultConfig;
        
        // Deploy role registry
        roleRegistry = _roleRegistryImpl.clone();
        IRoleRegistry(roleRegistry).initialize(_masterAdmin);
        
        emit FactoryInitialized(
            roleRegistry,
            _revenueSystem,
            _studentProfile,
            _tuitionSystem,
            _masterAdmin
        );
    }

    /**
     * @dev Only the master admin can call this function
     */
    modifier onlyMasterAdmin() {
        require(msg.sender == masterAdmin, "Only master admin");
        _;
    }

    /**
     * @dev Modifier to validate organization address
     */
    modifier onlyValidOrganization(address organization) {
        if(organization == address(0)) revert InvalidOrganizationAddress();
        if(_isContract(organization)) revert OrganizationCannotBeContract();
        _;
    }

    /**
     * @dev Deploy a new school management system
     */
    function deploySchool(
        address organizationAdmin,
        DeploymentConfig memory customConfig
    ) external payable onlyMasterAdmin 
      onlyValidOrganization(organizationAdmin) 
      whenNotPaused 
      nonReentrant 
      returns (address schoolContract, address programContract, address studentContract, address attendanceContract, address certificateContract) {
        if(schoolInfo[organizationAdmin].isDeployed) revert OrganizationAlreadyHasContract();
        if(msg.value < defaultConfig.subscriptionFee) revert InsufficientSubscriptionFee();
        
        _validateConfig(customConfig);

        // Clone all contracts
        schoolContract = schoolManagementImpl.clone();
        programContract = programManagementImpl.clone();
        studentContract = studentManagementImpl.clone();
        attendanceContract = attendanceTrackingImpl.clone();
        certificateContract = certificateManagementImpl.clone();
        
        // Initialize all contracts
        // 1. School Management
        ISchoolManagement(schoolContract).initialize(
            revenueSystem,
            studentProfile,
            tuitionSystem,
            roleRegistry,
            masterAdmin
        );
        
        // 2. Program Management
        ISchoolManagement(programContract).initialize(
            revenueSystem,
            studentProfile,
            tuitionSystem,
            roleRegistry,
            masterAdmin
        );
        
        // 3. Student Management
        ISchoolManagement(studentContract).initialize(
            revenueSystem,
            studentProfile,
            tuitionSystem,
            roleRegistry,
            masterAdmin
        );
        
        // 4. Attendance Tracking
        ISchoolManagement(attendanceContract).initialize(
            revenueSystem,
            studentProfile,
            tuitionSystem,
            roleRegistry,
            masterAdmin
        );
        
        // 5. Certificate Management
        ISchoolManagement(certificateContract).initialize(
            revenueSystem,
            studentProfile,
            tuitionSystem,
            roleRegistry,
            masterAdmin
        );

        // Assign roles
        // School role for the main contract
        IRoleRegistry(roleRegistry).grantSchoolRole(SCHOOL_ROLE, schoolContract, schoolContract);
        // Admin role for the organization admin
        IRoleRegistry(roleRegistry).grantSchoolRole(ADMIN_ROLE, organizationAdmin, schoolContract);
        
        // Set custom fee structure if provided
        if (customConfig.subscriptionFee > 0) {
            IRevenueSystem(revenueSystem).setCustomFeeStructure(
                schoolContract,
                customConfig.programFee,
                customConfig.subscriptionFee,
                customConfig.certificateFee,
                customConfig.revenueShare
            );
        }

        // Activate school in the student profile
        IStudentProfile(studentProfile).activateSchool(schoolContract);

        // Record deployment
        deployedSchools.push(schoolContract);
        
        schoolInfo[organizationAdmin] = SchoolInfo({
            isDeployed: true,
            isActive: true,
            subscriptionEnd: block.timestamp + customConfig.subscriptionDuration,
            subscriptionDuration: customConfig.subscriptionDuration
        });
        
        organizationToSchool[organizationAdmin] = schoolContract;
        totalFeesCollected += msg.value;

        emit SchoolDeployed(
            schoolContract, 
            organizationAdmin, 
            block.timestamp,
            schoolInfo[organizationAdmin].subscriptionEnd,
            customConfig.subscriptionDuration
        );

        return (schoolContract, programContract, studentContract, attendanceContract, certificateContract);
    }

    /**
     * @dev Update implementation address
     */
    function updateImplementation(
        string memory implementationType,
        address newImplementation
    ) external onlyMasterAdmin {
        if(newImplementation == address(0)) revert InvalidImplementation();
        if(!_isContract(newImplementation)) revert NotContractAddress();
        
        address oldImplementation;
        
        if (keccak256(bytes(implementationType)) == keccak256(bytes("roleRegistry"))) {
            oldImplementation = roleRegistryImpl;
            roleRegistryImpl = newImplementation;
        } else if (keccak256(bytes(implementationType)) == keccak256(bytes("schoolManagement"))) {
            oldImplementation = schoolManagementImpl;
            schoolManagementImpl = newImplementation;
        } else if (keccak256(bytes(implementationType)) == keccak256(bytes("programManagement"))) {
            oldImplementation = programManagementImpl;
            programManagementImpl = newImplementation;
        } else if (keccak256(bytes(implementationType)) == keccak256(bytes("studentManagement"))) {
            oldImplementation = studentManagementImpl;
            studentManagementImpl = newImplementation;
        } else if (keccak256(bytes(implementationType)) == keccak256(bytes("attendanceTracking"))) {
            oldImplementation = attendanceTrackingImpl;
            attendanceTrackingImpl = newImplementation;
        } else if (keccak256(bytes(implementationType)) == keccak256(bytes("certificateManagement"))) {
            oldImplementation = certificateManagementImpl;
            certificateManagementImpl = newImplementation;
        } else {
            revert("Invalid implementation type");
        }
        
        if(newImplementation == oldImplementation) revert SameImplementation();
        
        emit ImplementationUpdated(implementationType, oldImplementation, newImplementation);
    }

    /**
     * @dev Update shared contract address
     */
    function updateSharedContract(
        string memory contractType,
        address newAddress
    ) external onlyMasterAdmin {
        require(newAddress != address(0), "Invalid address");
        
        if (keccak256(bytes(contractType)) == keccak256(bytes("roleRegistry"))) {
            if(!_isContract(newAddress)) revert InvalidRoleRegistry();
            roleRegistry = newAddress;
        } else if (keccak256(bytes(contractType)) == keccak256(bytes("revenueSystem"))) {
            revenueSystem = newAddress;
        } else if (keccak256(bytes(contractType)) == keccak256(bytes("studentProfile"))) {
            studentProfile = newAddress;
        } else if (keccak256(bytes(contractType)) == keccak256(bytes("tuitionSystem"))) {
            tuitionSystem = newAddress;
        } else {
            revert("Invalid contract type");
        }
    }

    /**
     * @dev Withdraw collected fees
     */
    function withdrawFees(address payable recipient, uint256 amount) 
        external 
        onlyMasterAdmin 
        nonReentrant 
    {
        if(recipient == address(0)) revert InvalidRecipient();
        if(amount > totalFeesCollected) revert InsufficientBalance();
        
        totalFeesCollected -= amount;
        (bool success, ) = recipient.call{value: amount}("");
        if(!success) revert TransferFailed();
        
        emit FeesWithdrawn(recipient, amount);
    }

    /**
     * @dev Renew subscription for a school
     */
    function renewSubscription(address organization) 
        external 
        payable 
        nonReentrant 
    {
        if(!schoolInfo[organization].isDeployed) revert InvalidOrganizationAddress();
        if(msg.value < defaultConfig.subscriptionFee) revert InsufficientSubscriptionFee();
        
        SchoolInfo storage info = schoolInfo[organization];
        
        // If subscription ended beyond grace period, revert
        if(info.subscriptionEnd + GRACE_PERIOD < block.timestamp && info.isActive) {
            revert SubscriptionExpiredBeyondGracePeriod();
        }
        
        // Set new subscription end date
        // If still active, add duration to current end date
        // If expired but within grace, add duration to current timestamp
        uint256 newEndTime;
        if(info.subscriptionEnd >= block.timestamp) {
            newEndTime = info.subscriptionEnd + info.subscriptionDuration;
        } else {
            newEndTime = block.timestamp + info.subscriptionDuration;
        }
        
        info.subscriptionEnd = newEndTime;
        info.isActive = true;
        totalFeesCollected += msg.value;
        
        emit SubscriptionRenewed(
            organizationToSchool[organization],
            newEndTime,
            msg.value
        );
    }

    /**
     * @dev Deactivate an organization's school
     */
    function deactivateOrganization(address organization)
        external
        onlyMasterAdmin
    {
        if(!schoolInfo[organization].isDeployed) revert InvalidOrganizationAddress();
        
        SchoolInfo storage info = schoolInfo[organization];
        info.isActive = false;
        
        emit SchoolDeactivated(organizationToSchool[organization], block.timestamp);
    }

    /**
     * @dev Check if an address is a contract
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Update default configuration parameters
     */
    function updateDefaultConfig(DeploymentConfig memory newConfig) 
        external 
        onlyMasterAdmin 
    {
        _validateConfig(newConfig);
        defaultConfig = newConfig;
        
        emit ConfigurationUpdated(newConfig);
    }
    
    /**
     * @dev Get the current default configuration
     */
    function getDefaultConfig() external view returns (DeploymentConfig memory) {
        return defaultConfig;
    }

    /**
     * @dev Validate configuration parameters
     */
    function _validateConfig(DeploymentConfig memory config) internal pure {
        if(config.revenueShare > 100) revert InvalidRevenueShare();
        if(config.subscriptionFee == 0) revert InvalidSubscriptionFee();
        if(config.subscriptionDuration < MIN_SUBSCRIPTION_DURATION || 
           config.subscriptionDuration > MAX_SUBSCRIPTION_DURATION) revert InvalidSubscriptionDuration();
    }

    /**
     * @dev Pause the factory
     */
    function pause() external onlyMasterAdmin {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @dev Unpause the factory
     */
    function unpause() external onlyMasterAdmin {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /**
     * @dev Reject direct payments
     */
    receive() external payable {
        revert DirectPaymentsNotAllowed();
    }
}


/*
Imagine you're running a franchise business, but instead of fast food restaurants, you're managing a network of schools on the blockchain! 

This contract is like the "Franchise Headquarters" that helps create and manage new schools in this digital education system. Here's what it does in simple terms:

🏫 School Creation:
- Just like opening a new franchise location, organizations can deploy their own school management system
- They pay a subscription fee (like a franchise fee) to join the network
- Each school gets their own customized setup with specific rules about fees and revenue sharing

💳 Subscription Management:
- Schools need to keep their subscription active to stay in the network
- There's a grace period (like a payment deadline extension) if they're late on renewal
- The system tracks when subscriptions end and handles renewals

👨‍💼 Administration:
- There's a master admin (like a franchise CEO) who oversees everything
- Each school gets their own admin to manage their specific location
- The system keeps track of which schools are active and their payment status

💰 Financial Management:
- Handles all the money stuff - collecting fees, tracking payments
- Makes sure everyone pays what they're supposed to
- Keeps track of how much money has been collected

🔒 Safety Features:
- Has built-in protection against hackers and fraud
- Can be paused in case of emergencies
- Makes sure only authorized people can make important changes

Think of it as a digital franchise system for education - but instead of selling burgers, it's helping organizations set up and run schools on the blockchain!
*/