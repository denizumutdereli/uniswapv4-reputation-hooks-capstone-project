# Reputation Hook Contract Project

## Table of Contents
- [Reputation Hook Contract Project](#reputation-hook-contract-project)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Architecture](#architecture)
  - [Components](#components)
    - [Uniswap V4 Hooks](#uniswap-v4-hooks)
    - [MetaPool Library](#metapool-library)
    - [Reputation Logic Contracts](#reputation-logic-contracts)
    - [Brevis Zero-Knowledge Computation](#brevis-zero-knowledge-computation)
    - [Reputation Oracle](#reputation-oracle)
    - [EigenLayer Integration](#eigenlayer-integration)
    - [Chainlink Integration](#chainlink-integration)
  - [Features](#features)
  - [Fee Structuring](#fee-structuring)
  - [Deployment](#deployment)
  - [Helpful Commands](#helpful-commands)
  - [Important Note](#important-note)
  - [Architecture Diagram](#architecture-diagram)
  - [References](#references)

## Introduction
Welcome to the **Reputation Hook Contract Project**, as part of [Atrium Academy - Uniswap Hook Incubator program](https://atrium.academy/uniswap) programme, a proof-of-concept that showcases the potential of Uniswap V4 Hooks to revolutionize decentralized finance. This project demonstrates how liquidity providers and traders can be rewarded based on their reputations, influencing various aspects of the trading environment such as fees and access to premium features.

## Architecture
The project architecture leverages several cutting-edge technologies and platforms:
- **Uniswap V4 Hooks**: To modify the behavior of liquidity pools.
- **MetaPool Library**: A low-level library that aggregates inter-connected pools and their liquidities.
- **Reputation Logic Contracts**: Deployed using EIP-1167 minimal proxies for efficiency.
- **Brevis Zero-Knowledge Computation**: For secure, reliable and private reputation calculations.
- **Reputation Oracle**: An ERC-1155 contract that stores user reputations.
- **EigenLayer**: Provides security and reliability through Ethereum Proof of Stake.
- **Chainlink Automation**: For reliable off-chain and onchain smooth transisions & oracle services.

## Components

### Uniswap V4 Hooks
Uniswap V4 Hooks allow developers to customize the behavior of liquidity pools. In this project, hooks are used to track user activities and influence pool parameters based on reputations.

### MetaPool Library
The **MetaPool** library is a cornerstone of this project, unlocking new possibilities for liquidity management and user interaction across multiple interconnected pools. By aggregating data from various pools, MetaPool provides a comprehensive view of the ecosystem, enabling a range of advanced functionalities, such as:
- **Global Liquidity Insights**: By aggregating liquidity data across all connected pools, MetaPool allows for an unprecedented understanding of market dynamics. This global perspective helps in optimizing liquidity allocation, reducing slippage, and enhancing overall market efficiency.
- **Cross-Pool Reputation Tracking**: MetaPool facilitates tracking user behavior across multiple pools, enabling a holistic approach to reputation management. This cross-pool visibility ensures that user actions, whether positive or negative, are consistently recognized and rewarded, creating a more cohesive incentive structure.
- **Enhanced Decision Making**: With access to detailed metrics such as tick shifts, liquidation patterns, and slippage data, MetaPool empowers developers to build intelligent hooks that respond dynamically to market conditions. For example, hooks can adjust trading fees based on real-time market volatility or incentivize liquidity provision during periods of low activity.
- **Aggregated Yield Analytics**: MetaPool computes advanced financial metrics like APY (Annual Percentage Yield) and APR (Annual Percentage Rate) across all connected pools, providing deeper insights into yield opportunities. This functionality can be extended to support custom yield optimization strategies, further enhancing user engagement.
- **Second Derivative Movements**: By analyzing the second derivative of liquidity and trading volume, MetaPool offers insights into the rate of change in market conditions. This advanced analysis can be used to preemptively adjust trading parameters, enhancing the stability and efficiency of the liquidity pools.
- **Custom Hook Integration**: MetaPool's architecture supports the integration of custom hooks, known as **HULKs** (Hook Utility and Liquidity Kits), which can introduce novel functionalities tailored to specific use cases. This modular approach opens up a broad range of possibilities, from custom reward structures to advanced trading mechanisms like limit orders and flash loans, governed by the user's reputation.
Overall, MetaPool serves as a foundational layer that not only enhances existing functionalities but also paves the way for new innovations in DeFi. Its ability to aggregate and analyze data across multiple pools creates a versatile platform for experimenting with complex financial instruments and strategies, making it a key asset in the reputation-based DeFi landscape.

### Reputation Logic Contracts
Reputation Logic Contracts are automatically created using the EIP-1167 minimal proxy pattern when a new pool is initialized. Each pool has its own reputation logic contract, allowing for separation of concerns and modularity. These contracts handle the intricacies of user reputation management, ensuring that each pool's logic remains independent while still contributing to the overall ecosystem.

### Brevis Zero-Knowledge Computation
Brevis provides zero-knowledge computation services that calculate user reputations securely and privately. It uses sophisticated algorithms like the Hamming Distance for reputation scoring. This ensures that user data remains confidential, while still allowing for accurate and transparent reputation assessments.

### Reputation Oracle
The **Reputation Oracle** is an ERC-1155 contract that stores user reputations in a decentralized manner. It manages two types of tokens:
- **pRO Tokens**: Representing user reputations.
- **RO Tokens**: Spendable tokens that users can utilize for premium features like discounted fees. The oracle continuously updates these reputations based on data provided by the Brevis ZK computation and influences the user's interactions with the pools.

### EigenLayer Integration
EigenLayer is used to ensure security and reliability by leveraging Ethereum's Proof of Stake mechanism. It orchestrates the tokenomics end-to-end, providing a robust foundation for the reputation system. EigenLayer's integration guarantees that the reputation system remains secure, scalable, and aligned with Ethereum's broader security model.

### Chainlink Integration
Chainlink is integrated to provide reliable oracle services and off-chain data feeds, enhancing the system's overall reliability and decentralization. By leveraging Chainlink Automation, the project ensures that transisions trustworthy and that the integrity of off-chain computations is maintained.

## Features
- **Dynamic Fee Structuring**: Pools can adjust fees dynamically based on user reputation tiers obtained from the Reputation Oracle.
- **Reputation-Based Access**: Users with higher reputations can access premium features like discounted fees and custom trading options.
- **MetaPool Insights**: Aggregated data allows for the creation of intelligent hooks and custom pool behaviors.
- **Custom Hook Providers (HULKs)**: Allow for the development of advanced hooks that can provide intelligent functionalities similar to MetaPool.

## Fee Structuring
Unlike traditional methods that use the `updateDynamicLPFee` function, this project employs delta-based fee adjustments without worrying about fee caching. The fee structure adapts in real-time based on the user's reputation tier, allowing pools to incentivize positive behaviors and penalize negative actions dynamically.

## Deployment
The project includes:
- **5 Core Contracts**
- **6 Mock Contracts**
- **9 Extensive Low-Level Libraries**

Approximately **4,000 lines of code** have been written to implement the system.


## Helpful Commands
- Start Anvil with custom settings:
  ```bash
  anvil --block-time 1 --gas-limit 10000000 --port 8545

clear;forge test -vvvv --fork-url http://127.0.0.1:8545

clear;forge script script/AnvilDeployment.s.sol:ReputationHookDeployer --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944b................ --block-time 10 -vvvv

clear;tsc;node ../dist/app.js

anvil --hardfork cancun

## Important Note

Add the following line to your remappings.txt file due to vmJsonWrite permissions required for offchain Brevis mocks to capture the deployed Reputation Oracle contract address and start listening to requests and tasks:

forge-std/=lib/forge-std/src/


## Architecture Diagram

flowchart TD
    subgraph User Interaction
        A[Liquidity Provider / Trader]
    end

    subgraph Uniswap V4 Pool
        B[Liquidity Pool]
        C[Uniswap V4 Hook Contract]
    end

    subgraph Reputation System
        D[MetaPool Library]
        E[Reputation Logic Contract]
        F[Brevis ZK Computation]
        G[Reputation Oracle (ERC-1155)]
    end

    subgraph Security Layer
        H[EigenLayer]
    end

    subgraph Oracle Services
        I[Chainlink]
    end

    A -- Provides Liquidity / Trades --> B
    B -- Invokes Hooks --> C
    C -- Sends User Activity --> D
    D -- Updates --> E
    E -- Sends Data --> F
    F -- Computes Reputation --> G
    G -- Updates Reputation Tokens --> A
    G -- Interacts With --> H
    C -- Requests Data --> I
    I -- Provides Data --> C

## References

- [Uniswap V4 Hooks](https://uniswap.org/blog/uniswap-v4)
- [Brevis Zero-Knowledge Computation](https://brevis.network/)
- [EigenLayer](https://www.eigenlayer.xyz/)
- [Chainlink](https://chain.link/)
- [Atrium Academy](https://atrium.academy/uniswap)
- [EIP-1167: Minimal Proxy Contract](https://eips.ethereum.org/EIPS/eip-1167)
- [ERC-1155 Multi Token Standard](https://eips.ethereum.org/EIPS/eip-1155)

