# Polyglot Persistence & NoSQL Architecture
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** ApexPay Bank / Fintech Platform  
**Student Name:** Ifenna Victor Okany | ID: 301923302  

---

## 1. Why Polyglot Persistence?
In modern banking, using only SQL or only NoSQL creates major problems:
- **SQL (PostgreSQL):** Excellent for ACID compliance, money transfers, and balance consistency.
- **NoSQL (MongoDB):** Excellent for unstructured KYC documents (passports, driver's licenses) and high-speed fraud logging without needing slow database schema migrations.

---

## 2. Time-Series Bucketing Pattern
Instead of storing each transaction as an isolated document, transactions are grouped into monthly buckets:
- **Document Key:** `{ account_id: "0123456789", bucket_year_month: "2026-11" }`
- **Advantage:** Generating a customer's monthly account statement requires **1 single disk read**, rather than querying hundreds of individual documents.

---

## 3. CAP Theorem Configuration
Under the CAP Theorem, ApexPay configures MongoDB as **CP (Consistency + Partition Tolerance)**:
- **Write Concern:** `w: "majority", j: true` (ensures writes are written to disk across a majority of nodes before confirmation).
- In a financial platform, stopping an ambiguous transaction during a network partition is far safer than allowing conflicting balances (split-brain).
