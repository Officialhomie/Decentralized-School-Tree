// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "node_modules/@openzeppelin/contracts/utils/Pausable.sol";
import "node_modules/@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title IStudentProfile
 * @dev Interface for student profile validation
 */
interface IStudentProfile {
    /**
     * @dev Check if student is enrolled in a school
     * @param student Address of the student
     * @param school Address of the school
     * @return bool True if student is enrolled in the school
     */
    function isStudentOfSchool(address student, address school) external view returns (bool);
    
    /**
     * @dev Get program ID that student is enrolled in
     * @param student Address of the student
     * @return uint256 Program ID
     */
    function getStudentProgram(address student) external view returns (uint256);
}

/**
 * @title TuitionSystem
 * @dev Manages tuition payments, fees, and financial records
 * 
 * This contract handles:
 * - Setting program-specific fees
 * - Processing tuition payments
 * - Tracking payment status
 * - Late fee management
 * - School balance withdrawals
 */
contract TuitionSystem is AccessControl, Pausable, Initializable {
    // Role identifiers
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");

    // Custom errors
    error InvalidStudentProfileAddress();
    error InvalidMasterAdminAddress();
    error LateFeePercentageTooHigh();
    error NotEnrolledInSchool();
    error ProgramFeesNotSet();
    error TuitionAlreadyPaid();
    error InsufficientPayment();
    error NoBalanceToWithdraw();
    error PaymentAlreadyRecorded();

    /**
     * @dev Struct for tuition fee details
     */
    struct TuitionFee {
        uint256 amount;
        uint256 dueDate;
        bool isPaid;
        uint256 programId;  // Added to track program-specific fees
        uint256 lateFee;    // Added for late payment penalties
    }

    /**
     * @dev Struct for program fee structure
     */
    struct ProgramFees {
        uint256 registrationFee;
        uint256 termFee;
        uint256 graduationFee;
        uint256 lateFeePercentage;  // Added for late fee calculation
        bool isActive;
    }

    // School -> Program -> Fees
    mapping(address => mapping(uint256 => ProgramFees)) public programFees;
    // School -> Student -> Term -> TuitionFee
    mapping(address => mapping(address => mapping(uint256 => TuitionFee))) public tuitionFees;
    // School -> Balance
    mapping(address => uint256) public schoolBalance;

    IStudentProfile public studentProfile;

    /**
     * @dev Emitted when tuition is paid
     * @param student Address of the student
     * @param school Address of the school
     * @param term Term number
     * @param programId Program ID
     * @param amount Amount paid
     */
    event TuitionPaid(
        address indexed student, 
        address indexed school, 
        uint256 term,
        uint256 programId,
        uint256 amount
    );

    /**
     * @dev Emitted when program fees are updated
     * @param school Address of the school
     * @param programId Program ID
     * @param registrationFee Registration fee
     * @param termFee Term fee
     * @param graduationFee Graduation fee
     * @param lateFeePercentage Late fee percentage
     */
    event ProgramFeesUpdated(
        address indexed school,
        uint256 indexed programId,
        uint256 registrationFee,
        uint256 termFee,
        uint256 graduationFee,
        uint256 lateFeePercentage
    );

    /**
     * @dev Emitted when late fee is charged
     * @param student Address of the student
     * @param school Address of the school
     * @param term Term number
     * @param amount Late fee amount
     */
    event LateFeeCharged(
        address indexed student,
        address indexed school,
        uint256 term,
        uint256 amount
    );

    /**
     * @dev Emitted when payment is recorded
     * @param student Address of the student
     * @param term Term number
     * @param amount Amount paid
     */
    event PaymentRecorded(
        address indexed student,
        uint256 term,
        uint256 amount
    );

    /**
     * @dev Emitted when contract is initialized
     * @param studentProfile Address of the student profile
     * @param masterAdmin Address of the master admin
     */
    event ContractInitialized(
        address studentProfile,
        address masterAdmin
    );

    /**
     * @dev Emitted when balance is withdrawn
     * @param school Address of the school
     * @param amount Amount withdrawn
     */
    event BalanceWithdrawn(
        address indexed school,
        uint256 amount
    );

    /**
     * @dev Emitted when contract is paused
     * @param pauser Address of the pauser
     */
    event ContractPaused(
        address indexed pauser
    );

    /**
     * @dev Emitted when contract is unpaused
     * @param unpauser Address of the unpauser
     */
    event ContractUnpaused(
        address indexed unpauser
    );

    /**
     * @dev Constructor disables initializers
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param _studentProfile Address of the student profile
     * @param _masterAdmin Address of the master admin
     * Requirements:
     * - Student profile address must be valid
     * - Master admin address must be valid
     */
    function initialize(
        address _studentProfile,
        address _masterAdmin
    ) public initializer {
        if (_studentProfile == address(0)) revert InvalidStudentProfileAddress();
        if (_masterAdmin == address(0)) revert InvalidMasterAdminAddress();

        studentProfile = IStudentProfile(_studentProfile);
        
        _grantRole(DEFAULT_ADMIN_ROLE, _masterAdmin);
        _grantRole(MASTER_ADMIN_ROLE, _masterAdmin);

        emit ContractInitialized(_studentProfile, _masterAdmin);
    }

    /**
     * @dev Set fees for a program
     * @param programId Program ID
     * @param _registrationFee Registration fee
     * @param _termFee Term fee
     * @param _graduationFee Graduation fee
     * @param _lateFeePercentage Late fee percentage
     * Requirements:
     * - Must be called by an admin
     * - Contract must not be paused
     * - Late fee percentage must not exceed 50%
     */
    function setProgramFees(
        uint256 programId,
        uint256 _registrationFee,
        uint256 _termFee,
        uint256 _graduationFee,
        uint256 _lateFeePercentage
    ) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_lateFeePercentage > 50) revert LateFeePercentageTooHigh();
        
        programFees[msg.sender][programId] = ProgramFees({
            registrationFee: _registrationFee,
            termFee: _termFee,
            graduationFee: _graduationFee,
            lateFeePercentage: _lateFeePercentage,
            isActive: true
        });

        emit ProgramFeesUpdated(
            msg.sender,
            programId,
            _registrationFee,
            _termFee,
            _graduationFee,
            _lateFeePercentage
        );
    }

    /**
     * @dev Pay tuition
     * @param school Address of the school
     * @param term Term number
     * Requirements:
     * - Contract must not be paused
     * - Student must be enrolled in the school
     * - Program fees must be set and active
     * - Tuition must not already be paid
     * - Payment must cover required amount including late fees if applicable
     */
    function payTuition(
        address school,
        uint256 term
    ) external payable whenNotPaused {
        if (!studentProfile.isStudentOfSchool(msg.sender, school)) revert NotEnrolledInSchool();
        
        uint256 programId = studentProfile.getStudentProgram(msg.sender);
        ProgramFees memory fees = programFees[school][programId];
        if (!fees.isActive) revert ProgramFeesNotSet();

        TuitionFee storage fee = tuitionFees[school][msg.sender][term];
        if (fee.isPaid) revert TuitionAlreadyPaid();

        uint256 totalAmount = fees.termFee;
        
        // Calculate late fee if payment is overdue
        if (fee.dueDate > 0 && block.timestamp > fee.dueDate) {
            uint256 lateFee = (fees.termFee * fees.lateFeePercentage) / 100;
            totalAmount += lateFee;
            fee.lateFee = lateFee;
            
            emit LateFeeCharged(msg.sender, school, term, lateFee);
        }

        if (msg.value < totalAmount) revert InsufficientPayment();

        fee.amount = msg.value;
        fee.isPaid = true;
        fee.dueDate = block.timestamp + 180 days; // 6 months term
        fee.programId = programId;

        schoolBalance[school] += msg.value;

        emit TuitionPaid(msg.sender, school, term, programId, msg.value);
    }

    /**
     * @dev Withdraw school balance
     * Requirements:
     * - Must be called by an admin
     * - Contract must not be paused
     * - School must have balance to withdraw
     */
    function withdrawBalance() external onlyRole(ADMIN_ROLE) whenNotPaused {
        uint256 amount = schoolBalance[msg.sender];
        if (amount == 0) revert NoBalanceToWithdraw();

        schoolBalance[msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit BalanceWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Check tuition status
     * @param school Address of the school
     * @param student Address of the student
     * @param term Term number
     * @return isPaid Whether tuition is paid
     * @return dueDate Due date for the tuition
     */
    function checkTuitionStatus(
        address school, 
        address student, 
        uint256 term
    ) external view returns (bool isPaid, uint256 dueDate) {
        TuitionFee memory fee = tuitionFees[school][student][term];
        return (fee.isPaid, fee.dueDate);
    }

    /**
     * @dev Record tuition payment
     * @param student Address of the student
     * @param term Term number
     * Requirements:
     * - Must be called by a school
     * - Contract must not be paused
     * - Payment must not already be recorded
     */
    function recordTuitionPayment(
        address student,
        uint256 term
    ) external onlyRole(SCHOOL_ROLE) whenNotPaused {
        TuitionFee storage fee = tuitionFees[msg.sender][student][term];
        if (fee.isPaid) revert PaymentAlreadyRecorded();
        
        fee.isPaid = true;
        fee.dueDate = block.timestamp + 180 days;
        
        emit PaymentRecorded(student, term, fee.amount);
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
}

/*
This contract is like a digital payment system for schools. Here's what it does in simple terms:

1. Fee Management:
   - Schools can set up different fees for their programs (registration, term fees, graduation fees)
   - They can also set late payment penalties (up to 50% of the term fee)

2. Student Payments:
   - Students can pay their tuition fees directly through the system
   - The system checks if they're actually enrolled in the school
   - If they pay late, they get charged extra fees
   - Each payment is for a 6-month term

3. School Finance:
   - Schools can see how much money they've collected
   - They can withdraw their collected fees whenever they want
   - The system keeps track of who paid what and when

4. Safety Features:
   - Only authorized people can access certain functions
   - There's an emergency stop button (pause function) if something goes wrong
   - The system verifies everything before processing payments

Think of it like a digital cashier's office for a school, but instead of going to a physical office,
everything is handled automatically through the blockchain. It makes sure students pay the right amount,
on time, and that schools can easily manage and collect their fees.
*/