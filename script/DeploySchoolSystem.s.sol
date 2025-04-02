// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

// Import all contracts
import {SchoolManagementFactory} from "../src/SchoolManagementFactory.sol";
import {SchoolManagementBase} from "../src/SchoolManagementBase.sol";
import {StudentManagement} from "../src/StudentManagement.sol";
import {StudentProfile} from "../src/StudentProfile.sol";
import {TuitionSystem} from "../src/TuitionFees.sol";
import {RevenueSystem} from "../src/RevenueSystem.sol";
import {ProgramManagement} from "../src/ProgramManagement.sol";
import {AttendanceTracking} from "../src/AttendanceTracking.sol";
import {RoleManagement} from "../src/RoleManagement.sol";
import {CertificateManagement} from "../src/CertificateManagement.sol";

contract DeploySchoolSystem is Script {
    // Store deployed addresses as state variables to reduce stack usage
    address public baseImplAddress;
    address public studentProfileAddress;
    address public tuitionSystemAddress;
    address public revenueSystemAddress;
    address public factoryAddress;
    
    // Default configuration values
    uint256 constant defaultProgramFee = 0.1 ether;
    uint256 constant defaultSubscriptionFee = 0.5 ether;
    uint256 constant defaultCertificateFee = 0.05 ether;
    uint256 constant defaultRevenueShare = 10; // 10% platform fee
    uint256 constant subscriptionDuration = 365 days;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy implementation contracts
        deployImplementationContracts();
        
        // Step 2: Deploy system contracts
        deploySystemContracts();
        
        // Step 3: Initialize system contracts
        initializeSystemContracts(msg.sender);
        
        // Step 4: Setup and initialize factory
        setupFactory(msg.sender);
        
        // Step 5: Deploy a test school
        deployTestSchool();
        
        vm.stopBroadcast();
    }

    function deployImplementationContracts() internal {
        // Deploy implementation contracts
        SchoolManagementBase baseImpl = new SchoolManagementBase();
        baseImplAddress = address(baseImpl);
        
        // We don't need to store these addresses since they're not referenced later
        new StudentManagement();
        new ProgramManagement();
        new AttendanceTracking();
        new RoleManagement();
        new CertificateManagement();
        
        console.log("Implementation contracts deployed. Base impl:", baseImplAddress);
    }

    function deploySystemContracts() internal {
        // Deploy system contracts
        StudentProfile studentProfile = new StudentProfile();
        studentProfileAddress = address(studentProfile);
        
        TuitionSystem tuitionSystem = new TuitionSystem();
        tuitionSystemAddress = address(tuitionSystem);
        
        RevenueSystem revenueSystem = new RevenueSystem();
        revenueSystemAddress = address(revenueSystem);
        
        console.log("System contracts deployed:");
        console.log("- StudentProfile:", studentProfileAddress);
        console.log("- TuitionSystem:", tuitionSystemAddress);
        console.log("- RevenueSystem:", revenueSystemAddress);
    }

    function initializeSystemContracts(address masterAdmin) internal {
        // Initialize StudentProfile
        StudentProfile(studentProfileAddress).initialize(masterAdmin);
        
        // Initialize TuitionSystem
        TuitionSystem(tuitionSystemAddress).initialize(
            studentProfileAddress, 
            masterAdmin
        );
        
        // Store the RevenueSystem instance to avoid casting
        RevenueSystem revenue = RevenueSystem(payable(revenueSystemAddress));
        
        // Initialize RevenueSystem with placeholder for schoolManagement
        revenue.initialize(
            address(0x1), // Placeholder - will update after factory deployment
            tuitionSystemAddress,
            masterAdmin,
            defaultProgramFee,
            defaultSubscriptionFee,
            defaultCertificateFee,
            defaultRevenueShare
        );
        
        console.log("System contracts initialized");
    }

    function setupFactory(address masterAdmin) internal {
        // Deploy factory
        SchoolManagementFactory factory = new SchoolManagementFactory(baseImplAddress);
        factoryAddress = address(factory);
        
        // Configure factory
        SchoolManagementFactory.DeploymentConfig memory defaultConfig = 
            SchoolManagementFactory.DeploymentConfig({
                programFee: defaultProgramFee,
                subscriptionFee: defaultSubscriptionFee, 
                certificateFee: defaultCertificateFee,
                revenueShare: defaultRevenueShare,
                subscriptionDuration: subscriptionDuration
            });
        
        // Initialize factory
        factory.initialize(
            baseImplAddress, 
            revenueSystemAddress,
            studentProfileAddress,
            masterAdmin,
            defaultConfig
        );
        
        // Update revenueSystem with the factory address
        // Note: Make sure this function exists in your RevenueSystem contract
        RevenueSystem(payable(revenueSystemAddress)).updateSchoolManagementAddress(factoryAddress);
        
        console.log("Factory deployed and initialized:", factoryAddress);
    }

    function deployTestSchool() internal {
        address organizationAdmin = 0xDA6fDF1002bB0E2e5EDC45440C3975dbb54799A8;
        
        // Create school configuration
        SchoolManagementFactory.DeploymentConfig memory schoolConfig = 
            SchoolManagementFactory.DeploymentConfig({
                programFee: defaultProgramFee,
                subscriptionFee: defaultSubscriptionFee,
                certificateFee: defaultCertificateFee,
                revenueShare: defaultRevenueShare,
                subscriptionDuration: subscriptionDuration
            });
        
        // Deploy school contract using payable cast
        SchoolManagementFactory factory = SchoolManagementFactory(payable(factoryAddress));
        
        address schoolContract = factory.deploySchoolManagement{
            value: defaultSubscriptionFee
        }(
            organizationAdmin,
            schoolConfig
        );
        
        console.log("Test school deployed at:", schoolContract);
    }
}