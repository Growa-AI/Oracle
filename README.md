

# Growa IoT Gateway Smart Contract

![Growa IoT Gateway](Cohort2024.jpg)

## Overview

The Growa IoT Gateway is a sophisticated smart contract developed for the Internet Computer Protocol (ICP), designed to revolutionize precision agriculture through advanced data management and device control. This system is part of Growa.ai's comprehensive solution for agricultural technology, integrating IoT devices, real-time data processing, and blockchain technology.

## Features

### User Management
- Hierarchical role-based access control system
- Multiple user roles (SUPER_ADMIN, SYSTEM_ADMIN, USER_ADMIN, etc.)
- User status management (PENDING, APPROVED, REJECTED, SUSPENDED)
- Department-based organization
- First registered user automatically becomes system admin

### Device Management
- Secure device registration and authentication
- Unique device hashing and key generation
- Department-based device organization
- Approval workflow for new devices
- Last usage tracking
- Support for multiple devices per owner

### Reading Management
- Structured data collection from IoT devices
- Custom reading format support
- Multi-parameter reading capability (type, value, unit)
- Historical data tracking
- Device-specific reading indexing

### Security Features
- Role-based access control
- Admin approval workflows
- Secure device authentication
- Hash-based device identification
- Protected reading submission

## Technical Specifications

### Dependencies
```motoko
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Float "mo:base/Float";
import HashMap "mo:base/HashMap";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";
```

### Core Data Types

#### ReadingData
```motoko
type ReadingData = {
    readingType : Text;
    readingValue : Float;
    readingUnit : Text;
};
```

#### User
```motoko
type User = {
    principal : Principal;
    name : Text;
    email : Text;
    role : Role;
    status : UserStatus;
    department : ?Text;
    created : Int;
    lastModified : Int;
};
```

#### Device
```motoko
type Device = {
    hash : Text;
    owner : Principal;
    name : Text;
    key : Text;
    department : ?Text;
    approved : Bool;
    created : Int;
    lastUsed : ?Int;
};
```

## Integration with Growa Ecosystem

The IoT Gateway smart contract is designed to work seamlessly with:

- **Growa Sense**: Compact, solar-powered control units for field operations
- **Growa Pilot**: Advanced evaluation kit for comprehensive management
- **GAIA**: Growa's proprietary AI model for agricultural data analysis

## Key Benefits

- Real-time data collection and analysis
- Automated device management
- Secure data storage and access
- Scalable architecture
- Integration with precision agriculture tools
- Support for multiple agricultural parameters
- Department-based organization

## Getting Started

### Prerequisites
- Internet Computer SDK (dfx)
- Node.js and npm
- Motoko base library

### Deployment
1. Clone the repository
2. Install dependencies
3. Configure the dfx.json
4. Deploy to Internet Computer:
```bash
dfx deploy
```

### Basic Usage

1. **Register First Admin**
```motoko
await iotGateway.registerUser("Admin Name", "admin@example.com", ?"IT");
```

2. **Register Device**
```motoko
await iotGateway.registerDevice("Device Name", ?"Field A");
```

3. **Submit Reading**
```motoko
await iotGateway.addReading(deviceHash, deviceKey, "type:temperature,value:25.5,unit:C");
```

## Support

For technical support and inquiries:
- Email: info@growa.ai
- Website: www.growa.ai

## License

Copyright © 2023 Growa.AI Ltd. - All rights reserved
