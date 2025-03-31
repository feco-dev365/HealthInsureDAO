# HealthInsureDAO

A decentralized autonomous organization for personalized health insurance based on verifiable health metrics.

## Overview

HealthInsureDAO is a blockchain-based health insurance platform that dynamically adjusts premiums based on verifiable health metrics from wearable devices. The system creates risk pools of users with similar health profiles, incentivizing healthier lifestyles through lower premiums.

## Smart Contracts

### Dynamic Premium Calculator

The core smart contract that calculates insurance premiums based on health metrics received from authorized data providers (oracles). The contract:

- Registers users with initial risk profiles
- Securely receives health metrics from authorized data sources
- Calculates personalized premiums based on health data
- Processes premium payments

## How It Works

1. **User Registration**: Users register with the DAO and are assigned an initial risk factor and base premium
2. **Health Data Integration**: Authorized data providers (oracles) submit verified health metrics from wearable devices
3. **Dynamic Premium Calculation**: The smart contract calculates personalized premiums based on:
   - Heart rate averages
   - Daily step counts
   - Sleep quality metrics
   - Blood pressure readings
4. **Premium Payment**: Users pay their dynamically calculated premiums through the contract

## Risk Calculation

The contract evaluates several health metrics to determine a user's overall health score:

- **Heart Rate**: Optimal ranges receive lower risk scores
- **Physical Activity**: Higher step counts lead to lower premiums
- **Sleep Quality**: Adequate sleep duration reduces risk assessment
- **Blood Pressure**: Normal blood pressure readings decrease premium costs

## Security Features

- Only authorized data providers can submit health metrics
- Contract owner manages the list of authorized data providers
- Health data is validated before affecting premium calculations

## Future Development

- Integration with additional wearable devices and health metrics
- Implementation of a governance token for DAO voting on policy changes
- Development of a claims processing system
- Cross-chain compatibility for broader adoption

## License

This project is licensed under the MIT License - see the LICENSE file for details.
