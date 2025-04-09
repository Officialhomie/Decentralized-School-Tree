// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@thirdweb-dev/contracts/node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "./SchoolManagementBase.sol";


/**
 * @title IProgramManagement
 * @dev Interface for program management functionality
 */
interface IProgramManagement {
    function isProgramActive(uint256 programId) external view returns (bool);
    function getProgramDetails(uint256 programId) external view returns (string memory name, uint256 termFee);
}

/**
 * @title IAttendanceTracking
 * @dev Interface for attendance tracking
 */
interface IAttendanceTracking {
    function hasMetAttendanceRequirement(address student, uint256 programId) external view returns (bool);
}

/**
 * @title ICertificateManagement
 * @dev Interface for certificate management
 */
interface ICertificateManagement {
    function mintCertificate(address student, uint256 batchId) external payable;
    function getCurrentCertificateTokenId() external view returns (uint256);
}

/**
 * @title CertificateManagement
 * @dev Manages certificate issuance as NFTs
 */
contract CertificateManagement is ERC721, SchoolManagementBase, ICertificateManagement {
    using Counters for Counters.Counter;
    
    // Custom errors
    error StudentNotRegistered();
    error ProgramInactive();
    error TuitionNotPaid();
    error InsufficientAttendance();
    error ManagementContractsNotSet();
    
    // Counter for certificate token IDs
    Counters.Counter private _certificateTokenIds;
    
    // Interface references
    IProgramManagement public programManagement;
    IAttendanceTracking public attendanceTracking;
    
    // Events
    event CertificateMinted(address indexed student, uint256 indexed tokenId);
    
    /**
     * @dev Constructor for ERC721 token
     */
    constructor() ERC721("SchoolCertificate", "CERT") {
        // Initialize ERC721 with token name and symbol
    }
    
    /**
     * @dev Initialize the certificate management contract
     * @param _revenueSystem Address of the revenue system
     * @param _studentProfile Address of the student profile
     * @param _tuitionSystem Address of the tuition system
     * @param _roleRegistry Address of the role registry
     * @param _masterAdmin Address of the master admin
     */
    function initialize(
        address _revenueSystem,
        address _studentProfile,
        address _tuitionSystem,
        address _roleRegistry,
        address _masterAdmin
    ) public override initializer {
        SchoolManagementBase.initialize(
            _revenueSystem,
            _studentProfile,
            _tuitionSystem,
            _roleRegistry,
            _masterAdmin
        );
    }
    
    /**
     * @dev Sets the program management and attendance tracking references
     */
    function setManagementContracts(
        address _programManagement,
        address _attendanceTracking
    ) external onlyRole(ADMIN_ROLE) {
        if (_programManagement == address(0) || _attendanceTracking == address(0))
            revert InvalidAddress();
        programManagement = IProgramManagement(_programManagement);
        attendanceTracking = IAttendanceTracking(_attendanceTracking);
    }
    
    /**
     * @dev Mints a certificate as an NFT for a student
     */
    function mintCertificate(address student, uint256 batchId) 
        external 
        payable 
        override
        onlyRole(TEACHER_ROLE) 
        notRecovered 
        subscriptionActive 
    {
        if (address(programManagement) == address(0) || address(attendanceTracking) == address(0))
            revert ManagementContractsNotSet();
            
        if (msg.value < revenueSystem.certificateFee()) 
            revert InsufficientPayment();
        if (!studentProfile.isStudentOfSchool(student, address(this))) 
            revert StudentNotRegistered();
        
        uint256 programId = studentProfile.getStudentProgram(student);
        if (!programManagement.isProgramActive(programId)) 
            revert ProgramInactive();
        
        // Check tuition status
        (bool isPaid,) = tuitionSystem.checkTuitionStatus(
            address(this), 
            student, 
            0  // Current term from StudentProfile would be used here
        );
        if (!isPaid) revert TuitionNotPaid();
        
        // Check if student meets attendance requirements
        if (!attendanceTracking.hasMetAttendanceRequirement(student, programId))
            revert InsufficientAttendance();
        
        revenueSystem.issueCertificate{value: msg.value}(student, batchId);
        
        _certificateTokenIds.increment();
        uint256 newTokenId = _certificateTokenIds.current();
        
        _mint(student, newTokenId);
        emit CertificateMinted(student, newTokenId);
    }
    
    /**
     * @dev Gets the current certificate token ID counter
     */
    function getCurrentCertificateTokenId() external view override returns (uint256) {
        return _certificateTokenIds.current();
    }
    
    /**
     * @dev Overrides supportsInterface for ERC721 compatibility
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}