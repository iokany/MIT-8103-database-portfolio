# ApexPay Bank & Fintech Platform
## MIT 8103 Advanced Database Systems - Course Portfolio

- **University:** Miva Open University
- **Programme:** M.Sc. Information Technology
- **Course Code:** MIT 8103 - Advanced Database Systems
- **Academic Session:** 2026/2027
- **Student Name:** Ifenna Victor Okany
- **Student ID:** 301923302
- **GitHub Username:** [iokany](https://github.com/iokany)
- **Live Portfolio Website:** [https://iokany.github.io/mit-8103-database-portfolio/](https://iokany.github.io/mit-8103-database-portfolio/)

---

## 1. Project Overview

This project is an advanced, individual database engineering portfolio built for a realistic digital fintech bank called **ApexPay**.

The system is designed to handle core digital banking operations safely and reliably, including:
- Customer registration and KYC identity verification (BVN, NIN, international passports).
- Multi-currency customer accounts (Savings, Current, Merchant, and USD Wallets).
- Real-time fund transfers, deposits, withdrawals, and fee deductions.
- An immutable double-entry ledger ensuring accounting balance across all transactions.
- Cryptographically chained forensic audit logs to detect fraud and policy violations.

---

## 2. Project Folder Structure

The repository is structured into five distinct portfolio activities, following the official course guidelines:

```text
mit-8103-database-portfolio/
├── portfolio-1-database-design/
│   ├── schema.sql                     # Full DDL schema, constraints, enums, and indexes
│   ├── normalization_report.md        # Formal proofs of 1NF, 2NF, 3NF, and BCNF
│   └── er_diagram_description.md      # Structural layout and Mermaid ER diagrams
├── portfolio-2-query-optimisation/
│   ├── complex_queries.sql            # Advanced multi-table JOINs, window functions, rCTEs
│   └── execution_plans_analysis.md    # EXPLAIN ANALYZE benchmarks and 98% index speedup
├── portfolio-3-transactions-concurrency/
│   ├── transaction_demos.sql          # ACID transactions, SAVEPOINTs, and idempotency
│   └── concurrency_report.md          # Isolation levels, race conditions, and deadlock solutions
├── portfolio-4-nosql/
│   ├── nosql_models.json              # MongoDB document models (Profiles, Ledgers, Audits)
│   └── nosql_explanation.md           # Polyglot persistence, sharding, and CAP trade-offs
├── portfolio-5-distributed-cloud/
│   └── distributed_strategy.md        # Multi-region replication, PACELC, and cloud HA
└── README.md                          # Master portfolio overview and reflection
```

---

## 3. Summary of Portfolio Deliverables

### Portfolio 1: Database Design and Modelling
- **What Was Implemented:** The complete relational schema was designed in PostgreSQL 15, creating the core entities: `customers`, `customer_identities`, `account_types`, `accounts`, `transactions`, `ledger_entries`, and `audit_logs`.
- **Integrity Rules:** Data integrity was enforced through primary keys, foreign keys (`ON DELETE RESTRICT`), unique indexes, and `CHECK` constraints on positive balances and valid email formats.
- **Normalization Proof:** The data structures were analyzed mathematically, proving full compliance with 1NF, 2NF, 3NF, and Boyce-Codd Normal Form (BCNF) to eliminate update, insertion, and deletion anomalies.

### Portfolio 2: Query Processing and Optimisation
- **What Was Implemented:** Four advanced analytical queries were authored utilizing multi-table joins, conditional aggregations, rolling 30-day window frames (`ROWS BETWEEN 29 PRECEDING AND CURRENT ROW`), and recursive Common Table Expressions (rCTEs) to trace fraud rings across mule accounts.
- **Performance Profiling:** Query execution plans were evaluated before and after optimization using `EXPLAIN (ANALYZE, BUFFERS)`. On an unindexed dataset of 24 million ledger entries, the baseline sequential scan took **9,158 ms**. By engineering a covering B-Tree index with the `INCLUDE` clause, execution time was reduced to **114 ms** (a **98.7% latency drop**).

### Portfolio 3: Transactions and Concurrency Control
- **What Was Implemented:** Production stored procedures were developed in PL/pgSQL demonstrating explicit `BEGIN`, `COMMIT`, `ROLLBACK`, and `SAVEPOINT` partial rollbacks for batch payroll runs.
- **Concurrency & Deadlock Prevention:** The fintech "double-spend" race condition was solved using row-level locking (`SELECT ... FOR UPDATE`). Furthermore, cyclic transaction deadlocks were eliminated by ordering account IDs lexicographically before acquiring locks.

### Portfolio 4: NoSQL and Advanced Data Models
- **What Was Implemented:** A polyglot persistence architecture was implemented using MongoDB alongside PostgreSQL.
- **Document Design:** JSON schema models were designed for `customer_profiles` (embedding polymorphic KYC identity proofs), `account_ledgers` (using the time-series bucketing pattern for fast monthly statement generation), and `realtime_fraud_audit_logs`.
- **CAP Theorem Mapping:** The NoSQL store was configured in **CP (Consistency & Partition Tolerance)** mode using `w: "majority"` and `j: true` to prevent data divergence during network partitions.

### Portfolio 5: Distributed and Cloud Database Strategy
- **What Was Implemented:** An active-active high-availability architecture was formulated with synchronous streaming replication in-region ($\text{RPO} = 0, \text{RTO} < 15\text{s}$) and asynchronous cross-region replication for disaster recovery.
- **Sharding & PACELC:** A horizontal sharding model was designed, partitioned on `customer_id` to guarantee single-shard transaction locality, and the core ledger was classified as **PC/EC** under the PACELC theorem.

---

## 4. Individual Technical Reflection

Working through this practical portfolio provided valuable insight into critical real-world database trade-offs:

1. **Academic Theory vs. Production Performance:**  
   In textbook database theory, an account balance should never be stored as an attribute, but computed dynamically from transaction history. However, in high-frequency production ($>20,000 \text{ TPS}$), re-summing millions of rows on every payment creates severe I/O bottlenecks. This was resolved by storing an atomically locked balance on the `accounts` table while preserving an immutable double-entry ledger as the true financial record.

2. **Solving Deadlocks Mathematically:**  
   Simultaneous reciprocal transfers ($A \to B$ and $B \to A$) often cause cyclic deadlocks in financial databases. By enforcing a deterministic lock acquisition order (sorting account IDs before locking), cycles in the database lock manager were eliminated completely.

3. **Polyglot Persistence in Modern Fintech:**  
   Relying exclusively on SQL tables for polymorphic identity documents and high-speed telemetry causes schema bloat. Combining PostgreSQL’s ACID guarantees with MongoDB’s flexible document models provides the optimal architecture for financial systems.

---

## 5. Academic Integrity & AI-Use Declaration

In strict accordance with Section 11 of the Miva Open University guidelines:
1. **AI Tool Used:** Google Gemini.
2. **What AI Was Used For:** Generative AI was used as an interactive technical sounding board, helping draft SQL boilerplate code, verify query explanations, and format documentation.
3. **Student Verification:** I, **Ifenna Victor Okany**, independently reviewed, understood, tested, and verified all database designs, normalization breakdowns, query plans, and concurrency strategies to ensure complete technical correctness and authenticity.
