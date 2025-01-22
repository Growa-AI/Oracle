# ESP32-based Hydroponic Monitoring System with Internet Computer Integration

## System Overview

This project implements a comprehensive hydroponic monitoring system using an ESP32 microcontroller, integrating various sensors to monitor critical parameters of a hydroponic setup. The system communicates with the Internet Computer Protocol (ICP) blockchain, ensuring secure and decentralized data storage. What makes this system unique is its robust approach to data integrity, system reliability, and secure communication with the ICP network.

## Hardware Architecture

The system is built around an ESP32 microcontroller and incorporates several key sensors:

The SHT30 sensor handles environmental monitoring, providing accurate measurements of air temperature and relative humidity. This digital sensor communicates over I2C, offering high precision and excellent long-term stability, which is crucial for maintaining optimal growing conditions.

Water quality monitoring is handled by an ES2 sensor utilizing the SDI-12 protocol. This sensor measures both electrical conductivity (EC) and water temperature. The EC measurement is particularly important as it directly correlates with nutrient concentration in the hydroponic solution. The sensor's ability to simultaneously measure water temperature allows for temperature compensation of EC readings, ensuring accuracy across varying conditions.

pH monitoring is accomplished through a professional-grade pH sensor connected to a high-precision analog input (GPIO 36) on the ESP32. The system is designed to handle 0-10V input, providing industrial-standard pH measurements. The implementation includes multi-sample averaging and temperature compensation capabilities to ensure reliable readings.

An MCP23017 I2C port expander is integrated into the system to manage various control outputs and additional inputs if needed. This component adds flexibility to the system and allows for future expansion of control capabilities.

## Software Architecture

The software architecture is designed with reliability and fault tolerance as primary considerations. The system implements several key features:

### Identity Management

A sophisticated identity management system is implemented for secure communication with the ICP blockchain. The system generates and maintains an ED25519 key pair, stored securely in the ESP32's SPIFFS file system. This identity is used to sign all transactions with the ICP canister, ensuring data authenticity and preventing unauthorized access.

### Data Management and Storage

The system implements a robust data management strategy that includes local caching of sensor readings when network communication fails. Failed transmissions are stored in SPIFFS and automatically retried when connectivity is restored. This approach ensures no data is lost due to temporary network issues.

The storage system utilizes JSON formatting for data structure, making it easy to manage and parse both locally and on the blockchain. Each reading includes a timestamp, sensor identifier, and value, along with metadata for tracking retry attempts.

### Safety and Reliability Features

Multiple safety mechanisms are implemented to ensure reliable operation:

A hardware watchdog timer is configured to automatically reset the system if the main program becomes unresponsive. This is complemented by software-level checks that monitor various system components.

The system continuously monitors the health of all connected I2C devices, particularly the MCP23017, and will initiate a controlled restart if communication issues are detected.

WiFi connectivity is actively monitored with an automatic reconnection system that includes fallback mechanisms and controlled system restarts when necessary.

### Sensor Reading and Processing

Each sensor type has a dedicated reading routine that includes error checking and validation:

The SHT30 readings include verification of the communication success and validation of the received values.

The ES2 sensor implementation includes proper SDI-12 timing and command sequencing, with parsing of the multi-parameter response.

pH readings are averaged over multiple samples to reduce noise, with temperature compensation applied based on the current water temperature from the ES2 sensor.

### ICP Integration

The system communicates with an ICP canister through HTTP POST requests, with each request properly signed using the system's identity. The communication protocol includes:

- Candid argument encoding for proper ICP canister interaction
- Request signing using ED25519 signatures
- Automatic retry mechanism for failed transmissions
- Proper error handling and reporting

## Configuration and Setup

The system requires initial configuration of several parameters:

Network Configuration:
- WiFi credentials
- ICP canister ID
- NTP server for time synchronization
- Qatar timezone offset

Sensor Configuration:
- I2C addresses for SHT30 and MCP23017
- SDI-12 address for ES2 sensor
- pH sensor calibration values
- Reading intervals and timing parameters

Safety Parameters:
- Watchdog timeout values
- Maximum retry attempts
- Storage limits for cached readings

## Maintenance and Monitoring

The system provides comprehensive monitoring through the serial interface, logging all significant events and sensor readings. Regular maintenance tasks are automated, including:

- Periodic verification of sensor connections
- Automatic retry of failed transmissions
- System health monitoring and reporting
- Automatic handling of common error conditions

## Future Expansion

The system architecture allows for easy expansion through:

- Additional sensors via the I2C bus
- Extra control outputs through the MCP23017
- Enhanced data processing and analysis capabilities
- Integration with additional ICP canisters or other blockchain systems

## Troubleshooting

The system includes extensive error reporting and self-diagnostic capabilities. Common issues can be identified through the serial output, which provides detailed information about:

- Sensor communication errors
- Network connectivity issues
- ICP canister interaction problems
- System state and health indicators

Regular monitoring of these outputs allows for proactive maintenance and quick resolution of any issues that may arise.

## Technical Specifications

Operating Environment:
- Temperature Range: 0-50°C
- Humidity Range: 0-100% RH
- Input Voltage: 5V DC
- Power Consumption: <500mA typical

Measurement Ranges:
- pH: 0-14 (0.01 resolution)
- EC: 0-5000 µS/cm
- Temperature: 0-50°C (0.1°C resolution)
- Humidity: 0-100% RH (0.1% resolution)

Network Requirements:
- WiFi: 2.4GHz
- Internet: Stable connection required for ICP interaction
- Bandwidth: Minimal (<1MB/hour typical)

This system represents a comprehensive solution for hydroponic monitoring with blockchain integration, suitable for both commercial and research applications where reliable data collection and secure storage are essential.
