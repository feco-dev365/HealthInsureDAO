# HealthInsureDAO - Decentralized Health Insurance Platform

## 🏥 Overview

HealthInsureDAO is a revolutionary blockchain-based health insurance platform that leverages real-time health data from wearable devices to create personalized, fair, and transparent insurance premiums. By combining smart contracts, health data oracles, and decentralized governance, we're building the future of health insurance.

## 🌟 Key Features

### 1. Dynamic Premium Calculator
- **Real-time Premium Adjustments**: Premiums automatically adjust based on verified health metrics from wearables
- **Multi-metric Analysis**: Considers heart rate, daily steps, sleep quality, and blood pressure
- **Incentivized Healthy Living**: Better health metrics = lower premiums
- **Oracle Integration**: Secure, tamper-proof health data validation

### 2. Risk Pool Management System
- **Intelligent Pool Assignment**: Users automatically grouped by health risk profiles
- **5-Tier Risk Structure**: From "Excellent Health" to "High Risk" pools
- **Dynamic Rebalancing**: Automatic pool reassignment as health improves/declines
- **Pool-based Premium Adjustments**: Fair pricing within similar risk groups
- **Transparency**: Full visibility into pool statistics and performance

### 3. Claims Processing System ⭐ **NEW**
- **Automated Processing**: Instant approval for small, low-risk claims
- **Fraud Detection**: AI-powered analysis of claim patterns and anomalies
- **Multi-tier Validation**: Automated checks + human validator review
- **Appeal Process**: Fair dispute resolution for rejected claims
- **Integration**: Seamless connection with premium calculator and risk pools

## 🏗️ Architecture

### Smart Contract Structure

\`\`\`
HealthInsureDAO/
├── contracts/
│   ├── dynamic-premium-calculator.clar    # Core premium calculation logic
│   ├── risk-pool-management.clar          # User risk pool assignment & management
│   └── claims-processing.clar             # Claims submission, validation & payouts
├── tests/
│   ├── premium-calculator-test.clar
│   ├── risk-pool-test.clar
│   └── claims-processing-test.clar
└── scripts/
    ├── deploy.js
    └── initialize-pools.js
\`\`\`

### Data Flow

1. **Health Data Collection**: Wearable devices → Health Oracles → Smart Contracts
2. **Risk Assessment**: Health metrics → Risk score calculation → Pool assignment
3. **Premium Calculation**: Base premium + Risk factors + Pool adjustments = Final premium
4. **Claims Processing**: Claim submission → Validation → Automated/Manual review → Payout

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) for smart contract development
- [Stacks CLI](https://docs.stacks.co/docs/cli) for blockchain interaction
- Node.js 16+ for deployment scripts

### Installation

\`\`\`bash
# Clone the repository
git clone https://github.com/yourusername/HealthInsureDAO.git
cd HealthInsureDAO

# Install Clarinet
curl -L https://github.com/hirosystems/clarinet/releases/latest/download/clarinet-linux-x64.tar.gz | tar xz
sudo mv clarinet /usr/local/bin

# Initialize the project
clarinet new healthinsure-dao
cd healthinsure-dao
\`\`\`

### Deployment

\`\`\`bash
# Test contracts locally
clarinet test

# Deploy to testnet
clarinet deploy --testnet

# Initialize risk pools (run once after deployment)
clarinet call initialize-pools --testnet
\`\`\`

## 📊 Contract Details

### Dynamic Premium Calculator

**Core Functions:**
- `register-user(base-premium, risk-factor)` - Register new user with initial profile
- `update-health-metrics(user, heart-rate, steps, sleep, bp-sys, bp-dia)` - Update health data
- `calculate-premium(user)` - Calculate current premium based on health metrics
- `pay-premium()` - Process premium payment

**Health Metrics Scoring:**
- **Heart Rate**: Optimal 60-70 BPM (lowest risk), penalties for extremes
- **Daily Steps**: 12,000+ steps = 0 risk, <3,000 steps = high risk
- **Sleep Hours**: 7-8 hours optimal, penalties for <5 or >9 hours
- **Blood Pressure**: <120/80 optimal, staged penalties for hypertension

### Risk Pool Management

**Pool Structure:**
1. **Excellent Health** (Score 0-25): 80% premium multiplier
2. **Good Health** (Score 26-50): 90% premium multiplier  
3. **Average Health** (Score 51-75): 100% premium multiplier
4. **Poor Health** (Score 76-100): 120% premium multiplier
5. **High Risk** (Score 101+): 150% premium multiplier

**Key Functions:**
- `initialize-pools()` - Set up default risk pool structure
- `assign-user-to-pool(user, health-score)` - Assign user to appropriate pool
- `rebalance-user(user, new-health-score)` - Move user between pools
- `calculate-pool-adjusted-premium(user, base-premium)` - Apply pool-based adjustments

### Claims Processing System

**Claim Types:**
1. **Emergency** - Urgent medical situations
2. **Routine** - Regular medical care
3. **Preventive** - Wellness and prevention
4. **Chronic** - Ongoing condition management
5. **Mental Health** - Psychological care

**Processing Workflow:**
1. **Submission**: User submits claim with supporting documentation
2. **Automated Validation**: Fraud detection and basic checks
3. **Manual Review**: Human validator assessment for complex claims
4. **Decision**: Approval, rejection, or request for additional information
5. **Payout**: Automatic token transfer to approved claimants
6. **Appeal**: Dispute resolution process for rejected claims

**Fraud Detection Features:**
- **Pattern Analysis**: Unusual claim frequency or amounts
- **Health Data Correlation**: Claims inconsistent with health metrics
- **Provider Verification**: Medical provider authentication
- **Timing Analysis**: Suspicious claim timing patterns

## 🔧 Usage Examples

### For Users

```clarity
;; Register as a new user
(contract-call? .dynamic-premium-calculator register-user u100000 u50)

;; Update health metrics (called by authorized oracle)
(contract-call? .dynamic-premium-calculator update-health-metrics 
  'SP1234... u65 u8500 u7 u118 u75)

;; Check current premium
(contract-call? .dynamic-premium-calculator calculate-premium 'SP1234...)

;; Submit a medical claim
(contract-call? .claims-processing submit-claim 
  u1 u25000 "Emergency room visit for chest pain" 0x1234...)
