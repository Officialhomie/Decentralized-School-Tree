# EducationChain Platform

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Solidity Version: ^0.8.20](https://img.shields.io/badge/Solidity-0.8.20-orange.svg)

A comprehensive blockchain-based platform for educational institutions to manage student enrollment, attendance tracking, program management, and certificate issuance with transparent financial accounting.

## Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Key Features](#key-features)
- [Smart Contracts](#smart-contracts)
- [Deployment Guide](#deployment-guide)
- [Frontend Integration](#frontend-integration)
- [Financial System](#financial-system)
- [Security Considerations](#security-considerations)
- [License](#license)

## Overview

EducationChain is a decentralized application (dApp) designed for educational institutions to leverage blockchain technology for transparent, efficient school management. The platform enables:

- Schools to create and manage educational programs
- Teachers to track student attendance and performance
- Students to pay tuition and receive verifiable credentials
- Administrators to oversee financial transactions and revenue distribution
- Certificate issuance as NFTs with verifiable on-chain proof

The platform implements a revenue-sharing model between the platform and participating schools, with customizable fee structures and comprehensive financial tracking.

## System Architecture

The platform follows a factory-proxy pattern with clear separation of concerns across multiple contracts:

```
                   ┌────────────────────┐
                   │SchoolManagementBase│
                   └────────────────────┘
                            ▲
                            │
           ┌────────────────┼────────────────┐
           │                │                │
┌──────────┴──────┐ ┌───────┴────────┐ ┌────┴───────────┐
│ProgramManagement│ │StudentManagement│ │AttendanceTracking│
└─────────────────┘ └────────────────┘ └────────────────┘
           │                │                │
           │                │                │
           └────────────────┼────────────────┘
                            │
                            ▼
                   ┌────────────────┐
                   │ RevenueSystem  │
                   └────────────────┘
                            ▲
                            │
           ┌────────────────┼────────────────┐
           │                │                │
┌──────────┴──────┐ ┌───────┴────────┐ ┌────┴───────────┐
│  TuitionSystem  │ │ StudentProfile │ │CertificateManagement│
└─────────────────┘ └────────────────┘ └────────────────┘
```

The platform employs:
- **Role-based access control** for ensuring proper permissions
- **Factory pattern** for efficient school instance deployment
- **Cross-contract communication** for integrated operations
- **Proxy pattern** for potential upgradability

## Key Features

### For Schools
- Create and manage educational programs with customizable parameters
- Register and track students through their academic journey
- Issue verifiable digital certificates as NFTs
- Collect and withdraw tuition payments with transparent accounting
- Monitor attendance and academic performance

### For Students
- Secure, immutable record of academic achievements
- Transparent tuition payment tracking
- Verifiable digital credentials as NFTs
- Reliable attendance and performance tracking

### For Platform Administrators
- Deploy and manage school instances
- Configure platform-wide parameters
- Implement revenue-sharing models
- Monitor and withdraw platform fees

## Smart Contracts

| Contract | Description |
|----------|-------------|
| `SchoolManagementBase.sol` | Base contract with shared functionality for all school management contracts |
| `SchoolManagementFactory.sol` | Factory contract for deploying new school instances |
| `StudentManagement.sol` | Manages student registration, enrollment, and progression |
| `ProgramManagement.sol` | Handles educational program creation and configuration |
| `AttendanceTracking.sol` | Tracks student attendance and performance metrics |
| `RoleManagement.sol` | Manages role-based permissions across the platform |
| `StudentProfile.sol` | Maintains student profiles, reputations, and relationships |
| `TuitionSystem.sol` | Processes and tracks tuition payments and fee structures |
| `RevenueSystem.sol` | Handles financial accounting, revenue sharing, and withdrawals |
| `CertificateManagement.sol` | Issues and verifies educational certificates as NFTs |

### Contract Inheritance Structure

```
AccessControl, Pausable, Initializable, ReentrancyGuard
        ↓
SchoolManagementBase
        ↓
┌───────┬───────┬───────┬───────┬───────┐
│       │       │       │       │       │
PM      SM      AT      RM      CM      ...
```

## Deployment Guide

### Prerequisites
- Node.js and npm installed
- Hardhat, Truffle, or Foundry development environment
- Ethereum wallet with sufficient ETH for deployment
- Environment configuration file (.env) with required keys

### Deployment Order

1. **Deploy Base/Implementation Contracts**
   - SchoolManagementBase.sol
   - Implementation versions of management contracts

2. **Deploy Core Service Contracts**
   - StudentProfile.sol
   - TuitionSystem.sol
   - RevenueSystem.sol

3. **Initialize Core Services**
   - Configure with appropriate addresses and parameters

4. **Deploy Factory Contract**
   - SchoolManagementFactory.sol

5. **Initialize Factory**
   - Link to implementation contracts and core services

6. **Deploy School Instances**
   - Use factory to create configured school contracts

### Sample Deployment Script

```javascript
// See detailed deployment script in deployment documentation
const { ethers } = require("hardhat");

async function main() {
  // Deploy implementations
  // Deploy core services
  // Initialize services
  // Deploy and initialize factory
  // Deploy first school instance
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
```

For detailed deployment instructions, refer to the [Deployment Documentation](./docs/DEPLOYMENT.md).

## Frontend Integration

The platform can be integrated with any web frontend using Web3 libraries:

### Key Libraries
- ethers.js or web3.js for blockchain interaction
- React, Angular, or Vue.js for UI components
- MetaMask or WalletConnect for wallet integration

### Integration Example

```javascript
// Connect to deployed contracts
const provider = new ethers.providers.Web3Provider(window.ethereum);
const signer = provider.getSigner();
const schoolContract = new ethers.Contract(SCHOOL_ADDRESS, SCHOOL_ABI, signer);

// Example: Register a student
async function registerStudent(address, name, programId) {
  try {
    const tx = await schoolContract.registerStudent(address, name, programId);
    await tx.wait();
    return { success: true, txHash: tx.hash };
  } catch (error) {
    console.error("Failed to register student:", error);
    return { success: false, error: error.message };
  }
}
```

## Financial System

The platform implements a comprehensive financial ecosystem:

### Revenue Streams
- **School Subscription Fees**: Regular payments from institutions to use the platform
- **Program Creation Fees**: One-time fees for creating new educational programs
- **Certificate Issuance Fees**: Payments for issuing certificates as NFTs
- **Tuition Payments**: Student payments processed with revenue sharing

### Revenue Sharing
- Platform receives a configurable percentage of tuition payments
- Schools receive the remainder of tuition payments
- All transactions are transparent and verifiable on-chain

### Withdrawal Mechanisms
- Schools can withdraw their share after a time-based cooldown
- Platform administrators can withdraw accumulated fees
- All withdrawals are tracked with emitted events

### Fee Customization
- Schools can have custom fee structures
- Fees can be updated by authorized administrators
- Late payment penalties can be configured per program

## Security Considerations

The contracts implement several security mechanisms:

### Access Controls
- Role-based permission system using OpenZeppelin's AccessControl
- Strict function access restrictions based on role
- Hierarchical administrative structure

### Rate Limiting
- Protection against transaction spam with cooldown periods
- Burst allowances for batch operations with overall rate limits

### Financial Safeguards
- Non-reentrant modifiers for financial functions
- Balance verification before withdrawals
- Time-based withdrawal restrictions
- Emergency pause functionality

### Upgradeability
- Factory-proxy pattern allows for potential upgrades
- Implementation contracts can be updated
- Storage layout must be preserved for safe upgrades

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

---

© 2025 EducationChain Platform