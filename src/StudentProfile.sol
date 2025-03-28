// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "node_modules/@openzeppelin/contracts/utils/Pausable.sol";
import "node_modules/@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Custom errors
error InvalidMasterAdmin();
error SchoolNotActive();
error StudentNotActive();
error InvalidAddress();
error AlreadySet();
error StudentAlreadyRegistered();
error Unauthorized();
error TooSoonForAttendance();
error PenaltyTooHigh();
error StudentNotRegistered();
error InvalidNewSchool();
error ProgramNotActive();

/**
 * @title ISchoolManagement
 * @dev Interface for interacting with school management functionality
 */
interface ISchoolManagement {
    /**
     * @dev Check if a program is active
     * @param programId ID of the program to check
     * @return bool True if program is active
     */
    function isProgramActive(uint256 programId) external view returns (bool);
    
    /**
     * @dev Get attendance requirement for a program
     * @param programId ID of the program
     * @return uint256 Required attendance percentage
     */
    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256);
    
    /**
     * @dev Get the program a student is enrolled in
     * @param student Address of the student
     * @return uint256 ID of the program
     */
    function getStudentProgram(address student) external view returns (uint256);
    
    /**
     * @dev Grant a role to an account
     * @param role Role identifier
     * @param account Account to grant role to
     */
    function grantRole(bytes32 role, address account) external;
    
    /**
     * @dev Update program fees
     * @param programFee New program creation fee
     * @param certificateFee New certificate fee
     */
    function updateProgramFees(uint256 programFee, uint256 certificateFee) external;
}

/**
 * @title StudentProfile
 * @dev Manages student profiles, reputations, and school enrollments
 * 
 * This contract handles:
 * - Student registration and profile management
 * - Reputation tracking (attendance, behavior, academic)
 * - School-student relationships
 * - Student transfers between schools
 * - Term completion tracking
 */
contract StudentProfile is AccessControl, Pausable, Initializable {
    // Role identifiers
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");

    /**
     * @dev Struct to track student attendance records
     */
    struct AttendanceRecord {
        uint256 totalClasses;
        uint256 attendedClasses;
        uint256 lastAttendanceDate;
        mapping(uint256 => uint256) termAttendance; // term -> attendance count
    }

    /**
     * @dev Struct to track student reputation metrics
     */
    struct Reputation {
        uint256 attendancePoints;
        uint256 behaviorPoints;
        uint256 academicPoints;
        uint256 lastUpdateTime;
    }

    /**
     * @dev Struct for student information and status
     */
    struct Student {
        string name;
        bool isRegistered;
        Reputation reputation;
        AttendanceRecord attendance;
        address school;
        uint256 currentTerm;
        bool isActive;
        uint256 registrationDate;
        uint256 programId;  // Added to track student's program
    }

    // Main storage
    mapping(address => Student) private students;
    // School tracking
    mapping(address => bool) public isActiveSchool;
    // School student count
    mapping(address => uint256) public schoolStudentCount;
    // Student term history
    mapping(address => mapping(uint256 => bool)) public completedTerms;
    mapping(address => mapping(uint256 => bool)) public tuitionPayments;

    ISchoolManagement public schoolManagement;

    /**
     * @dev Emitted when a student is registered
     * @param student Address of the student
     * @param name Name of the student
     * @param school Address of the school
     * @param programId ID of the program
     */
    event StudentRegistered(address indexed student, string name, address indexed school, uint256 programId);
    
    /**
     * @dev Emitted when a student is deactivated
     * @param student Address of the student
     * @param timestamp Time of deactivation
     */
    event StudentDeactivated(address indexed student, uint256 timestamp);
    
    /**
     * @dev Emitted when attendance is updated
     * @param student Address of the student
     * @param totalClasses Total number of classes
     * @param attendedClasses Number of attended classes
     */
    event AttendanceUpdated(address indexed student, uint256 totalClasses, uint256 attendedClasses);
    
    /**
     * @dev Emitted when reputation is updated
     * @param student Address of the student
     * @param attendancePoints Updated attendance points
     * @param behaviorPoints Updated behavior points
     * @param academicPoints Updated academic points
     */
    event ReputationUpdated(
        address indexed student, 
        uint256 attendancePoints, 
        uint256 behaviorPoints, 
        uint256 academicPoints
    );
    
    /**
     * @dev Emitted when a school is deactivated
     * @param school Address of the school
     */
    event SchoolDeactivated(address indexed school);
    
    /**
     * @dev Emitted when a term is completed
     * @param student Address of the student
     * @param term Term number
     */
    event TermCompleted(address indexed student, uint256 term);
    
    /**
     * @dev Emitted when a reputation penalty is applied
     * @param student Address of the student
     * @param points Number of penalty points
     * @param reason Reason for the penalty
     */
    event ReputationPenalty(address indexed student, uint256 points, string reason);
    
    /**
     * @dev Emitted when a student is transferred
     * @param student Address of the student
     * @param fromSchool Address of the old school
     * @param toSchool Address of the new school
     */
    event StudentTransferred(address indexed student, address fromSchool, address toSchool);
    
    /**
     * @dev Emitted when a role is granted
     * @param role Role identifier
     * @param account Account granted the role
     */
    event RoleGranted(bytes32 role, address account);
    
    /**
     * @dev Emitted when a role is revoked
     * @param role Role identifier
     * @param account Account from which the role is revoked
     */
    event RoleRevoked(bytes32 role, address account);
    
    /**
     * @dev Emitted when school management is set
     * @param schoolManagement Address of the school management
     */
    event SchoolManagementSet(address indexed schoolManagement);
    
    /**
     * @dev Emitted when a school is activated
     * @param school Address of the school
     */
    event SchoolActivated(address indexed school);
    
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
     * @dev Emitted when student profile is initialized
     * @param masterAdmin Address of the master admin
     */
    event StudentInitialized(address indexed masterAdmin);
    
    /**
     * @dev Emitted when student program is updated
     * @param student Address of the student
     * @param programId ID of the program
     */
    event StudentProgramUpdated(address indexed student, uint256 programId);

    /**
     * @dev Constructor disables initializers
     */
    constructor() {
        // _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param masterAdmin Address of the master admin
     * Requirements:
     * - Master admin address must be valid
     */
    function initialize(
        address masterAdmin
    ) public initializer {
        if(masterAdmin == address(0)) revert InvalidMasterAdmin();
        
        _grantRole(MASTER_ADMIN_ROLE, masterAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, masterAdmin);
        
        emit StudentInitialized(masterAdmin);
    }

    /**
     * @dev Modifier to check if caller is an active school
     */
    modifier onlyActiveSchool() {
        if(!isActiveSchool[msg.sender]) revert SchoolNotActive();
        _;
    }

    /**
     * @dev Modifier to check if student is active
     * @param student Address of the student
     */
    modifier onlyActiveStudent(address student) {
        if(!students[student].isActive) revert StudentNotActive();
        _;
    }

    /**
     * @dev Set the school management contract
     * @param _schoolManagement Address of the school management contract
     * Requirements:
     * - Must be called by master admin
     * - School management address must be valid
     * - School management must not already be set
     */
    function setSchoolManagement(address _schoolManagement) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
    {
        if(_schoolManagement == address(0)) revert InvalidAddress();
        if(address(schoolManagement) != address(0)) revert AlreadySet();
        schoolManagement = ISchoolManagement(_schoolManagement);
        emit SchoolManagementSet(_schoolManagement);
    }

    /**
     * @dev Activate a school
     * @param school Address of the school
     * Requirements:
     * - Must be called by master admin
     */
    function activateSchool(address school) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
    {
        isActiveSchool[school] = true;
        _grantRole(SCHOOL_ROLE, school);
        emit SchoolActivated(school);
        emit RoleGranted(SCHOOL_ROLE, school);
    }

    /**
     * @dev Deactivate a school
     * @param school Address of the school
     * Requirements:
     * - Must be called by master admin
     */
    function deactivateSchool(address school) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
    {
        isActiveSchool[school] = false;
        _revokeRole(SCHOOL_ROLE, school);
        emit SchoolDeactivated(school);
        emit RoleRevoked(SCHOOL_ROLE, school);
    }

    /**
     * @dev Register a new student
     * @param student Address of the student
     * @param name Name of the student
     * Requirements:
     * - Must be called by a teacher
     * - Caller must be an active school
     * - Contract must not be paused
     * - Student must not already be registered
     */
    function registerStudent(
        address student, 
        string memory name
    ) 
        external 
        onlyRole(TEACHER_ROLE) 
        onlyActiveSchool 
        whenNotPaused 
    {
        if(students[student].isRegistered) revert StudentAlreadyRegistered();

        Student storage newStudent = students[student];
        newStudent.name = name;
        newStudent.isRegistered = true;
        newStudent.isActive = true;
        newStudent.school = msg.sender;
        newStudent.currentTerm = 1;
        newStudent.registrationDate = block.timestamp;
        newStudent.reputation = Reputation({
            attendancePoints: 0,
            behaviorPoints: 100, // Starting behavior points
            academicPoints: 0,
            lastUpdateTime: block.timestamp
        });

        schoolStudentCount[msg.sender]++;
        
        emit StudentRegistered(student, name, msg.sender, 0);
        emit ReputationUpdated(
            student,
            0, // attendancePoints
            100, // behaviorPoints
            0 // academicPoints
        );
    }

    /**
     * @dev Update student attendance
     * @param student Address of the student
     * @param attended Boolean indicating if student attended
     * Requirements:
     * - Must be called by a teacher
     * - Caller must be an active school
     * - Student must be active
     * - Contract must not be paused
     * - Caller must be the student's school
     * - At least 20 hours since last attendance update
     */
    function updateAttendance(
        address student,
        bool attended
    ) 
        external 
        onlyRole(TEACHER_ROLE) 
        onlyActiveSchool 
        onlyActiveStudent(student)
        whenNotPaused 
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        Student storage studentData = students[student];
        if(block.timestamp <= studentData.attendance.lastAttendanceDate + 20 hours) revert TooSoonForAttendance();

        uint256 requiredAttendance = schoolManagement.getProgramAttendanceRequirement(studentData.programId);

        if (attended) {
            studentData.attendance.attendedClasses++;
            studentData.attendance.termAttendance[studentData.currentTerm]++;
            
            uint256 attendanceRate = (studentData.attendance.attendedClasses * 100) / 
                                   (studentData.attendance.totalClasses + 1);
            
            if (attendanceRate >= requiredAttendance) {
                studentData.reputation.attendancePoints += 20;
            } else {
                studentData.reputation.attendancePoints += 10;
            }
        }

        studentData.attendance.totalClasses++;
        studentData.attendance.lastAttendanceDate = block.timestamp;

        emit AttendanceUpdated(
            student,
            studentData.attendance.totalClasses,
            studentData.attendance.attendedClasses
        );
        emit ReputationUpdated(
            student,
            studentData.reputation.attendancePoints,
            studentData.reputation.behaviorPoints,
            studentData.reputation.academicPoints
        );
    }

    /**
     * @dev Update student reputation
     * @param student Address of the student
     * @param attendancePoints New attendance points
     * @param behaviorPoints New behavior points
     * @param academicPoints New academic points
     * Requirements:
     * - Must be called by a teacher
     * - Student must be active
     * - Contract must not be paused
     * - Caller must be the student's school
     */
    function updateReputation(
        address student,
        uint256 attendancePoints,
        uint256 behaviorPoints,
        uint256 academicPoints
    ) 
        external 
        onlyRole(TEACHER_ROLE) 
        onlyActiveStudent(student)
        whenNotPaused 
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        
        Student storage studentData = students[student];
        studentData.reputation.attendancePoints = attendancePoints;
        studentData.reputation.behaviorPoints = behaviorPoints;
        studentData.reputation.academicPoints = academicPoints;
        studentData.reputation.lastUpdateTime = block.timestamp;

        emit ReputationUpdated(
            student,
            attendancePoints,
            behaviorPoints,
            academicPoints
        );
    }

    /**
     * @dev Apply reputation penalty to a student
     * @param student Address of the student
     * @param points Number of penalty points
     * @param reason Reason for the penalty
     * Requirements:
     * - Must be called by a teacher
     * - Student must be active
     * - Caller must be the student's school
     * - Penalty must not exceed student's behavior points
     */
    function applyReputationPenalty(
        address student,
        uint256 points,
        string memory reason
    ) 
        external 
        onlyRole(TEACHER_ROLE) 
        onlyActiveStudent(student)
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        if(points > students[student].reputation.behaviorPoints) revert PenaltyTooHigh();

        students[student].reputation.behaviorPoints -= points;
        
        emit ReputationPenalty(student, points, reason);
        emit ReputationUpdated(
            student,
            students[student].reputation.attendancePoints,
            students[student].reputation.behaviorPoints,
            students[student].reputation.academicPoints
        );
    }

    /**
     * @dev Complete student term
     * @param student Address of the student
     * Requirements:
     * - Must be called by a teacher
     * - Student must be active
     * - Caller must be the student's school
     */
    function completeStudentTerm(address student) 
        external 
        onlyRole(TEACHER_ROLE) 
        onlyActiveStudent(student)
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        
        Student storage studentData = students[student];
        completedTerms[student][studentData.currentTerm] = true;
        studentData.currentTerm++;
        
        emit TermCompleted(student, studentData.currentTerm - 1);
    }

    /**
     * @dev Transfer student to another school
     * @param student Address of the student
     * @param newSchool Address of the new school
     * Requirements:
     * - Must be called by master admin
     * - Student must be active
     * - New school must be active
     */
    function transferStudent(
        address student,
        address newSchool
    ) 
        external 
        onlyRole(MASTER_ADMIN_ROLE) 
        onlyActiveStudent(student)
    {
        if(!isActiveSchool[newSchool]) revert InvalidNewSchool();
        
        address oldSchool = students[student].school;
        students[student].school = newSchool;
        schoolStudentCount[oldSchool]--;
        schoolStudentCount[newSchool]++;

        emit StudentTransferred(student, oldSchool, newSchool);
    }

    /**
     * @dev Deactivate a student
     * @param student Address of the student
     * Requirements:
     * - Must be called by a teacher
     * - Caller must be the student's school
     */
    function deactivateStudent(address student) 
        external 
        onlyRole(TEACHER_ROLE) 
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        students[student].isActive = false;
        emit StudentDeactivated(student, block.timestamp);
    }

    /**
     * @dev Get student reputation
     * @param student Address of the student
     * @return Reputation Student's reputation structure
     * Requirements:
     * - Student must be registered
     * - Caller must be the student's school or master admin
     */
    function getStudentReputation(address student) 
        external 
        view 
        returns (Reputation memory) 
    {
        if(!students[student].isRegistered) revert StudentNotRegistered();
        if(students[student].school != msg.sender && !hasRole(MASTER_ADMIN_ROLE, msg.sender)) revert Unauthorized();
        return students[student].reputation;
    }

    /**
     * @dev Get student's program ID
     * @param student Address of the student
     * @return uint256 Program ID
     * Requirements:
     * - Student must be registered
     */
    function getStudentProgram(address student)
        external
        view
        returns (uint256)
    {
        if(!students[student].isRegistered) revert StudentNotRegistered();
        return students[student].programId;
    }

    /**
     * @dev Check if student is enrolled in a school
     * @param student Address of the student
     * @param school Address of the school
     * @return bool True if student is enrolled in the school
     */
    function isStudentOfSchool(address student, address school) 
        external 
        view 
        returns (bool) 
    {
        return students[student].isRegistered && 
               students[student].school == school &&
               students[student].isActive;
    }

    /**
     * @dev Get student details
     * @param student Address of the student
     * @return name Name of the student
     * @return currentTerm Current term
     * @return programId Program ID
     * @return isActive Whether student is active
     * @return registrationDate Date of registration
     */
    function getStudentDetails(address student)
        external
        view
        returns (
            string memory name,
            uint256 currentTerm,
            uint256 programId,
            bool isActive,
            uint256 registrationDate
        )
    {
        Student storage studentData = students[student];
        return (
            studentData.name,
            studentData.currentTerm,
            studentData.programId,
            studentData.isActive,
            studentData.registrationDate
        );
    }

    /**
     * @dev Get student attendance
     * @param student Address of the student
     * @param term Term number
     * @return termAttendance Attendance for the term
     * @return totalAttendance Total attendance
     * Requirements:
     * - Caller must be the student's school
     */
    function getStudentAttendance(
        address student,
        uint256 term
    ) 
        external 
        view 
        returns (uint256 termAttendance, uint256 totalAttendance) 
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        return (
            students[student].attendance.termAttendance[term],
            students[student].attendance.attendedClasses
        );
    }

    /**
     * @dev Get student status
     * @param student Address of the student
     * @return isRegistered Whether student is registered
     * @return isActive Whether student is active
     * @return currentTerm Current term
     * @return school Address of the school
     */
    function getStudentStatus(address student) 
        external 
        view 
        returns (
            bool isRegistered,
            bool isActive,
            uint256 currentTerm,
            address school
        ) 
    {
        Student storage studentData = students[student];
        return (
            studentData.isRegistered,
            studentData.isActive,
            studentData.currentTerm,
            studentData.school
        );
    }

     /**
     * @dev Update student program
     * @param student Address of the student
     * @param programId ID of the program
     * Requirements:
     * - Must be called by a teacher
     * - Student must be active
     * - Caller must be the student's school
     * - Program must be active
     */
    function updateStudentProgram(address student, uint256 programId) 
        external 
        onlyRole(TEACHER_ROLE) 
        onlyActiveStudent(student) 
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        if(!schoolManagement.isProgramActive(programId)) revert ProgramNotActive();
        
        students[student].programId = programId;
        emit StudentProgramUpdated(student, programId);
    }

    /**
     * @dev Validate program enrollment for a student
     * @param student Address of the student
     * @param programId ID of the program
     * @return bool True if student is enrolled in the program
     * Requirements:
     * - Student must be registered
     * - Program must be active
     */
    function validateProgramEnrollment(
        address student, 
        uint256 programId
    ) external view returns (bool) {
        if(!students[student].isRegistered) revert StudentNotRegistered();
        if(!schoolManagement.isProgramActive(programId)) revert ProgramNotActive();
        return students[student].programId == programId;
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
This contract is like a digital student management system that schools can use to:

1. Keep Track of Students:
   - Register new students
   - Record their attendance
   - Monitor their academic performance
   - Track which term/semester they're in
   - Know which school they belong to

2. Manage Student Performance:
   - Teachers can mark attendance
   - Give points for good behavior
   - Track academic achievements
   - Record penalties for misconduct
   - Keep a reputation score for each student

3. Handle Administrative Tasks:
   - Transfer students between schools
   - Activate or deactivate student accounts
   - Complete terms/semesters
   - Check if students are properly enrolled
   - View student details and history

4. Security Features:
   - Only authorized teachers can update records
   - Only active schools can perform actions
   - System can be paused in emergencies
   - Different permission levels for different roles

Think of it as a digital school diary that can't be tampered with, where everything about 
a student's academic journey is recorded securely on the blockchain. It's like having
a permanent, transparent record book that multiple schools can trust and use.
*/
