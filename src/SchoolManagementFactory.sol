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

/**
 * @title ISchoolManagement
 * @dev Interface for school management initialization and role management
 */
interface ISchoolManagement {
    /**
     * @dev Initialize the cloned SchoolManagement contract
     * @param revenueSystem Address of the revenue system
     * @param studentProfile Address of the student profile
     * @param factory Address of the factory
     * @param masterAdmin Address of the master admin
     * @param organizationAdmin Address of the organization admin
     */
    function initialize(
        address revenueSystem,
        address studentProfile,
        address factory,
        address masterAdmin,
        address organizationAdmin
    ) external;
    
    /**
     * @dev Grant a role to an account
     * @param role Role identifier
     * @param account Account to grant role to
     */
    function grantRole(bytes32 role, address account) external;
}

/**
 * @title IRevenueSystem
 * @dev Interface for configuring fee structures
 */
interface IRevenueSystem {
    /**
     * @dev Set custom fee structure for a school
     * @param school Address of the school
     * @param programFee Fee for program creation
     * @param subscriptionFee Fee for subscription
     * @param certificateFee Fee for certificate issuance
     * @param revenueShare Platform's share of revenue (percentage)
     */
    function setCustomFeeStructure(
        address school,
        uint256 programFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueShare
    ) external;
}

/**
 * @title IStudentProfile
 * @dev Interface for activating schools in the student profile system
 */
interface IStudentProfile {
    /**
     * @dev Activate a school in the student profile system
     * @param school Address of the school to activate
     */
    function activateSchool(address school) external;
}

/**
 * @title SchoolManagementFactory
 * @dev Factory contract for deploying and managing SchoolManagement contracts
 * 
 * This contract implements the factory pattern to create new school instances by:
 * - Using the OpenZeppelin Clones library for gas-efficient proxy deployment
 * - Managing subscriptions and configurations for schools
 * - Providing upgrade capabilities for implementation contracts
 * - Tracking deployed contracts and their statuses
 */
contract SchoolManagementFactory is AccessControl, Pausable, Initializable, ReentrancyGuard {
    using Clones for address;

    // Role identifiers
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Constants for validation
    uint256 public constant MAX_REVENUE_SHARE = 100;
    uint256 public constant MIN_SUBSCRIPTION_FEE = 0.01 ether;
    uint256 public constant MAX_SUBSCRIPTION_FEE = 100 ether;
    uint256 public constant GRACE_PERIOD = 3 days;
    uint256 public constant MIN_SUBSCRIPTION_DURATION = 30 days;
    uint256 public constant MAX_SUBSCRIPTION_DURATION = 365 days;

    /**
     * @dev Deployment configuration structure for schools
     */
    struct DeploymentConfig {
        uint256 programFee;
        uint256 subscriptionFee;
        uint256 certificateFee;
        uint256 revenueShare;
        uint256 subscriptionDuration;
    }

    /**
     * @dev Organization information structure
     */
    struct OrganizationInfo {
        bool isDeployed;
        bool isActive;
        uint256 subscriptionEnd;
        uint256 subscriptionDuration;
    }

    // Storage
    address public implementationContract;
    address[] public deployedContracts;
    
    mapping(address => OrganizationInfo) public organizationInfo;
    mapping(address => address) public organizationToContract;
    
    uint256 public totalFeesCollected;
    
    IRevenueSystem public revenueSystem;
    IStudentProfile public studentProfile;
    DeploymentConfig public defaultConfig;

    /**
     * @dev Emitted when a new contract is deployed
     * @param newContract Address of the deployed contract
     * @param organization Address of the organization
     * @param deploymentTime Timestamp of deployment
     * @param subscriptionEnd Subscription end time
     * @param subscriptionDuration Duration of subscription
     */
    event ContractDeployed(
        address indexed newContract, 
        address indexed organization,
        uint256 deploymentTime,
        uint256 subscriptionEnd,
        uint256 subscriptionDuration
    );

    /**
     * @dev Emitted when an organization is deactivated
     * @param organization Address of the organization
     * @param timestamp Timestamp of deactivation
     */
    event OrganizationDeactivated(address indexed organization, uint256 timestamp);
    
    /**
     * @dev Emitted when a subscription is renewed
     * @param organization Address of the organization
     * @param newEndTime New subscription end time
     * @param amountPaid Amount paid for renewal
     */
    event SubscriptionRenewed(
        address indexed organization, 
        uint256 newEndTime,
        uint256 amountPaid
    );
    
    /**
     * @dev Emitted when configuration is updated
     * @param config New configuration structure
     */
    event ConfigurationUpdated(DeploymentConfig config);
    
    /**
     * @dev Emitted when fees are withdrawn
     * @param recipient Address of the recipient
     * @param amount Amount withdrawn
     */
    event FeesWithdrawn(address indexed recipient, uint256 amount);
    
    /**
     * @dev Emitted when contract is paused
     * @param pauser Address of the pauser
     */
    event ContractPaused(address indexed pauser);
    
    /**
     * @dev Emitted when contract is unpaused
     * @param unpauser Address of the unpauser
     */
    event ContractUnpaused(address indexed unpauser);
    
    /**
     * @dev Emitted when implementation is updated
     * @param oldImplementation Address of the old implementation
     * @param newImplementation Address of the new implementation
     */
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);
    
    /**
     * @dev Emitted when contract is initialized
     * @param implementation Address of the implementation
     * @param revenueSystem Address of the revenue system
     * @param studentProfile Address of the student profile
     * @param masterAdmin Address of the master admin
     * @param config Default configuration
     */
    event ContractInitialized(
        address implementation,
        address revenueSystem,
        address studentProfile,
        address masterAdmin,
        DeploymentConfig config
    );

    /**
     * @dev Constructor
     * @param _implementation Address of the implementation contract
     */
    constructor(address _implementation) {
        if(_implementation == address(0)) revert InvalidImplementation();
        implementationContract = _implementation;
        // _disableInitializers();
    }

    /**
     * @dev Initialize the factory
     * @param _implementation Address of the implementation contract
     * @param _revenueSystem Address of the revenue system
     * @param _studentProfile Address of the student profile
     * @param _masterAdmin Address of the master admin
     * @param _defaultConfig Default configuration structure
     */
    function initialize(
        address _implementation,
        address _revenueSystem,
        address _studentProfile,
        address _masterAdmin,
        DeploymentConfig memory _defaultConfig
    ) public initializer {
        if(_implementation == address(0)) revert InvalidImplementation();
        if(_revenueSystem == address(0)) revert InvalidRevenueSystem();
        if(_studentProfile == address(0)) revert InvalidStudentProfile();
        if(_masterAdmin == address(0)) revert InvalidMasterAdmin();
        
        _validateConfig(_defaultConfig);
        
        implementationContract = _implementation;
        revenueSystem = IRevenueSystem(_revenueSystem);
        studentProfile = IStudentProfile(_studentProfile);
        defaultConfig = _defaultConfig;

        _grantRole(MASTER_ADMIN_ROLE, _masterAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, _masterAdmin);

        emit ContractInitialized(
            _implementation,
            _revenueSystem,
            _studentProfile,
            _masterAdmin,
            _defaultConfig
        );
    }

    /**
     * @dev Modifier to validate organization address
     * @param organization Address of the organization
     */
    modifier onlyValidOrganization(address organization) {
        if(organization == address(0)) revert InvalidOrganizationAddress();
        if(_isContract(organization)) revert OrganizationCannotBeContract();
        _;
    }

    /**
     * @dev Modifier to validate active organization
     * @param organization Address of the organization
     */
    modifier onlyActiveOrganization(address organization) {
        if(!organizationInfo[organization].isActive) revert OrganizationNotActive();
        if(block.timestamp > organizationInfo[organization].subscriptionEnd + GRACE_PERIOD)
            revert SubscriptionExpiredBeyondGracePeriod();
        _;
    }

    /**
     * @dev Deploy a new SchoolManagement contract
     * @param organizationAdmin Address of the organization admin
     * @param customConfig Custom configuration for the school
     * @return address Address of the deployed contract
     * Requirements:
     * - Must be called by master admin
     * - Organization must be valid
     * - Contract must not be paused
     * - Organization must not already have a contract
     * - Payment must cover subscription fee
     */
    function deploySchoolManagement(
        address organizationAdmin,
        DeploymentConfig memory customConfig
    ) external payable onlyRole(MASTER_ADMIN_ROLE) 
      onlyValidOrganization(organizationAdmin) 
      whenNotPaused 
      nonReentrant 
      returns (address) {
        if(organizationInfo[organizationAdmin].isDeployed) revert OrganizationAlreadyHasContract();
        if(msg.value < defaultConfig.subscriptionFee) revert InsufficientSubscriptionFee();
        
        _validateConfig(customConfig);

        address newContract = implementationContract.clone();
        
        ISchoolManagement(newContract).initialize(
            address(revenueSystem),
            address(studentProfile),
            address(this),
            msg.sender,
            organizationAdmin
        );

        ISchoolManagement(newContract).grantRole(SCHOOL_ROLE, newContract);
        ISchoolManagement(newContract).grantRole(ADMIN_ROLE, organizationAdmin);

        if (customConfig.subscriptionFee > 0) {
            revenueSystem.setCustomFeeStructure(
                newContract,
                customConfig.programFee,
                customConfig.subscriptionFee,
                customConfig.certificateFee,
                customConfig.revenueShare
            );
        }

        studentProfile.activateSchool(newContract);

        deployedContracts.push(newContract);
        
        organizationInfo[organizationAdmin] = OrganizationInfo({
            isDeployed: true,
            isActive: true,
            subscriptionEnd: block.timestamp + customConfig.subscriptionDuration,
            subscriptionDuration: customConfig.subscriptionDuration
        });
        
        organizationToContract[organizationAdmin] = newContract;
        totalFeesCollected += msg.value;

        emit ContractDeployed(
            newContract, 
            organizationAdmin, 
            block.timestamp,
            organizationInfo[organizationAdmin].subscriptionEnd,
            customConfig.subscriptionDuration
        );

        return newContract;
    }

    /**
     * @dev Renew subscription for an organization
     * @param organization Address of the organization
     * Requirements:
     * - Organization must be active
     * - Payment must cover subscription fee
     */
    function renewSubscription(address organization) 
        external 
        payable 
        onlyActiveOrganization(organization) 
        nonReentrant 
    {
        OrganizationInfo storage info = organizationInfo[organization];
        if(msg.value < defaultConfig.subscriptionFee) revert InsufficientSubscriptionFee();
        
        uint256 newEndTime = block.timestamp + info.subscriptionDuration;
        if (block.timestamp <= info.subscriptionEnd) {
            newEndTime = info.subscriptionEnd + info.subscriptionDuration;
        }
        
        info.subscriptionEnd = newEndTime;
        totalFeesCollected += msg.value;
        
        emit SubscriptionRenewed(organization, newEndTime, msg.value);
    }

    /**
     * @dev Withdraw collected fees
     * @param recipient Address to send fees to
     * @param amount Amount to withdraw
     * Requirements:
     * - Must be called by master admin
     * - Recipient must be valid
     * - Amount must not exceed collected fees
     */
    function withdrawFees(address payable recipient, uint256 amount) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
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
     * @dev Update implementation contract address
     * @param newImplementation Address of the new implementation
     * Requirements:
     * - Must be called by master admin
     * - New implementation must be valid
     * - New implementation must be different from current
     * - New implementation must be a contract
     */
    function updateImplementation(address newImplementation) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
    {
        if(newImplementation == address(0)) revert InvalidImplementation();
        if(newImplementation == implementationContract) revert SameImplementation();
        if(!_isContract(newImplementation)) revert NotContractAddress();
        
        address oldImplementation = implementationContract;
        implementationContract = newImplementation;
        
        emit ImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @dev Deactivate an organization
     * @param organization Address of the organization
     * Requirements:
     * - Must be called by master admin
     * - Organization must be active
     */
    function deactivateOrganization(address organization) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
    {
        if(!organizationInfo[organization].isActive) revert OrganizationNotActive();
        organizationInfo[organization].isActive = false;
        emit OrganizationDeactivated(organization, block.timestamp);
    }

    /**
     * @dev Update default configuration
     * @param newConfig New configuration structure
     * Requirements:
     * - Must be called by master admin
     * - Configuration must be valid
     */
    function updateDefaultConfig(DeploymentConfig memory newConfig) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
    {
        _validateConfig(newConfig);
        defaultConfig = newConfig;
        emit ConfigurationUpdated(newConfig);
    }

    /**
     * @dev Get a batch of deployed contracts
     * @param offset Starting index
     * @param limit Maximum number of contracts to return
     * @return address[] Array of contract addresses
     */
    function getDeployedContracts(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory) 
    {
        uint256 end = offset + limit;
        if (end > deployedContracts.length) {
            end = deployedContracts.length;
        }
        
        address[] memory batch = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            batch[i - offset] = deployedContracts[i];
        }
        
        return batch;
    }

    /**
     * @dev Get details about an organization
     * @param organization Address of the organization
     * @return contractAddress Address of the organization's contract
     * @return isActive Whether the organization is active
     * @return subscriptionEnd Timestamp when subscription ends
     * @return subscriptionDuration Duration of the subscription
     * @return isInGracePeriod Whether the organization is in grace period
     */
    function getOrganizationDetails(address organization) 
        external 
        view 
        returns (
            address contractAddress,
            bool isActive,
            uint256 subscriptionEnd,
            uint256 subscriptionDuration,
            bool isInGracePeriod
        ) 
    {
        OrganizationInfo memory info = organizationInfo[organization];
        return (
            organizationToContract[organization],
            info.isActive,
            info.subscriptionEnd,
            info.subscriptionDuration,
            block.timestamp > info.subscriptionEnd && 
            block.timestamp <= info.subscriptionEnd + GRACE_PERIOD
        );
    }

    /**
     * @dev Get default configuration
     * @return DeploymentConfig Default configuration structure
     */
    function getDefaultConfig() external view returns (DeploymentConfig memory) {
        return defaultConfig;
    }

    /**
     * @dev Pause contract in case of emergency
     * Requirements:
     * - Must be called by master admin
     */
    function pause() external onlyRole(MASTER_ADMIN_ROLE) {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @dev Unpause contract
     * Requirements:
     * - Must be called by master admin
     */
    function unpause() external onlyRole(MASTER_ADMIN_ROLE) {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    /**
     * @dev Validate configuration parameters
     * @param config Configuration structure to validate
     * Requirements:
     * - Revenue share must not exceed maximum
     * - Subscription fee must be within range
     * - Subscription duration must be within range
     */
    function _validateConfig(DeploymentConfig memory config) internal pure {
        if(config.revenueShare > MAX_REVENUE_SHARE) revert InvalidRevenueShare();
        if(config.subscriptionFee < MIN_SUBSCRIPTION_FEE || 
           config.subscriptionFee > MAX_SUBSCRIPTION_FEE) revert InvalidSubscriptionFee();
        if(config.subscriptionDuration < MIN_SUBSCRIPTION_DURATION || 
           config.subscriptionDuration > MAX_SUBSCRIPTION_DURATION) revert InvalidSubscriptionDuration();
    }

    /**
     * @dev Check if an address is a contract
     * @param account Address to check
     * @return bool True if address is a contract
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Handle direct payments
     * Requirements:
     * - Direct payments are not allowed
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