// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TuitionFees.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


error NotEnrolledInSchool();
error InsufficientPayment();
error LateFeePercentageTooHigh();
error NoBalanceToWithdraw();

// Mock StudentProfile contract
contract MockStudentProfile {
    mapping(address => mapping(address => bool)) public studentSchoolEnrollment;
    mapping(address => uint256) public studentPrograms;

    function setStudentSchoolStatus(address student, address school, bool status) external {
        studentSchoolEnrollment[student][school] = status;
    }

    function setStudentProgram(address student, uint256 programId) external {
        studentPrograms[student] = programId;
    }

    function isStudentOfSchool(address student, address school) external view returns (bool) {
        return studentSchoolEnrollment[student][school];
    }

    function getStudentProgram(address student) external view returns (uint256) {
        return studentPrograms[student];
    }
}

contract TuitionSystemTest is Test {
    TuitionSystem public implementation;
    TuitionSystem public tuitionSystem;
    MockStudentProfile public studentProfile;
    
    address public masterAdmin;
    address public schoolAdmin;
    address public student;
    address public secondStudent;
    address public secondSchool;
    
    uint256 public constant PROGRAM_ID = 1;
    uint256 public constant SECOND_PROGRAM_ID = 2;
    uint256 public constant TERM = 1;
    uint256 public constant REGISTRATION_FEE = 1 ether;
    uint256 public constant TERM_FEE = 2 ether;
    uint256 public constant GRADUATION_FEE = 0.5 ether;
    uint256 public constant LATE_FEE_PERCENTAGE = 10;

    event TuitionPaid(
        address indexed student,
        address indexed school,
        uint256 term,
        uint256 programId,
        uint256 amount
    );

    event PaymentRecorded(
        address indexed student,
        uint256 term,
        uint256 amount
    );

    function setUp() public {
        masterAdmin = makeAddr("masterAdmin");
        schoolAdmin = makeAddr("schoolAdmin");
        secondSchool = makeAddr("secondSchool");
        student = makeAddr("student");
        secondStudent = makeAddr("secondStudent");
        
        studentProfile = new MockStudentProfile();
        
        implementation = new TuitionSystem();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                TuitionSystem.initialize.selector,
                address(studentProfile),
                masterAdmin
            )
        );
        tuitionSystem = TuitionSystem(address(proxy));
        
        vm.startPrank(masterAdmin);
        tuitionSystem.grantRole(tuitionSystem.ADMIN_ROLE(), schoolAdmin);
        tuitionSystem.grantRole(tuitionSystem.SCHOOL_ROLE(), schoolAdmin);
        tuitionSystem.grantRole(tuitionSystem.ADMIN_ROLE(), secondSchool);
        tuitionSystem.grantRole(tuitionSystem.SCHOOL_ROLE(), secondSchool);
        vm.stopPrank();
        
        studentProfile.setStudentSchoolStatus(student, schoolAdmin, true);
        studentProfile.setStudentProgram(student, PROGRAM_ID);
        studentProfile.setStudentSchoolStatus(secondStudent, secondSchool, true);
        studentProfile.setStudentProgram(secondStudent, SECOND_PROGRAM_ID);
        
        vm.startPrank(schoolAdmin);
        tuitionSystem.setProgramFees(
            PROGRAM_ID,
            REGISTRATION_FEE,
            TERM_FEE,
            GRADUATION_FEE,
            LATE_FEE_PERCENTAGE
        );
        vm.stopPrank();
        
        vm.deal(student, 10 ether);
        vm.deal(secondStudent, 10 ether);
    }


    function test_RevertPayTuitionNotEnrolled() public {
        address nonStudent = makeAddr("nonStudent");
        vm.deal(nonStudent, TERM_FEE);
        
        vm.prank(nonStudent);
        vm.expectRevert(NotEnrolledInSchool.selector);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
    }

    function test_RevertPayTuitionInsufficientAmount() public {
        vm.prank(student);
        vm.expectRevert(InsufficientPayment.selector);
        tuitionSystem.payTuition{value: TERM_FEE - 0.1 ether}(schoolAdmin, TERM);
    }

    function testInitialization() public view {
        assertEq(address(tuitionSystem.studentProfile()), address(studentProfile));
        assertTrue(tuitionSystem.hasRole(tuitionSystem.MASTER_ADMIN_ROLE(), masterAdmin));
        assertTrue(tuitionSystem.hasRole(tuitionSystem.DEFAULT_ADMIN_ROLE(), masterAdmin));
    }

    function testSetProgramFees() public {
        vm.startPrank(schoolAdmin);
        tuitionSystem.setProgramFees(
            PROGRAM_ID,
            REGISTRATION_FEE,
            TERM_FEE,
            GRADUATION_FEE,
            LATE_FEE_PERCENTAGE
        );
        
        (
            uint256 regFee,
            uint256 termFee,
            uint256 gradFee,
            uint256 lateFeePerc,
            bool isActive
        ) = tuitionSystem.programFees(schoolAdmin, PROGRAM_ID);
        
        assertEq(regFee, REGISTRATION_FEE);
        assertEq(termFee, TERM_FEE);
        assertEq(gradFee, GRADUATION_FEE);
        assertEq(lateFeePerc, LATE_FEE_PERCENTAGE);
        assertTrue(isActive);
        vm.stopPrank();
    }

    function testPayTuition() public {
        vm.startPrank(student);
        
        vm.expectEmit(true, true, false, true);
        emit TuitionPaid(student, schoolAdmin, TERM, PROGRAM_ID, TERM_FEE);
        
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        
        (bool isPaid, uint256 dueDate) = tuitionSystem.checkTuitionStatus(
            schoolAdmin,
            student,
            TERM
        );
        
        assertTrue(isPaid);
        assertEq(dueDate, block.timestamp + 180 days);
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), TERM_FEE);
        vm.stopPrank();
    }

    function testPayTuitionWithLateFee() public {
        // First payment to set initial due date
        vm.startPrank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        vm.stopPrank();
        
        // Fast forward past due date
        vm.warp(block.timestamp + 181 days);
        
        // Calculate expected late fee
        uint256 lateFee = (TERM_FEE * LATE_FEE_PERCENTAGE) / 100;
        uint256 totalAmount = TERM_FEE + lateFee;
        
        // Pay tuition for next term
        vm.startPrank(student);
        tuitionSystem.payTuition{value: totalAmount}(schoolAdmin, TERM + 1);
        
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), TERM_FEE + totalAmount);
        vm.stopPrank();
    }

    function testWithdrawBalance() public {
        // First have student pay tuition
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        
        // Record initial balance
        uint256 initialBalance = schoolAdmin.balance;
        
        // Withdraw balance
        vm.prank(schoolAdmin);
        tuitionSystem.withdrawBalance();
        
        // Check balances
        assertEq(schoolAdmin.balance, initialBalance + TERM_FEE);
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), 0);
    }



    function testMultipleTermPayments() public {
        vm.startPrank(student);
        
        // Pay for first term
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, 1);
        
        // Pay for second term
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, 2);
        
        // Pay for third term
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, 3);
        
        // Verify all payments
        for (uint256 i = 1; i <= 3; i++) {
            (bool isPaid,) = tuitionSystem.checkTuitionStatus(schoolAdmin, student, i);
            assertTrue(isPaid);
        }
        
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), TERM_FEE * 3);
        vm.stopPrank();
    }

    function testMaxLateFeePercentage() public {
        vm.startPrank(schoolAdmin);
        
        // Try to set late fee percentage above 50%
        vm.expectRevert(LateFeePercentageTooHigh.selector);
        tuitionSystem.setProgramFees(
            PROGRAM_ID,
            REGISTRATION_FEE,
            TERM_FEE,
            GRADUATION_FEE,
            51 // 51% should fail
        );
        
        // Set maximum allowed late fee
        tuitionSystem.setProgramFees(
            PROGRAM_ID,
            REGISTRATION_FEE,
            TERM_FEE,
            GRADUATION_FEE,
            50 // 50% should succeed
        );
        vm.stopPrank();
    }

    function testMultipleSchoolsAndStudents() public {
        // Setup second school's program fees
        vm.startPrank(secondSchool);
        tuitionSystem.setProgramFees(
            SECOND_PROGRAM_ID,
            REGISTRATION_FEE * 2, // Different fee structure
            TERM_FEE * 2,
            GRADUATION_FEE * 2,
            LATE_FEE_PERCENTAGE
        );
        vm.stopPrank();
        
        // First student pays first school
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        
        // Second student pays second school
        vm.prank(secondStudent);
        tuitionSystem.payTuition{value: TERM_FEE * 2}(secondSchool, TERM);
        
        // Verify balances
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), TERM_FEE);
        assertEq(tuitionSystem.schoolBalance(secondSchool), TERM_FEE * 2);
    }

    function testRecordTuitionPayment() public {
        vm.startPrank(schoolAdmin);
        tuitionSystem.recordTuitionPayment(student, TERM);
        
        (bool isPaid, uint256 dueDate) = tuitionSystem.checkTuitionStatus(
            schoolAdmin,
            student,
            TERM
        );
        
        assertTrue(isPaid);
        assertEq(dueDate, block.timestamp + 180 days);
        vm.stopPrank();
    }

    // Additional test for role separation
    function testRoleSeparation() public {
        // Test that having SCHOOL_ROLE doesn't grant ADMIN_ROLE privileges
        address schoolOnly = makeAddr("schoolOnly");
        
        vm.startPrank(masterAdmin);
        tuitionSystem.grantRole(tuitionSystem.SCHOOL_ROLE(), schoolOnly);
        vm.stopPrank();
        
        assertTrue(tuitionSystem.hasRole(tuitionSystem.SCHOOL_ROLE(), schoolOnly));
        assertFalse(tuitionSystem.hasRole(tuitionSystem.ADMIN_ROLE(), schoolOnly));
        
        // School role should not be able to set program fees
        vm.startPrank(schoolOnly);
        vm.expectRevert();
        tuitionSystem.setProgramFees(
            PROGRAM_ID,
            REGISTRATION_FEE,
            TERM_FEE,
            GRADUATION_FEE,
            LATE_FEE_PERCENTAGE
        );
        vm.stopPrank();
    }

    function testComplexLateFeeScenario() public {
        // First term payment
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        
        // Fast forward just before due date
        vm.warp(block.timestamp + 179 days);
        
        // Second term payment (should not incur late fee)
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM + 1);
        
        // Fast forward past due date
        vm.warp(block.timestamp + 2 days);
        
        // Third term payment (should incur late fee)
        uint256 lateFee = (TERM_FEE * LATE_FEE_PERCENTAGE) / 100;
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE + lateFee}(schoolAdmin, TERM + 2);
        
        // Verify total balance includes all payments plus late fee
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), (TERM_FEE * 3) + lateFee);
    }

    function testPartialWithdrawals() public {
        // Student pays tuition
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        
        uint256 initialBalance = schoolAdmin.balance;
        
        // School admin withdraws balance
        vm.startPrank(schoolAdmin);
        tuitionSystem.withdrawBalance();
        
        // Verify withdrawal
        assertEq(schoolAdmin.balance, initialBalance + TERM_FEE);
        assertEq(tuitionSystem.schoolBalance(schoolAdmin), 0);
        
        // Try to withdraw again
        vm.expectRevert(NoBalanceToWithdraw.selector);
        tuitionSystem.withdrawBalance();
        vm.stopPrank();
    }

    function testPauseAndTransactionAttempts() public {
        vm.prank(masterAdmin);
        tuitionSystem.pause();
        
        // Try various operations while paused
        vm.startPrank(schoolAdmin);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tuitionSystem.setProgramFees(
            PROGRAM_ID,
            REGISTRATION_FEE,
            TERM_FEE,
            GRADUATION_FEE,
            LATE_FEE_PERCENTAGE
        );
        
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tuitionSystem.recordTuitionPayment(student, TERM);
        
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tuitionSystem.withdrawBalance();
        vm.stopPrank();
        
        vm.prank(student);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
        
        // Unpause and verify operations work again
        vm.prank(masterAdmin);
        tuitionSystem.unpause();
        
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
    }

    // function testAccessControlHierarchy() public {
    //     address newAdmin = makeAddr("newAdmin");
    //     address newSchool = makeAddr("newSchool");
        
    //     // Test MASTER_ADMIN_ROLE capabilities
    //     vm.startPrank(masterAdmin);
    //     tuitionSystem.grantRole(tuitionSystem.ADMIN_ROLE(), newAdmin);
    //     tuitionSystem.grantRole(tuitionSystem.SCHOOL_ROLE(), newSchool);
    //     vm.stopPrank();
        
    //     // Test that regular admin cannot grant roles
    //     vm.startPrank(schoolAdmin);
    //     vm.expectRevert();
    //     tuitionSystem.grantRole(tuitionSystem.ADMIN_ROLE(), newAdmin);
    //     vm.stopPrank();
        
    //     // Test that only MASTER_ADMIN can pause
    //     vm.prank(schoolAdmin);
    //     vm.expectRevert();
    //     tuitionSystem.pause();
        
    //     vm.prank(masterAdmin);
    //     tuitionSystem.pause();
    // }

    function testPause() public {
        vm.prank(masterAdmin);
        tuitionSystem.pause();
        
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
    }

    function testUnpause() public {
        vm.startPrank(masterAdmin);
        tuitionSystem.pause();
        tuitionSystem.unpause();
        vm.stopPrank();
        
        vm.prank(student);
        tuitionSystem.payTuition{value: TERM_FEE}(schoolAdmin, TERM);
    }
}