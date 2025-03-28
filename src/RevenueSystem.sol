// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "node_modules/@openzeppelin/contracts/utils/Pausable.sol";
import "node_modules/@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Custom errors
error InvalidMasterAdmin();
error InvalidSchoolManagement();
error InvalidTuitionSystem();
error InvalidRevenueShare();
error InvalidPaymentAmount();
error ProgramNotActive();
error NoRevenueToWithdraw();
error TooSoonToWithdraw();
error InsufficientFee();
error TuitionNotPaid();
error InvalidRevenueSharePercentage();
error InvalidSubscriptionFee();
error InvalidProgramFee();
error InvalidCertificateFee();
error FeeSyncFailed();
error DirectTransfersNotAllowed();
error SubscriptionExpired();
error InvalidSchool();

/**
 * @title ISchoolManagement
 * @dev Interface for interacting with school management functionality
 */
interface ISchoolManagement {
    /**
     * @dev Checks if a program is active
     * @param programId ID of the program to check
     * @return bool True if program is active, false otherwise
     */
    function isProgramActive(uint256 programId) external view returns (bool);
    
    /**
     * @dev Gets details about a specific program
     * @param programId ID of the program
     * @return name The name of the program
     * @return termFee The fee for each term of the program
     */
    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee);
    
    /**
     * @dev Gets the program a student is enrolled in
     * @param student Address of the student
     * @return uint256 ID of the program the student is enrolled in
     */
    function getStudentProgram(address student) external view returns (uint256);
    
    /**
     * @dev Updates program fees
     * @param programFee New fee for creating programs
     * @param certificateFee New fee for issuing certificates
     */
    function updateProgramFees(uint256 programFee, uint256 certificateFee) external;
}

/**
 * @title ITuitionSystem
 * @dev Interface for checking student tuition payment status
 */
interface ITuitionSystem {
    /**
     * @dev Checks if a student's tuition is paid for a specific term
     * @param school Address of the school
     * @param student Address of the student
     * @param term Term number to check
     * @return isPaid Boolean indicating if tuition is paid
     * @return dueDate Timestamp of the due date for the tuition
     */
    function checkTuitionStatus(address school, address student, uint256 term) external view returns (bool isPaid, uint256 dueDate);
}

/**
 * @title RevenueSystem
 * @dev Manages the financial aspects of the education platform including fee collection,
 * revenue distribution, and tracking of financial metrics.
 * 
 * This contract handles:
 * - Fee structures for schools
 * - Revenue sharing between platform and schools
 * - Subscription management
 * - Certificate issuance fees
 * - Revenue tracking per program
 * - School revenue withdrawals
 */
contract RevenueSystem is AccessControl, Pausable, Initializable {
    // Role definitions for access control
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");

    /**
     * @dev Struct to define fee structure for schools
     */
    struct FeeStructure {
        uint256 programCreationFee;    // Fee for creating a new program
        uint256 subscriptionFee;       // Monthly subscription fee
        uint256 certificateFee;        // Fee for issuing certificates
        uint256 revenueSharePercentage; // Platform's share of revenue
        bool isCustom;                  // Whether school has custom fee structure
    }

    /**
     * @dev Struct to track revenue information for each school
     */
    struct Revenue {
        uint256 totalRevenue;          // Total revenue collected
        uint256 platformShare;         // Platform's share of revenue
        uint256 schoolShare;           // School's share of revenue
        uint256 lastWithdrawalTime;    // Timestamp of last withdrawal
    }

    // Mappings for tracking various fees and revenue
    mapping(address => FeeStructure) public schoolFeeStructures;  // Custom fee structures per school
    mapping(address => Revenue) public revenueTracking;           // Revenue tracking per school
    mapping(address => uint256) public subscriptionEndTimes;      // Subscription expiry times
    
    // Tracking revenue per program for each school
    mapping(address => mapping(uint256 => uint256)) public programRevenue;
    
    // Contract interfaces
    ISchoolManagement public schoolManagement;
    ITuitionSystem public tuitionSystem;

    // Default fee structure for all schools
    FeeStructure public defaultFeeStructure;

    /**
     * @dev Emitted when revenue is received from tuition payment
     * @param school Address of the school
     * @param programId ID of the program
     * @param amount Total amount received
     * @param platformShare Amount allocated to the platform
     * @param schoolShare Amount allocated to the school
     */
    event RevenueReceived(
        address indexed school,
        uint256 indexed programId,
        uint256 amount,
        uint256 platformShare,
        uint256 schoolShare
    );

    /**
     * @dev Emitted when a school withdraws their revenue share
     * @param school Address of the school
     * @param amount Amount withdrawn
     * @param timestamp Time of withdrawal
     */
    event RevenueWithdrawn(
        address indexed school,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a fee structure is updated
     * @param school Address of the school (address(0) for default)
     * @param programCreationFee New program creation fee
     * @param subscriptionFee New subscription fee
     * @param certificateFee New certificate fee
     * @param revenueSharePercentage New revenue share percentage
     */
    event FeeStructureUpdated(
        address indexed school,
        uint256 programCreationFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueSharePercentage
    );

    /**
     * @dev Emitted when a subscription is renewed
     * @param school Address of the school
     * @param validUntil Timestamp when subscription expires
     * @param amount Amount paid for renewal
     */
    event SubscriptionRenewed(
        address indexed school,
        uint256 validUntil,
        uint256 amount
    );

    /**
     * @dev Emitted when a certificate is issued
     * @param student Address of the student
     * @param school Address of the school
     * @param batchId Batch ID for the certificate
     * @param fee Fee paid for the certificate
     */
    event CertificateIssued(
        address indexed student,
        address indexed school,
        uint256 batchId,
        uint256 fee
    );

    /**
     * @dev Emitted when program revenue is locked
     * @param school Address of the school
     * @param programId ID of the program
     * @param amount Amount locked
     */
    event ProgramRevenueLocked(
        address indexed school,
        uint256 indexed programId,
        uint256 amount
    );

    /**
     * @dev Emitted when contract is initialized
     * @param schoolManagement Address of the school management contract
     * @param tuitionSystem Address of the tuition system contract
     * @param masterAdmin Address of the master admin
     */
    event ContractInitialized(
        address schoolManagement,
        address tuitionSystem,
        address masterAdmin
    );

    /**
     * @dev Emitted when contract is paused
     * @param pauser Address of the pauser
     */
    event ContractPaused(address pauser);

    /**
     * @dev Emitted when contract is unpaused
     * @param unpauser Address of the unpauser
     */
    event ContractUnpaused(address unpauser);

    /**
     * @dev Constructor disables initializers for implementation contract
     */
    constructor() {
        // _disableInitializers();
    }

    /**
     * @dev Initializes the contract with configuration parameters
     * @param _schoolManagement Address of school management contract
     * @param _tuitionSystem Address of tuition system contract
     * @param masterAdmin Address of master admin
     * @param defaultProgramFee Default fee for program creation
     * @param defaultSubscriptionFee Default subscription fee
     * @param defaultCertificateFee Default certificate fee
     * @param defaultRevenueShare Default platform revenue share percentage
     */
    function initialize(
        address _schoolManagement,
        address _tuitionSystem,
        address masterAdmin,
        uint256 defaultProgramFee,
        uint256 defaultSubscriptionFee,
        uint256 defaultCertificateFee,
        uint256 defaultRevenueShare
    ) public initializer {
        if(masterAdmin == address(0)) revert InvalidMasterAdmin();
        if(_schoolManagement == address(0)) revert InvalidSchoolManagement();
        if(_tuitionSystem == address(0)) revert InvalidTuitionSystem();
        if(defaultRevenueShare > 100) revert InvalidRevenueShare();

        schoolManagement = ISchoolManagement(_schoolManagement);
        tuitionSystem = ITuitionSystem(_tuitionSystem);

        defaultFeeStructure = FeeStructure({
            programCreationFee: defaultProgramFee,
            subscriptionFee: defaultSubscriptionFee,
            certificateFee: defaultCertificateFee,
            revenueSharePercentage: defaultRevenueShare,
            isCustom: false
        });

        _grantRole(MASTER_ADMIN_ROLE, masterAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, masterAdmin);

        emit ContractInitialized(_schoolManagement, _tuitionSystem, masterAdmin);
    }

    /**
     * @dev Modifier to check if school's subscription is active
     */
    modifier onlyActiveSubscription() {
        if(block.timestamp > subscriptionEndTimes[msg.sender]) revert SubscriptionExpired();
        _;
    }

    /**
     * @dev Modifier to verify if address has school role
     * @param school Address to check
     */
    modifier onlyValidSchool(address school) {
        if(!hasRole(SCHOOL_ROLE, school) && school != msg.sender) revert InvalidSchool();
        _;
    }

    /**
     * @dev Process tuition payment and distribute revenue shares
     * @param student Address of the student
     * @param amount Amount of tuition payment
     */
    function processTuitionPayment(address student, uint256 amount) 
        external 
        payable 
        onlyValidSchool(msg.sender) 
        onlyActiveSubscription 
        whenNotPaused 
    {
        if(msg.value != amount) revert InvalidPaymentAmount();

        uint256 programId = schoolManagement.getStudentProgram(student);
        if(!schoolManagement.isProgramActive(programId)) revert ProgramNotActive();

        FeeStructure memory fees = schoolFeeStructures[msg.sender].isCustom ? 
            schoolFeeStructures[msg.sender] : defaultFeeStructure;

        uint256 platformShare = (amount * fees.revenueSharePercentage) / 100;
        uint256 schoolShare = amount - platformShare;

        // Update revenue tracking
        Revenue storage revenue = revenueTracking[msg.sender];
        revenue.totalRevenue += amount;
        revenue.platformShare += platformShare;
        revenue.schoolShare += schoolShare;

        // Track program-specific revenue
        programRevenue[msg.sender][programId] += amount;

        emit RevenueReceived(msg.sender, programId, amount, platformShare, schoolShare);
        emit ProgramRevenueLocked(msg.sender, programId, amount);
    }

    /**
     * @dev Allow schools to withdraw their share of revenue
     * Requirements:
     * - Must be called by a valid school
     * - Contract must not be paused
     * - School must have revenue to withdraw
     * - At least 1 day since last withdrawal
     */
    function withdrawSchoolRevenue() 
        external 
        onlyValidSchool(msg.sender) 
        whenNotPaused 
    {
        Revenue storage revenue = revenueTracking[msg.sender];
        if(revenue.schoolShare == 0) revert NoRevenueToWithdraw();
        if(block.timestamp < revenue.lastWithdrawalTime + 1 days) revert TooSoonToWithdraw();

        uint256 amount = revenue.schoolShare;
        revenue.schoolShare = 0;
        revenue.lastWithdrawalTime = block.timestamp;

        payable(msg.sender).transfer(amount);
        emit RevenueWithdrawn(msg.sender, amount, block.timestamp);
    }

    /**
     * @dev Allow schools to renew their subscription
     * Requirements:
     * - Must be called by a valid school
     * - Contract must not be paused
     * - Must pay at least the subscription fee
     */
    function renewSubscription() 
        external 
        payable 
        onlyValidSchool(msg.sender) 
        whenNotPaused 
    {
        FeeStructure memory fees = schoolFeeStructures[msg.sender].isCustom ? 
            schoolFeeStructures[msg.sender] : defaultFeeStructure;

        if(msg.value < fees.subscriptionFee) revert InsufficientFee();

        uint256 newEndTime = block.timestamp + 30 days;
        if (subscriptionEndTimes[msg.sender] > block.timestamp) {
            newEndTime = subscriptionEndTimes[msg.sender] + 30 days;
        }
        
        subscriptionEndTimes[msg.sender] = newEndTime;
        emit SubscriptionRenewed(msg.sender, newEndTime, msg.value);
    }

    /**
     * @dev Allow schools to issue certificates to students
     * @param student Address of the student
     * @param batchId Batch ID for the certificate
     * Requirements:
     * - Must be called by a valid school
     * - School must have active subscription
     * - Contract must not be paused
     * - Must pay exactly the certificate fee
     * - Student must have paid tuition
     */
    function issueCertificate(address student, uint256 batchId) 
        external 
        payable 
        onlyValidSchool(msg.sender) 
        onlyActiveSubscription 
        whenNotPaused 
    {
        FeeStructure memory fees = schoolFeeStructures[msg.sender].isCustom ? 
            schoolFeeStructures[msg.sender] : defaultFeeStructure;

        if(msg.value != fees.certificateFee) revert InsufficientFee();

        // Verify tuition status
        (bool isPaid,) = tuitionSystem.checkTuitionStatus(msg.sender, student, 0);
        if(!isPaid) revert TuitionNotPaid();

        emit CertificateIssued(student, msg.sender, batchId, msg.value);
    }

    /**
     * @dev Set custom fee structure for a school
     * @param school Address of the school
     * @param programFee Fee for program creation
     * @param subscriptionFee Fee for subscription
     * @param certificateFee Fee for certificate issuance
     * @param revenueShare Platform's share of revenue (percentage)
     * Requirements:
     * - Must be called by master admin
     * - Revenue share must be less than 100%
     * - All fees must be greater than 0
     */
    function setCustomFeeStructure(
        address school,
        uint256 programFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueShare
    ) external onlyRole(MASTER_ADMIN_ROLE) {
        if(revenueShare >= 100) revert InvalidRevenueSharePercentage();
        if(subscriptionFee == 0) revert InvalidSubscriptionFee();
        if(programFee == 0) revert InvalidProgramFee();
        if(certificateFee == 0) revert InvalidCertificateFee();

        schoolFeeStructures[school] = FeeStructure({
            programCreationFee: programFee,
            subscriptionFee: subscriptionFee,
            certificateFee: certificateFee,
            revenueSharePercentage: revenueShare,
            isCustom: true
        });

        emit FeeStructureUpdated(
            school,
            programFee,
            subscriptionFee,
            certificateFee,
            revenueShare
        );
    }

    /**
     * @dev Sync fee structure with school management
     * @param school Address of the school
     * Requirements:
     * - Must be called by a valid school
     */
    function syncFeeStructure(address school) external onlyValidSchool(msg.sender) {
        FeeStructure memory fees = schoolFeeStructures[school].isCustom ? 
            schoolFeeStructures[school] : defaultFeeStructure;
            
        try ISchoolManagement(schoolManagement).updateProgramFees(
            fees.programCreationFee,
            fees.certificateFee
        ) {
            emit FeeStructureUpdated(
                school,
                fees.programCreationFee,
                fees.subscriptionFee,
                fees.certificateFee,
                fees.revenueSharePercentage
            );
        } catch {
            revert FeeSyncFailed();
        }
    }

    /**
     * @dev Update default fee structure for all schools
     * @param programFee New program creation fee
     * @param subscriptionFee New subscription fee
     * @param certificateFee New certificate fee
     * @param revenueShare New platform revenue share percentage
     * Requirements:
     * - Must be called by master admin
     * - Revenue share must be <= 100%
     */
    function updateDefaultFeeStructure(
        uint256 programFee,
        uint256 subscriptionFee,
        uint256 certificateFee,
        uint256 revenueShare
    ) external onlyRole(MASTER_ADMIN_ROLE) {
        if(revenueShare > 100) revert InvalidRevenueSharePercentage();

        defaultFeeStructure = FeeStructure({
            programCreationFee: programFee,
            subscriptionFee: subscriptionFee,
            certificateFee: certificateFee,
            revenueSharePercentage: revenueShare,
            isCustom: false
        });

        emit FeeStructureUpdated(
            address(0),
            programFee,
            subscriptionFee,
            certificateFee,
            revenueShare
        );
    }

    /**
     * @dev Get revenue for specific program
     * @param school Address of the school
     * @param programId ID of the program
     * @return uint256 Revenue for the program
     */
    function getProgramRevenue(address school, uint256 programId) 
        external 
        view 
        returns (uint256) 
    {
        return programRevenue[school][programId];
    }

    /**
     * @dev Get detailed revenue information for a school
     * @param school Address of the school
     * @return total Total revenue collected
     * @return platformShare Platform's share of revenue
     * @return schoolShare School's share of revenue
     * @return lastWithdrawal Timestamp of last withdrawal
     */
    function getRevenueDetails(address school) 
        external 
        view 
        returns (
            uint256 total,
            uint256 platformShare,
            uint256 schoolShare,
            uint256 lastWithdrawal
        ) 
    {
        Revenue memory revenue = revenueTracking[school];
        return (
            revenue.totalRevenue,
            revenue.platformShare,
            revenue.schoolShare,
            revenue.lastWithdrawalTime
        );
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
     * @dev Prevent accidental ETH transfers to contract
     */
    receive() external payable {
        revert DirectTransfersNotAllowed();
    }
}



/*
This contract is essentially a financial management system for an educational platform. Here's what it does in simple terms:

1. Schools Management:
   - Schools can join the platform and offer educational programs
   - Each school pays fees to use the platform (subscription fees)
   - Schools can create programs and issue certificates to students

2. Payment Handling:
   - Students pay tuition fees through the platform
   - The platform automatically splits the money between:
     * The school's share
     * The platform's share (like a commission)
   - Schools can withdraw their share of the money after 24 hours

3. Fee Structure:
   - There are different types of fees:
     * Program creation fees (when schools create new courses)
     * Monthly subscription fees (for schools to stay on the platform)
     * Certificate issuing fees (when schools issue certificates)
   - Each school can have either:
     * Standard fees (same for everyone)
     * Custom fees (special rates for specific schools)

4. Safety Features:
   - Only authorized schools can use the system
   - Schools must have an active subscription
   - The system can be paused in emergencies
   - Schools can only withdraw money they've earned
   - Everything is tracked and recorded

Think of it like a digital school management system that handles all the money matters - 
like collecting tuition, paying schools their share, and making sure everyone follows the rules.
*/
