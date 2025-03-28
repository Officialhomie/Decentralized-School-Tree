// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/StudentProfile.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


contract MockSchoolManagement {
    mapping(uint256 => bool) public programs;
    mapping(uint256 => uint256) public attendanceRequirements;
    mapping(address => uint256) public studentPrograms;

    function setProgramActive(uint256 programId, bool active) external {
        programs[programId] = active;
    }

    function setAttendanceRequirement(uint256 programId, uint256 requirement) external {
        attendanceRequirements[programId] = requirement;
    }

    function setStudentProgram(address student, uint256 programId) external {
        studentPrograms[student] = programId;
    }

    function isProgramActive(uint256 programId) external view returns (bool) {
        return programs[programId];
    }

    function getProgramAttendanceRequirement(uint256 programId) external view returns (uint256) {
        return attendanceRequirements[programId];
    }

    function getStudentProgram(address student) external view returns (uint256) {
        return studentPrograms[student];
    }

    function grantRole(bytes32, address) external pure {} 
    function updateProgramFees(uint256, uint256) external pure {} 
}

contract StudentProfileTest is Test {
    StudentProfile public implementation;
    ERC1967Proxy public proxy;
    StudentProfile public studentProfile;
    MockSchoolManagement public schoolManagement;

    address public masterAdmin;
    address public school;
    address public student;
    address public teacher;
    address public unauthorized;

    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant SCHOOL_ROLE = keccak256("SCHOOL_ROLE");
    bytes32 public constant MASTER_ADMIN_ROLE = keccak256("MASTER_ADMIN_ROLE");
    
    event StudentRegistered(address indexed student, string name, address indexed school, uint256 programId);
    event AttendanceUpdated(address indexed student, uint256 totalClasses, uint256 attendedClasses);
    event ReputationUpdated(address indexed student, uint256 attendancePoints, uint256 behaviorPoints, uint256 academicPoints);
    event StudentTransferred(address indexed student, address indexed fromSchool, address indexed toSchool);
    event StudentTermCompleted(address indexed student, uint256 term);
    event StudentProgramUpdated(address indexed student, uint256 programId);
    
    function setUp() public {
        masterAdmin = makeAddr("masterAdmin");
        school = makeAddr("school");
        student = makeAddr("student");
        teacher = makeAddr("teacher");
        unauthorized = makeAddr("unauthorized");

        // Deploy contracts
        schoolManagement = new MockSchoolManagement();
        implementation = new StudentProfile();
        
        // Initialize proxy with correct data
        bytes memory initData = abi.encodeCall(StudentProfile.initialize, (masterAdmin));
        proxy = new ERC1967Proxy(address(implementation), initData);
        studentProfile = StudentProfile(address(proxy));

        // Setup initial state with proper roles
        vm.startPrank(masterAdmin);
        studentProfile.setSchoolManagement(address(schoolManagement));
        studentProfile.activateSchool(school);
        studentProfile.grantRole(TEACHER_ROLE, school);  // Grant TEACHER_ROLE to school address
        studentProfile.grantRole(SCHOOL_ROLE, school);
        vm.stopPrank();

        // Setup program
        schoolManagement.setProgramActive(1, true);
        schoolManagement.setAttendanceRequirement(1, 80);
    }

    function test_Initialize() public view {
        assertTrue(studentProfile.hasRole(studentProfile.MASTER_ADMIN_ROLE(), masterAdmin));
        assertTrue(studentProfile.hasRole(studentProfile.DEFAULT_ADMIN_ROLE(), masterAdmin));
    }

    function test_InitializerRestrictions() public {
        // Create a new implementation for testing initialization
        StudentProfile newImplementation = new StudentProfile();
        
        // Test can't initialize with zero address
        vm.expectRevert(InvalidMasterAdmin.selector);
        bytes memory initData = abi.encodeCall(StudentProfile.initialize, (address(0)));
        new ERC1967Proxy(address(newImplementation), initData);
        
        // Test can't initialize twice (using existing proxy)
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        studentProfile.initialize(masterAdmin);
    }

    function test_RevertWhenUnauthorizedAttendanceUpdate() public {
        // Register student
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        
        // Try to update attendance from unauthorized account
        vm.prank(unauthorized);
        
        // The proper way to handle AccessControl errors
        bytes memory expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            TEACHER_ROLE
        );
        vm.expectRevert(expectedError);
        studentProfile.updateAttendance(student, true);
    }

    function test_RegisterStudent() public {
        vm.startPrank(school);
        
        vm.expectEmit(true, true, false, true);
        emit StudentRegistered(student, "John Doe", school, 0);
        
        studentProfile.registerStudent(student, "John Doe");
        
        (
            string memory name,
            uint256 currentTerm,
            uint256 programId,
            bool isActive,
            uint256 registrationDate
        ) = studentProfile.getStudentDetails(student);
        
        assertEq(name, "John Doe");
        assertEq(currentTerm, 1);
        assertEq(programId, 0);
        assertTrue(isActive);
        assertGt(registrationDate, 0);
        
        vm.stopPrank();
    }

    function test_UpdateAttendance() public {
        // Register student first
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Set program for student
        vm.stopPrank();
        schoolManagement.setStudentProgram(student, 1);
        
        // Move time forward
        vm.warp(block.timestamp + 21 hours);
        
        vm.startPrank(school);
        
        vm.expectEmit(true, false, false, true);
        emit AttendanceUpdated(student, 1, 1);
        
        studentProfile.updateAttendance(student, true);
        
        // Verify attendance
        (uint256 termAttendance, uint256 totalAttendance) = studentProfile.getStudentAttendance(student, 1);
        assertEq(termAttendance, 1);
        assertEq(totalAttendance, 1);
        
        vm.stopPrank();
    }

    function test_ConsecutiveAttendanceTracking() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        schoolManagement.setStudentProgram(student, 1);

        vm.startPrank(school);
        
        // Record 3 consecutive days
        for(uint i = 0; i < 3; i++) {
            // Move forward 21 hours before each attendance update
            vm.warp(block.timestamp + 21 hours);
            studentProfile.updateAttendance(student, true);
        }

        // Record an absence after another 21 hours
        vm.warp(block.timestamp + 21 hours);
        studentProfile.updateAttendance(student, false);

        // Verify attendance
        (uint256 termAttendance, uint256 totalAttendance) = studentProfile.getStudentAttendance(student, 1);
        assertEq(termAttendance, 3);
        assertEq(totalAttendance, 3);

        vm.stopPrank();
    }

    function test_UpdateReputation() public {
        // Register student
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(student, 100, 90, 85);
        
        studentProfile.updateReputation(student, 100, 90, 85);
        
        // Verify reputation
        StudentProfile.Reputation memory rep = studentProfile.getStudentReputation(student);
        assertEq(rep.attendancePoints, 100);
        assertEq(rep.behaviorPoints, 90);
        assertEq(rep.academicPoints, 85);
        
        vm.stopPrank();
    }

    function test_TransferStudent() public {
        // Setup new school
        address newSchool = makeAddr("newSchool");
        vm.startPrank(masterAdmin);
        studentProfile.activateSchool(newSchool);
        studentProfile.grantRole(TEACHER_ROLE, newSchool);
        vm.stopPrank();
        
        // Register student
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        
        // Transfer student
        vm.prank(masterAdmin);
        studentProfile.transferStudent(student, newSchool);
        
        // Verify transfer
        (,,, address currentSchool) = studentProfile.getStudentStatus(student);
        assertEq(currentSchool, newSchool);
    }

    function test_CompleteStudentTerm() public {
        // Register student
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        studentProfile.completeStudentTerm(student);
        
        // Verify term completion
        (,, uint256 currentTerm,) = studentProfile.getStudentStatus(student);
        assertEq(currentTerm, 2);
        assertTrue(studentProfile.completedTerms(student, 1));
        
        vm.stopPrank();
    }

    function test_PauseContract() public {
        // Pause contract
        vm.prank(masterAdmin);
        studentProfile.pause();
        
        // Try to register student while paused
        vm.startPrank(school);
        
        // Expect the EnforcedPause error from OpenZeppelin's Pausable contract
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        studentProfile.registerStudent(student, "John Doe");
        
        vm.stopPrank();
    }

    function test_UnpauseContract() public {
        // First pause the contract
        vm.prank(masterAdmin);
        studentProfile.pause();
        
        // Then unpause it
        vm.prank(masterAdmin);
        studentProfile.unpause();
        
        // Verify we can perform operations after unpausing
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Verify the registration worked
        (string memory name,,,,) = studentProfile.getStudentDetails(student);
        assertEq(name, "John Doe");
        
        vm.stopPrank();
    }

    function test_RevertWhenInvalidAttendanceUpdate() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Set initial timestamp
        vm.warp(block.timestamp + 21 hours);
        
        // First attendance update should succeed
        studentProfile.updateAttendance(student, true);
        
        // Try to update attendance again without enough time passing
        vm.expectRevert(TooSoonForAttendance.selector);
        studentProfile.updateAttendance(student, true);
        
        vm.stopPrank();
    }

    function test_RevertWhenTransferringNonExistentStudent() public {
        address newSchool = makeAddr("newSchool");
        vm.startPrank(masterAdmin);
        studentProfile.activateSchool(newSchool);
        
        vm.expectRevert(StudentNotActive.selector);
        studentProfile.transferStudent(student, newSchool);
        
        vm.stopPrank();
    }

    function test_MultipleTermCompletion() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Complete multiple terms
        for(uint i = 1; i <= 3; i++) {
            studentProfile.completeStudentTerm(student);
            (,, uint256 currentTerm,) = studentProfile.getStudentStatus(student);
            assertEq(currentTerm, i + 1);
            assertTrue(studentProfile.completedTerms(student, i));
        }
        
        vm.stopPrank();
    }

    function testFuzz_UpdateAttendance(uint256 timeJump) public {
        vm.assume(timeJump > 21 hours && timeJump < 365 days);
        
        // Register student
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Set program
        vm.stopPrank();
        schoolManagement.setStudentProgram(student, 1);
        
        // Warp time
        vm.warp(block.timestamp + timeJump);
        
        // Update attendance
        vm.startPrank(school);
        studentProfile.updateAttendance(student, true);
        
        // Verify
        (uint256 termAttendance,) = studentProfile.getStudentAttendance(student, 1);
        assertEq(termAttendance, 1);
        
        vm.stopPrank();
    }


    function test_SchoolManagementInteractions() public {
        // First clear the existing school management
        // This requires creating a new implementation and proxy
        StudentProfile newImplementation = new StudentProfile();
        bytes memory initData = abi.encodeCall(StudentProfile.initialize, (masterAdmin));
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        StudentProfile newStudentProfile = StudentProfile(address(newProxy));
        
        // Test setting school management
        vm.startPrank(masterAdmin);
        address newSchoolManagement = address(new MockSchoolManagement());
        newStudentProfile.setSchoolManagement(newSchoolManagement);
        assertEq(address(newStudentProfile.schoolManagement()), newSchoolManagement);
        
        // Test trying to set it again (should revert)
        vm.expectRevert(AlreadySet.selector);
        newStudentProfile.setSchoolManagement(newSchoolManagement);
        vm.stopPrank();
    }

    function test_StudentProgramValidation() public {
        // Register student        
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        
        // Update the student's program ID in the StudentProfile contract
        // This requires creating a special function to set program ID directly
        vm.prank(school);
        studentProfile.updateStudentProgram(student, 1);  // New function needed
        
        // Set up program in school management
        schoolManagement.setProgramActive(1, true);
        schoolManagement.setStudentProgram(student, 1);
        
        // Test program validation
        bool isValid = studentProfile.validateProgramEnrollment(student, 1);
        assertTrue(isValid);
        
        // Test invalid program
        schoolManagement.setProgramActive(1, false);
        vm.expectRevert(ProgramNotActive.selector);
        studentProfile.validateProgramEnrollment(student, 1);
    }

    // Add helper to properly set up a new student profile instance
    function _deployNewStudentProfile() internal returns (StudentProfile) {
        StudentProfile newImplementation = new StudentProfile();
        bytes memory initData = abi.encodeCall(StudentProfile.initialize, (masterAdmin));
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImplementation), initData);
        return StudentProfile(address(newProxy));
    }

    function test_SchoolActivationAndDeactivation() public {
        address newSchool = makeAddr("newSchool");
        
        vm.startPrank(masterAdmin);
        // Test activation
        studentProfile.activateSchool(newSchool);
        assertTrue(studentProfile.isActiveSchool(newSchool));
        assertTrue(studentProfile.hasRole(studentProfile.SCHOOL_ROLE(), newSchool));
        
        // Test deactivation
        studentProfile.deactivateSchool(newSchool);
        assertFalse(studentProfile.isActiveSchool(newSchool));
        assertFalse(studentProfile.hasRole(studentProfile.SCHOOL_ROLE(), newSchool));
        vm.stopPrank();
    }

    function test_StudentDeactivation() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Test deactivation
        studentProfile.deactivateStudent(student);
        (,bool isActive,,) = studentProfile.getStudentStatus(student);
        assertFalse(isActive);
        
        // Test that deactivated student can't have attendance updated
        vm.warp(block.timestamp + 21 hours);
        vm.expectRevert(StudentNotActive.selector);
        studentProfile.updateAttendance(student, true);
        vm.stopPrank();
    }

    function test_ReputationPenalties() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Apply penalty
        studentProfile.applyReputationPenalty(student, 50, "Misconduct");
        
        // Verify penalty was applied
        StudentProfile.Reputation memory rep = studentProfile.getStudentReputation(student);
        assertEq(rep.behaviorPoints, 50); // Started at 100, reduced by 50
        
        // Test penalty too high
        vm.expectRevert(PenaltyTooHigh.selector);
        studentProfile.applyReputationPenalty(student, 51, "Too high penalty"); // Would reduce below 0
        
        vm.stopPrank();
    }

    function test_StudentViewFunctions() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Test getStudentProgram
        uint256 programId = studentProfile.getStudentProgram(student);
        assertEq(programId, 0);
        
        // Test isStudentOfSchool
        assertTrue(studentProfile.isStudentOfSchool(student, school));
        assertFalse(studentProfile.isStudentOfSchool(student, address(0x123)));
        
        // Test getStudentDetails
        (
            string memory name,
            uint256 currentTerm,
            uint256 progId,
            bool isActive,
            uint256 registrationDate
        ) = studentProfile.getStudentDetails(student);
        
        assertEq(name, "John Doe");
        assertEq(currentTerm, 1);
        assertEq(progId, 0);
        assertTrue(isActive);
        assertGt(registrationDate, 0);
        
        vm.stopPrank();
    }

    function test_UnauthorizedAccess() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        
        // Test unauthorized attempts
        vm.startPrank(unauthorized);
        
        vm.expectRevert(Unauthorized.selector);
        studentProfile.getStudentReputation(student);
        
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                unauthorized,
                TEACHER_ROLE
            )
        );
        studentProfile.updateReputation(student, 100, 100, 100);
        
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                unauthorized,
                MASTER_ADMIN_ROLE
            )
        );
        studentProfile.transferStudent(student, address(0x123));
        
        vm.stopPrank();
    }

    function test_StudentSchoolCounts() public {
        // Test school student count tracking
        vm.startPrank(school);
        assertEq(studentProfile.schoolStudentCount(school), 0);
        
        // Register students
        studentProfile.registerStudent(student, "John Doe");
        assertEq(studentProfile.schoolStudentCount(school), 1);
        
        address student2 = makeAddr("student2");
        studentProfile.registerStudent(student2, "Jane Doe");
        assertEq(studentProfile.schoolStudentCount(school), 2);
        vm.stopPrank();
        
        // Test count updates on transfer
        address newSchool = makeAddr("newSchool");
        vm.startPrank(masterAdmin);
        studentProfile.activateSchool(newSchool);
        studentProfile.transferStudent(student, newSchool);
        vm.stopPrank();
        
        assertEq(studentProfile.schoolStudentCount(school), 1);
        assertEq(studentProfile.schoolStudentCount(newSchool), 1);
    }

    function testFuzz_ReputationUpdates(
        uint256 attendance,
        uint256 behavior,
        uint256 academic
    ) public {
        // Bound the values to reasonable ranges
        attendance = bound(attendance, 0, 100);
        behavior = bound(behavior, 0, 100);
        academic = bound(academic, 0, 100);
        
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        studentProfile.updateReputation(student, attendance, behavior, academic);
        
        StudentProfile.Reputation memory rep = studentProfile.getStudentReputation(student);
        assertEq(rep.attendancePoints, attendance);
        assertEq(rep.behaviorPoints, behavior);
        assertEq(rep.academicPoints, academic);
        vm.stopPrank();
    }

    function test_ReputationPointsCap() public {
        // Setup
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Try to set points beyond reasonable limits
        studentProfile.updateReputation(student, 1000, 1000, 1000);
        
        // Verify points are updated
        StudentProfile.Reputation memory rep = studentProfile.getStudentReputation(student);
        assertEq(rep.attendancePoints, 1000);
        assertEq(rep.behaviorPoints, 1000);
        assertEq(rep.academicPoints, 1000);
        
        vm.stopPrank();
    }

    function test_ConsecutiveDeactivationAndReactivation() public {
        // Setup
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // First deactivation
        studentProfile.deactivateStudent(student);
        (,bool isActive,,) = studentProfile.getStudentStatus(student);
        assertFalse(isActive);
        
        // Try operations while deactivated
        vm.warp(block.timestamp + 21 hours);
        vm.expectRevert(StudentNotActive.selector);
        studentProfile.updateAttendance(student, true);
        
        // Note: Currently there's no reactivation function in the contract
        // This would be a good feature to add
        vm.stopPrank();
    }

    function test_MultipleSchoolTransfers() public {
        // Setup initial state
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        
        // Create multiple schools
        address[] memory schools = new address[](3);
        schools[0] = makeAddr("school1");
        schools[1] = makeAddr("school2");
        schools[2] = makeAddr("school3");
        
        // Activate all schools
        vm.startPrank(masterAdmin);
        for(uint i = 0; i < schools.length; i++) {
            studentProfile.activateSchool(schools[i]);
        }
        
        // Perform multiple transfers
        for(uint i = 0; i < schools.length; i++) {
            studentProfile.transferStudent(student, schools[i]);
            (,,, address currentSchool) = studentProfile.getStudentStatus(student);
            assertEq(currentSchool, schools[i]);
        }
        vm.stopPrank();
    }

    function test_ConcurrentStudentOperations() public {
        // Setup
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Update multiple aspects concurrently
        vm.warp(block.timestamp + 21 hours);
        studentProfile.updateAttendance(student, true);
        studentProfile.updateReputation(student, 90, 85, 95);
        studentProfile.completeStudentTerm(student);
        
        // Verify all updates were applied correctly
        (,, uint256 currentTerm,) = studentProfile.getStudentStatus(student);
        assertEq(currentTerm, 2);
        
        StudentProfile.Reputation memory rep = studentProfile.getStudentReputation(student);
        assertEq(rep.attendancePoints, 90);
        assertEq(rep.behaviorPoints, 85);
        assertEq(rep.academicPoints, 95);
        
        (uint256 termAttendance,) = studentProfile.getStudentAttendance(student, 1);
        assertEq(termAttendance, 1);
        
        vm.stopPrank();
    }

    function test_SchoolStudentCountEdgeCases() public {
        // Test maximum students per school scenario
        uint256 maxStudents = 5;
        address[] memory students = new address[](maxStudents);
        
        vm.startPrank(school);
        for(uint i = 0; i < maxStudents; i++) {
            students[i] = makeAddr(string.concat("student", Strings.toString(i)));
            studentProfile.registerStudent(students[i], string.concat("Student ", Strings.toString(i)));
            assertEq(studentProfile.schoolStudentCount(school), i + 1);
        }
        vm.stopPrank();
        
        // Test transfer impact on counts
        address newSchool = makeAddr("newSchool");
        vm.startPrank(masterAdmin);
        studentProfile.activateSchool(newSchool);
        
        // Transfer half the students
        for(uint i = 0; i < maxStudents / 2; i++) {
            studentProfile.transferStudent(students[i], newSchool);
        }
        
        assertEq(studentProfile.schoolStudentCount(school), maxStudents - (maxStudents / 2));
        assertEq(studentProfile.schoolStudentCount(newSchool), maxStudents / 2);
        vm.stopPrank();
    }

    function test_AttendanceCalculationPrecision() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        vm.stopPrank();
        
        schoolManagement.setStudentProgram(student, 1);
        schoolManagement.setAttendanceRequirement(1, 80);
        
        vm.startPrank(school);
        
        // Record specific attendance pattern
        for(uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 21 hours);
            // Alternate between present and absent
            studentProfile.updateAttendance(student, i % 2 == 0);
        }
        
        // Check final attendance records
        (uint256 termAttendance, uint256 totalAttendance) = studentProfile.getStudentAttendance(student, 1);
        assertEq(termAttendance, 5); // Should have 5 attended classes in term 1
        assertEq(totalAttendance, 5); // Should have 5 total attended classes
        
        vm.stopPrank();
    }

    function test_RoleManagementComplex() public {
        // Test complex role assignment scenarios
        address newAdmin = makeAddr("newAdmin");
        address newTeacher = makeAddr("newTeacher");
        
        vm.startPrank(masterAdmin);
        
        // Grant multiple roles to same address
        studentProfile.grantRole(TEACHER_ROLE, newAdmin);
        studentProfile.grantRole(SCHOOL_ROLE, newAdmin);
        
        assertTrue(studentProfile.hasRole(TEACHER_ROLE, newAdmin));
        assertTrue(studentProfile.hasRole(SCHOOL_ROLE, newAdmin));
        
        // Test role hierarchy
        studentProfile.grantRole(TEACHER_ROLE, newTeacher);
        
        // Verify teacher can't grant roles
        vm.stopPrank();
        vm.startPrank(newTeacher);
        
        bytes memory expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            newTeacher,
            studentProfile.DEFAULT_ADMIN_ROLE()
        );
        vm.expectRevert(expectedError);
        studentProfile.grantRole(TEACHER_ROLE, makeAddr("anotherTeacher"));
        
        vm.stopPrank();
    }

    function test_ProgramEnrollmentComplexScenarios() public {
        // Setup
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Test program enrollment validation
        schoolManagement.setProgramActive(1, true);
        studentProfile.updateStudentProgram(student, 1);
        assertTrue(studentProfile.validateProgramEnrollment(student, 1));
        
        // Test program deactivation impact
        vm.stopPrank();
        schoolManagement.setProgramActive(1, false);
        
        vm.expectRevert(ProgramNotActive.selector);
        studentProfile.validateProgramEnrollment(student, 1);
        
        // Test program switch
        schoolManagement.setProgramActive(2, true);
        vm.prank(school);
        studentProfile.updateStudentProgram(student, 2);
        
        assertTrue(studentProfile.validateProgramEnrollment(student, 2));
    }

    function testFuzz_StudentNameValidation(string memory studentName) public {
        vm.assume(bytes(studentName).length > 0 && bytes(studentName).length <= 100);
        
        vm.startPrank(school);
        studentProfile.registerStudent(student, studentName);
        
        (string memory storedName,,,,) = studentProfile.getStudentDetails(student);
        assertEq(storedName, studentName);
        
        vm.stopPrank();
    }









    // Event emission tests for complex operations
    function test_ComplexEventEmissions() public {
        vm.startPrank(school);
        
        // Test multiple events from student registration
        vm.expectEmit(true, true, false, true);
        emit StudentRegistered(student, "John Doe", school, 0);
        
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(student, 0, 100, 0);
        
        studentProfile.registerStudent(student, "John Doe");
        
        // Test events from attendance and reputation update
        vm.warp(block.timestamp + 21 hours);
        schoolManagement.setStudentProgram(student, 1);
        
        vm.expectEmit(true, false, false, true);
        emit AttendanceUpdated(student, 1, 1);
        
        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(student, 20, 100, 0);
        
        studentProfile.updateAttendance(student, true);
        
        vm.stopPrank();
    }

    // Gas optimization tests
    function test_GasOptimization() public {
        vm.startPrank(school);
        
        // Measure gas for student registration
        uint256 gasBefore = gasleft();
        studentProfile.registerStudent(student, "John Doe");
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(gasUsed < 300000, "Student registration gas too high");
        
        // Measure gas for attendance update
        vm.warp(block.timestamp + 21 hours);
        schoolManagement.setStudentProgram(student, 1);
        
        gasBefore = gasleft();
        studentProfile.updateAttendance(student, true);
        gasUsed = gasBefore - gasleft();
        assertTrue(gasUsed < 200000, "Attendance update gas too high");
        
        vm.stopPrank();
    }

    // Complex attendance patterns
    function test_ComplexAttendancePatterns() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        schoolManagement.setStudentProgram(student, 1);
        
        // Test week-long attendance pattern
        uint256[7] memory attendancePattern = [
            uint256(1), // Monday: Present
            uint256(0), // Tuesday: Absent
            uint256(1), // Wednesday: Present
            uint256(1), // Thursday: Present
            uint256(0), // Friday: Absent
            uint256(1), // Saturday: Present
            uint256(1)  // Sunday: Present
        ];
        
        for(uint i = 0; i < attendancePattern.length; i++) {
            vm.warp(block.timestamp + 21 hours);
            studentProfile.updateAttendance(student, attendancePattern[i] == 1);
        }
        
        // Verify final attendance
        (uint256 termAttendance, uint256 totalAttendance) = studentProfile.getStudentAttendance(student, 1);
        assertEq(termAttendance, 5); // 5 days present
        assertEq(totalAttendance, 5);
        
        vm.stopPrank();
    }

    // Student term completion edge cases
    function test_TermCompletionEdgeCases() public {
        vm.startPrank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Complete multiple terms in sequence
        for(uint256 i = 1; i <= 5; i++) {
            studentProfile.completeStudentTerm(student);
            (,, uint256 currentTerm,) = studentProfile.getStudentStatus(student);
            assertEq(currentTerm, i + 1);
            assertTrue(studentProfile.completedTerms(student, i));
        }
        
        // Verify student status after multiple terms
        (,, uint256 finalTerm,) = studentProfile.getStudentStatus(student);
        assertEq(finalTerm, 6);
        
        vm.stopPrank();
    }

    // Pause/Unpause interaction tests
    function test_PauseUnpauseInteractions() public {
        // Register student before pausing
        vm.prank(school);
        studentProfile.registerStudent(student, "John Doe");
        
        // Pause contract
        vm.prank(masterAdmin);
        studentProfile.pause();
        
        vm.startPrank(school);
        
        // Test all operations while paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        studentProfile.registerStudent(makeAddr("newStudent"), "Jane Doe");
        
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        studentProfile.updateAttendance(student, true);
        
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        studentProfile.updateReputation(student, 90, 90, 90);
        
        // Unpause and verify operations resume
        vm.stopPrank();
        vm.prank(masterAdmin);
        studentProfile.unpause();
        
        vm.startPrank(school);
        
        // Should work after unpause
        address newStudent = makeAddr("newStudent");
        studentProfile.registerStudent(newStudent, "Jane Doe");
        (string memory name,,,,) = studentProfile.getStudentDetails(newStudent);
        assertEq(name, "Jane Doe");
        
        vm.stopPrank();
    }

    // Comprehensive authorization tests
    function test_ComprehensiveAuthorization() public {
        // Setup multiple roles
        address admin2 = makeAddr("admin2");
        address teacher2 = makeAddr("teacher2");
        address unauthorized = makeAddr("unauthorized");
        
        vm.startPrank(masterAdmin);
        studentProfile.grantRole(TEACHER_ROLE, teacher2);
        studentProfile.grantRole(studentProfile.DEFAULT_ADMIN_ROLE(), admin2);
        vm.stopPrank();
        
        // Test unauthorized access to admin functions
        vm.startPrank(unauthorized);
        
        bytes memory expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            MASTER_ADMIN_ROLE
        );
        vm.expectRevert(expectedError);
        studentProfile.pause();
        
        expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorized,
            TEACHER_ROLE
        );
        vm.expectRevert(expectedError);
        studentProfile.registerStudent(student, "John Doe");
        
        vm.stopPrank();
        
        // Test teacher permissions
        vm.startPrank(teacher2);
        
        vm.expectRevert(SchoolNotActive.selector);
        studentProfile.registerStudent(student, "John Doe");
        
        vm.stopPrank();
        
        // Test admin2 permissions
        vm.startPrank(admin2);
        
        expectedError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            admin2,
            MASTER_ADMIN_ROLE
        );
        vm.expectRevert(expectedError);
        studentProfile.setSchoolManagement(address(0x123));
        
        vm.stopPrank();
    }

    function test_NestedRoleOperations() public {
        address newSchool = makeAddr("newSchool");
        address newTeacher = makeAddr("newTeacher");
        
        vm.startPrank(masterAdmin);
        
        // Activate school and grant necessary roles
        studentProfile.activateSchool(newSchool);
        studentProfile.grantRole(TEACHER_ROLE, newSchool); // Grant TEACHER_ROLE to school
        studentProfile.grantRole(TEACHER_ROLE, newTeacher);
        
        // Verify school can operate
        vm.stopPrank();
        vm.startPrank(newSchool);
        
        studentProfile.registerStudent(student, "John Doe");
        
        // Verify teacher can operate under school context
        vm.stopPrank();
        vm.startPrank(newTeacher);
        
        // Register a new student
        vm.expectRevert(SchoolNotActive.selector); // Teacher needs to be associated with an active school
        studentProfile.registerStudent(makeAddr("newStudent"), "Jane Doe");
        
        vm.stopPrank();
    }

    function test_StudentStateTransitions() public {
        vm.startPrank(masterAdmin);
        // Ensure school has TEACHER_ROLE
        studentProfile.grantRole(TEACHER_ROLE, school);
        vm.stopPrank();
        
        vm.startPrank(school);
        
        // Register -> Update -> Deactivate -> Transfer -> Reactivate flow
        studentProfile.registerStudent(student, "John Doe");
        
        vm.warp(block.timestamp + 21 hours);
        schoolManagement.setStudentProgram(student, 1);
        studentProfile.updateAttendance(student, true);
        
        studentProfile.deactivateStudent(student);
        
        vm.stopPrank();
        
        // Transfer to new school
        address newSchool = makeAddr("newSchool");
        vm.startPrank(masterAdmin);
        studentProfile.activateSchool(newSchool);
        studentProfile.grantRole(SCHOOL_ROLE, newSchool);
        studentProfile.grantRole(TEACHER_ROLE, newSchool);
        
        // Student must be active for transfer
        vm.stopPrank();
        
        // Verify final state
        (bool isRegistered, bool isActive, uint256 currentTerm, address studentSchool) = 
            studentProfile.getStudentStatus(student);
        
        assertTrue(isRegistered);
        assertFalse(isActive);  // Should be deactivated
        assertEq(currentTerm, 1);
        assertEq(studentSchool, school); // Should still be at original school since transfer wasn't possible
        
        vm.stopPrank();
    }


}