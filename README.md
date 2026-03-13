# Chain11

A fully decentralized fantasy sports platform built for **EVM** with **Chainlink Functions** for trustless score oracle and settlement.

![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)
![Base](https://img.shields.io/badge/Chain-Base-blue)
![Chainlink](https://img.shields.io/badge/Oracle-Chainlink-375bd2)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 🏏 Features

- **Create Contests** — Anyone can create a fantasy contest for any cricket match
- **Join & Submit Teams** — Pick 11 players, captain (2×), vice-captain (1.5×)
- **Automatic Settlement** — Chainlink fetches scores and calculates winners off-chain
- **Decentralized Prizes** — Top 3 or Top 10 winners split the pool
- **Gas Optimized** — Batch operations, compressed contracts, <24KB each
- **Scalable** — Handles 600+ participants per contest

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────┐
│              Chain11.sol (22KB)                  │
│  • Contest management                            │
│  • Team validation (batched)                     │
│  • Prize distribution                            │
└───────────────────┬──────────────────────────────┘
                    │
                    ▼ calls
┌──────────────────────────────────────────────────┐
│            Chain11Oracle.sol (19KB)              │
│  • Chainlink Functions integration               │
│  • Match initialization (squad data)             │
│  • Score fetching (fantasy points)               │
│  • Settlement calculation (off-chain)            │
└───────────────────┬──────────────────────────────┘
                    │
                    ▼ requests
┌──────────────────────────────────────────────────┐
│              Chainlink DON                       │
│  • Fetches match data from Cricket API           │
│  • Fetches final scores                          │
│  • Calculates winners (batched RPC calls)        │
│  • Returns top K winners                         │
└──────────────────────────────────────────────────┘
```

---

## 📦 Installation

### Prerequisites
```bash
node >= 18.0.0
npm >= 9.0.0
```

### Setup
```bash
# Clone repository
git clone https://github.com/DaevMithran/chain11.git
cd chain11

# Install dependencies
npm install

# Copy environment template
cp .env.example .env
```

### Environment Variables
```bash
# .env
PRIVATE_KEY=                              # Deployer wallet private key
BASE_RPC_URL=https://mainnet.base.org     # Base mainnet RPC
BASESCAN_API_KEY=                         # For contract verification

# Chainlink Functions
CHAINLINK_ROUTER_ADDRESS=0xf9B8fc078197181C841c296C876945aaa425B278
CHAINLINK_DON_ID=0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000
CHAINLINK_SUBSCRIPTION_ID=                # Your Chainlink subscription ID

# Contract addresses (set after deployment)
ORACLE_ADDRESS=
CORE_ADDRESS=
```

---

## 🚀 Quick Start

### 1. Compile Contracts
```bash
npx hardhat compile
```

### 2. Run Tests
```bash
# All tests
npx hardhat test

# With gas reporting
REPORT_GAS=true npx hardhat test
```

### 3. Deploy to Testnet (Base Sepolia)
```bash
# Create Chainlink subscription first:
# https://functions.chain.link (Base Sepolia)

# Deploy Oracle
npx hardhat run scripts/deploy-oracle.ts --network base-sepolia

# Deploy Core
export ORACLE_ADDRESS=0x...
npx hardhat run scripts/deploy-core.ts --network base-sepolia

# Link contracts
export CORE_ADDRESS=0x...
npx hardhat run scripts/link-contracts.ts --network base-sepolia
```

### 4. Verify Contracts
```bash
npx hardhat verify --network base-sepolia $ORACLE_ADDRESS \
  $CHAINLINK_ROUTER_ADDRESS \
  $CHAINLINK_DON_ID \
  $CHAINLINK_SUBSCRIPTION_ID

npx hardhat verify --network base-sepolia $CORE_ADDRESS \
  $ORACLE_ADDRESS
```

**Expected gas costs:**
- Create contest: ~200k gas (~$0.04)
- Join & submit team: ~59k gas (~$0.01) — optimized with batch validation
- Settlement: ~300k gas (~$0.06) — constant, regardless of participants

## 💰 Tokenomics

### Fees
```
Contest creation: 0.01 ETH
Team entry:       0.01 ETH
Platform fee:     10% of all entries
```

### Prize Distribution

**3-9 participants (Top 3):**
```
1st: 50% | 2nd: 30% | 3rd: 20%
```

**10+ participants (Top 10):**
```
1st: 30% | 2nd: 15% | 3rd: 10% | Ranks 4-10: 5% each
```

### Chainlink Costs (per contest)
```
Match initialization: ~0.3 LINK  (~$1.50)
Score fetching:       ~0.3 LINK  (~$1.50)
Settlement:           ~0.3 LINK  (~$1.50)
Total:                ~0.9 LINK  (~$4.50)
```

---

## 🛠️ Tools & Technologies Used

| Category | Tool | Version | Purpose |
|----------|------|---------|---------|
| **Language** | Solidity | 0.8.28 | Smart contracts |
| **Framework** | Hardhat | 2.22+ | Development environment |
| **Library** | Viem | 2.x | Contract interactions |
| **Oracle** | Chainlink Functions | 1.0.0 | Off-chain data & compute |
| **Build** | Terser | Latest | JS minification |
| **Optimizer** | Via IR | Built-in | Code optimization |

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.
---

## 🗺️ Roadmap

- [x] Core contract implementation
- [x] Chainlink Functions integration
- [x] Test suite
- [ ] Frontend dApp (React)
- [ ] Mobile app (React Native)
- [ ] Multi-sport support

---