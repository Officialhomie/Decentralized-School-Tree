// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@openzeppelin/contracts/access/AccessControl.sol";
import "node_modules/@openzeppelin/contracts/utils/Pausable.sol";
import "node_modules/@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "node_modules/@openzeppelin/contracts/utils/Strings.sol";

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
error InvalidRoleRegistry();

/**
 * @title IRoleRegistry
 * @dev Interface for centralized role management
 */
interface IRoleRegistry {
    function checkRole(bytes32 role, address account, address school) external view returns (bool);
    function grantSchoolRole(bytes32 role, address account, address school) external;
    function revokeSchoolRole(bytes32 role, address account, address school) external;
}

/**
 * @title ISchoolManagement
 * @dev Interface for school management functionality
 */
interface ISchoolManagement {
    function isProgramActive(uint256 programId) external view returns (bool);
    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256);
}

/**
 * @title StudentProfile
 * @dev Manages student profiles, reputations, and school enrollments
 */
contract StudentProfile is AccessControl, Pausable, Initializable {
    // Role identifiers
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");

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
        uint256 programId;
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

    // Interface instances
    ISchoolManagement public schoolManagement;
    
    // Master admin address
    address public masterAdmin;

    // Events
    event StudentRegistered(address indexed student, string name, address indexed school, uint256 programId);
    event StudentDeactivated(address indexed student, uint256 timestamp);
    event AttendanceUpdated(address indexed student, uint256 totalClasses, uint256 attendedClasses);
    event ReputationUpdated(
        address indexed student, 
        uint256 attendancePoints, 
        uint256 behaviorPoints, 
        uint256 academicPoints
    );
    event SchoolDeactivated(address indexed school);
    event TermCompleted(address indexed student, uint256 term);
    event ReputationPenalty(address indexed student, uint256 points, string reason);
    event StudentTransferred(address indexed student, address fromSchool, address toSchool);
    event SchoolManagementSet(address indexed schoolManagement);
    event SchoolActivated(address indexed school);
    event ContractPaused(address indexed pauser);
    event ContractUnpaused(address indexed unpauser);
    event StudentInitialized(address indexed masterAdmin, address indexed roleRegistry);
    event StudentProgramUpdated(address indexed student, uint256 programId);

    /**
     * @dev Constructor disables initializers
     */
    constructor() {
        // _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     */
    function initialize(
        address _masterAdmin
    ) public initializer {
        if(_masterAdmin == address(0)) revert InvalidMasterAdmin();
        
        masterAdmin = _masterAdmin;
        
        // Set up initial roles
        _grantRole(DEFAULT_ADMIN_ROLE, _masterAdmin);
        _grantRole(MASTER_ADMIN_ROLE, _masterAdmin);
        
        emit StudentInitialized(_masterAdmin, address(0));
    }

    /**
     * @dev Returns true if account has been granted role
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return super.hasRole(role, account);
    }
    
    /**
     * @dev Grants role to account
     */
    function grantRole(bytes32 role, address account) public virtual override {
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(account),
                        " is missing role ",
                        Strings.toHexString(uint256(DEFAULT_ADMIN_ROLE), 32)
                    )
                )
            );
        }
        _grantRole(role, account);
    }

    /**
     * @dev Revokes role from account
     */
    function revokeRole(bytes32 role, address account) public virtual override {
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(account),
                        " is missing role ",
                        Strings.toHexString(uint256(DEFAULT_ADMIN_ROLE), 32)
                    )
                )
            );
        }
        _revokeRole(role, account);
    }

    /**
     * @dev Modifier to check if caller has a specific role
     */
    modifier onlyHasRole(bytes32 role) {
        if(!hasRole(role, msg.sender)) revert Unauthorized();
        _;
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
     */
    modifier onlyActiveStudent(address student) {
        if(!students[student].isActive) revert StudentNotActive();
        _;
    }

    /**
     * @dev Set the school management contract
     */
    function setSchoolManagement(address _schoolManagement) 
        external 
        onlyHasRole(MASTER_ADMIN_ROLE) 
    {
        if(_schoolManagement == address(0)) revert InvalidAddress();
        if(address(schoolManagement) != address(0)) revert AlreadySet();
        schoolManagement = ISchoolManagement(_schoolManagement);
        emit SchoolManagementSet(_schoolManagement);
    }

    /**
     * @dev Activate a school
     */
    function activateSchool(address school) 
        external 
        onlyHasRole(MASTER_ADMIN_ROLE) 
    {
        isActiveSchool[school] = true;
        emit SchoolActivated(school);
    }

    /**
     * @dev Deactivate a school
     */
    function deactivateSchool(address school) 
        external 
        onlyHasRole(MASTER_ADMIN_ROLE) 
    {
        isActiveSchool[school] = false;
        emit SchoolDeactivated(school);
    }

    /**
     * @dev Register a new student
     */
    function registerStudent(
        address student, 
        string memory name
    ) 
        external 
        onlyHasRole(TEACHER_ROLE) 
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
     */
    function updateAttendance(
        address student,
        bool attended
    ) 
        external 
        onlyHasRole(TEACHER_ROLE) 
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
     */
    function updateReputation(
        address student,
        uint256 attendancePoints,
        uint256 behaviorPoints,
        uint256 academicPoints
    ) 
        external 
        onlyHasRole(TEACHER_ROLE) 
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
     */
    function applyReputationPenalty(
        address student,
        uint256 points,
        string memory reason
    ) 
        external 
        onlyHasRole(TEACHER_ROLE) 
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
     */
    function completeStudentTerm(address student) 
        external 
        onlyHasRole(TEACHER_ROLE) 
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
     */
    function transferStudent(
        address student,
        address newSchool
    ) 
        external 
        onlyHasRole(MASTER_ADMIN_ROLE) 
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
     */
    function deactivateStudent(address student) 
        external 
        onlyHasRole(TEACHER_ROLE) 
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        students[student].isActive = false;
        
        emit StudentDeactivated(student, block.timestamp);
    }

    /**
     * @dev Get student reputation information
     */
    function getStudentReputation(address student) 
        external 
        view 
        returns (Reputation memory) 
    {
        if(students[student].school != msg.sender && !hasRole(MASTER_ADMIN_ROLE, msg.sender))
            revert Unauthorized();
        return students[student].reputation;
    }

    /**
     * @dev Get student's program ID
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
     * @dev Update student's program ID
     */
    function updateStudentProgram(address student, uint256 programId) 
        external 
        onlyHasRole(TEACHER_ROLE) 
        onlyActiveStudent(student)
    {
        if(students[student].school != msg.sender) revert Unauthorized();
        if(!schoolManagement.isProgramActive(programId)) revert ProgramNotActive();
        
        students[student].programId = programId;
        emit StudentProgramUpdated(student, programId);
    }

    /**
     * @dev Validate program enrollment for a student
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
     */
    function pause() external onlyHasRole(MASTER_ADMIN_ROLE) {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyHasRole(MASTER_ADMIN_ROLE) {
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
