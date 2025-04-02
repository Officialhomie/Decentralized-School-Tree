// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import "../src/interfaces/ISchoolManagement.sol";
// import "../src/RoleManagement.sol";
// import "../src/StudentManagement.sol";
// import "../src/ProgramManagement.sol";
// import "../src/AttendanceTracking.sol";
// import "../src/CertificateManagement.sol";

// contract ConfigureSchool is Script {
//     function run() external {
//         uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
//         vm.startBroadcast(adminPrivateKey);
        
//         // Address of the deployed school contract
//         address schoolAddress = 0x...; // Replace with the address from previous deployment
        
//         // Deploy the implementation contracts for the specific school
//         RoleManagement roleManagement = new RoleManagement();
//         StudentManagement studentManagement = new StudentManagement();
//         ProgramManagement programManagement = new ProgramManagement();
//         AttendanceTracking attendanceTracking = new AttendanceTracking();
//         CertificateManagement certificateManagement = new CertificateManagement();
        
//         // Initialize the implementations for the specific school
//         // Get references to existing contract addresses
//         address revenueSystemAddress = 0x...; // From previous deployment
//         address studentProfileAddress = 0x...; // From previous deployment
//         address tuitionSystemAddress = 0x...; // From previous deployment
//         address factoryAddress = 0x...; // From previous deployment
//         address masterAdminAddress = 0x...; // From previous deployment
//         address orgAdminAddress = msg.sender;
        
//         // Initialize each contract with the school's context
//         roleManagement.initialize(
//             revenueSystemAddress,
//             studentProfileAddress,
//             tuitionSystemAddress,
//             factoryAddress,
//             masterAdminAddress,
//             orgAdminAddress
//         );
        
//         studentManagement.initialize(
//             revenueSystemAddress,
//             studentProfileAddress,
//             tuitionSystemAddress,
//             factoryAddress,
//             masterAdminAddress,
//             orgAdminAddress
//         );
        
//         programManagement.initialize(
//             revenueSystemAddress,
//             studentProfileAddress,
//             tuitionSystemAddress,
//             factoryAddress,
//             masterAdminAddress,
//             orgAdminAddress
//         );
        
//         attendanceTracking.initialize(
//             revenueSystemAddress,
//             studentProfileAddress,
//             tuitionSystemAddress,
//             factoryAddress,
//             masterAdminAddress,
//             orgAdminAddress
//         );
        
//         certificateManagement.initialize(
//             revenueSystemAddress,
//             studentProfileAddress,
//             tuitionSystemAddress,
//             factoryAddress,
//             masterAdminAddress,
//             orgAdminAddress
//         );
        
//         // Set up the contract interconnections
//         studentManagement.setProgramManagement(address(programManagement));
//         attendanceTracking.setManagementContracts(address(studentManagement), address(programManagement));
//         certificateManagement.setManagementContracts(address(programManagement), address(attendanceTracking));
        
//         console.log("School contract successfully configured!");
        
//         vm.stopBroadcast();
//     }
// }