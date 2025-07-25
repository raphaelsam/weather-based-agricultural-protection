# Weather-Based Agricultural Protection Smart Contract

## Overview

This Clarity smart contract implements an automated agricultural protection system that provides compensation to farmers based on predefined weather triggers. Unlike traditional crop insurance that requires manual claims processing, this system automatically executes payouts when specific weather conditions (drought, excessive rainfall, or freezing temperatures) are detected through authorized weather oracles.

## Key Features

- **Automated Payouts**: No manual claims required - compensation is triggered automatically by weather data
- **Multi-Risk Coverage**: Protects against drought, flooding, and frost damage
- **Oracle-Based**: Uses certified weather data providers for reliable information
- **Risk Pooling**: Premiums are pooled by crop type to distribute risk
- **Partial Refunds**: Policy holders can cancel early and receive prorated refunds
- **Data Verification**: Multiple oracles can verify weather data for accuracy

## Contract Architecture

### Core Data Structures

1. **Protection Agreements** (`protection-agreements`)
   - Individual farmer protection policies with coverage terms and trigger thresholds

2. **Weather Observations** (`weather-observations`)
   - Timestamped weather data from certified oracles

3. **Certified Oracles** (`certified-oracles`)
   - Authorized weather data providers

4. **Protection Pools** (`protection-pools`)
   - Risk pools organized by crop type containing premiums and reserves

## Main Functions

### For Farmers

- `create-protection()` - Purchase a new protection policy
- `terminate-protection()` - Cancel policy early for partial refund
- `assess-protection()` - Manually trigger policy evaluation

### For Weather Oracles

- `register-weather-oracle()` - Register as a certified data provider
- `record-weather-observation()` - Submit weather data
- `validate-weather-observation()` - Verify data from other oracles

### Read-Only Functions

- `get-protection-details()` - View policy information
- `get-weather-observation()` - Access weather data
- `get-protection-pool()` - Check risk pool status
- `check-oracle-certification()` - Verify oracle authorization

## Usage Example

### 1. Create Protection Policy

```clarity
(create-protection 
  "REGION-001"           ;; location-id
  "corn"                 ;; crop-type
  u1000000               ;; compensation-limit (10 STX)
  u50000                 ;; premium-amount (0.5 STX)
  u52560                 ;; coverage-duration (~1 year in blocks)
  50                     ;; drought-threshold (50mm rainfall)
  300                    ;; excessive-rain-threshold (300mm rainfall)
  2                      ;; freeze-threshold (2°C)
  'SP1ABC...XYZ          ;; weather-oracle address
)
```

### 2. Submit Weather Data (Oracle Only)

```clarity
(record-weather-observation
  "REGION-001"           ;; location-id
  25                     ;; rainfall-mm (triggers drought payout)
  15                     ;; temperature-celsius
  u65                    ;; humidity-level
)
```

## Trigger Conditions

Automatic payouts occur when weather data meets any of these conditions:
- **Drought**: Rainfall below the drought threshold
- **Flooding**: Rainfall above the excessive rain threshold  
- **Frost**: Temperature below the freeze threshold

## Economic Model

- **Protocol Fee**: 5% of premiums go to protocol treasury
- **Risk Pools**: 95% of premiums fund crop-specific insurance pools
- **Reserve Ratio**: Default 70% reserve requirement per pool
- **Automatic Execution**: No additional fees for payouts

## Security Features

- **Oracle Authorization**: Only certified oracles can submit weather data
- **Data Verification**: Multiple oracles can cross-verify observations
- **Threshold Validation**: Reasonable limits on weather trigger values
- **Access Control**: Policy holders and oracles have appropriate permissions
- **Partial Refunds**: Time-based refund calculations prevent abuse

## Deployment Requirements

1. Deploy contract to Stacks blockchain
2. Register initial weather oracles
3. Set protocol fee collector address
4. Fund initial risk pools (optional)

## Limitations

- **Oracle Dependency**: Requires reliable weather data providers
- **Geographic Coverage**: Limited to regions with active oracles
- **Single Payout**: Each policy can only trigger one compensation
- **Block-Based Timing**: Uses blockchain blocks for time calculations

## Future Enhancements

- Multi-oracle consensus mechanisms
- Dynamic pricing based on historical data
- Crop yield correlation factors
- Governance token for protocol parameters
- Cross-chain oracle integration

