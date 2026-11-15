# Database Normalization Report: ApexPay Fintech Platform
**Course:** MIT 8103 Advanced Database Systems  
**Academic Session:** 2026/2027  
**Student Name:** Ifenna Victor Okany  
**Student ID:** 301923302  

---

## 1. Executive Summary
This report demonstrates the step-by-step mathematical and relational normalization of the **ApexPay Bank & Fintech Platform**. The database was decomposed from an unnormalized transaction state (UNF) through First Normal Form (1NF), Second Normal Form (2NF), Third Normal Form (3NF), and Boyce-Codd Normal Form (BCNF). 

This process eliminates data redundancy and prevents insertion, update, and deletion anomalies while maintaining data integrity.

---

## 2. Unnormalized Form (UNF) Analysis
In a flat, unnormalized spreadsheet or receipt, banking records contain repeating groups and mixed entities:

```text
UNF_RECORD = {
    TransactionRef, Date, Narration,
    CustomerBVN, CustomerName, CustomerEmail, CustomerPhone,
    CustomerAddresses: [HomeAddress, WorkAddress],
    Identities: [{DocType, DocNumber, ExpiryDate}],
    SourceAccountNum, SourceAccountType, SourceBalance, SourceDailyLimit,
    DestAccountNum, DestAccountType, DestBalance, DestDailyLimit,
    LedgerEntries: [{AccountNum, DebitOrCredit, Amount, BalanceAfter}],
    AuditAction, AuditTimestamp, OldPayload, NewPayload
}
```

### Inherent Anomalies in UNF:
1. **Insertion Anomaly:** A new customer cannot be registered in the system without first opening an account and executing a dummy financial transaction.
2. **Update Anomaly:** If a customer changes their phone number or address, thousands of historical transaction records must be searched and modified. Missing even one row results in corrupt, contradictory data.
3. **Deletion Anomaly:** Deleting a cancelled transaction record accidentally purges the customer's identity records or account balance history.

---

## 3. First Normal Form (1NF) Compliance
**Rule:** A relation is in 1NF if every column contains atomic (single, indivisible) values, there are no repeating groups or arrays, and each row is uniquely identifiable by a primary key.

### Normalization Actions Taken:
- Decomposed compound attributes like `CustomerName` into atomic columns: `first_name` and `last_name`.
- Eliminated multi-valued repeating groups (`Identities`, `Addresses`, and `LedgerEntries`) by separating them into distinct dedicated tables linked by foreign keys.
- Assigned unique, immutable Primary Keys (`UUID` and `BIGSERIAL`) to all entities.

$$\text{1NF Condition: } \forall A \in R, \text{domain}(A) \text{ is atomic, and } \exists \text{PK}(R)$$

---

## 4. Second Normal Form (2NF) Compliance
**Rule:** A relation is in 2NF if it is in 1NF and every non-key attribute is fully functionally dependent on the entire primary key (no partial functional dependencies on composite keys).

### Analysis & Resolution:
Consider a composite candidate key for an entry: `{ transaction_id, account_id }`.
If non-key attributes were stored together:
$$\{ \underline{\text{transaction\_id}, \text{account\_id}}, \text{gross\_amount}, \text{account\_type\_name}, \text{running\_balance} \}$$

We observe the following partial dependencies:
- $\text{transaction\_id} \to \text{gross\_amount}$ (Depends only on the transaction, not the account).
- $\text{account\_id} \to \text{account\_type\_name}$ (Depends only on the account, not the transaction).
- $\{ \text{transaction\_id}, \text{account\_id} \} \to \text{running\_balance}$ (Full functional dependency).

### Decomposition:
1. Isolated transactions into `core_banking.transactions` keyed by `transaction_id`.
2. Isolated accounts into `core_banking.accounts` keyed by `account_id`.
3. Created `core_banking.ledger_entries` with an independent surrogate primary key `entry_id` to hold balanced double-entry postings.

All tables satisfy **2NF**.

---

## 5. Third Normal Form (3NF) Compliance
**Rule:** A relation is in 3NF if it is in 2NF and no non-key attribute is transitively dependent on the primary key (no $X \to Y \to Z$ dependencies).

### Identified Transitive Dependencies:
In early modeling of the `accounts` table:
$$\text{account\_id} \to \text{account\_type\_code} \to \{ \text{daily\_transfer\_limit}, \text{interest\_rate} \}$$
Here, `daily_transfer_limit` is determined by the account type code, not directly by the specific account number.

### Decomposition:
Extracted product terms into `core_banking.account_types`:
- Table `account_types`: $\text{PK: } \text{account\_type\_id} \to \{ \text{type\_code}, \text{daily\_transfer\_limit}, \text{interest\_rate\_annual} \}$.
- Table `accounts`: Retains solely the foreign key reference `account_type_id`.

Similarly, customer KYC documents were separated into `core_banking.customer_identities` so identity verification status does not transitively pollute the `customers` table.

All tables satisfy **3NF**.

---

## 6. Boyce-Codd Normal Form (BCNF) Evaluation
**Rule:** A relation is in BCNF if for every non-trivial functional dependency $X \to Y$, $X$ is a superkey.

- In `customers`: Determinants $\{ \text{customer\_id} \}$, $\{ \text{email} \}$, and $\{ \text{bvn\_or\_nin} \}$ are all candidate superkeys.
- In `accounts`: Determinants $\{ \text{account\_id} \}$ and $\{ \text{account\_number} \}$ are unique candidate superkeys.
- In `transactions`: Determinants $\{ \text{transaction\_id} \}$, $\{ \text{transaction\_reference} \}$, and $\{ \text{idempotency\_key} \}$ are all unique superkeys.

The entire schema satisfies **BCNF**.

---

## 7. Controlled Denormalization for Real-World Banking
In pure academic theory, an account balance should never be stored as an attribute, but computed dynamically by summing all historical ledger entries:
$$\text{balance} = \sum \text{Credits} - \sum \text{Debits}$$

### The Real-World Engineering Problem:
In high-frequency banking processing thousands of transactions per second, recalculating the sum of millions of historical rows on every card swipe causes severe database slowdowns.

### The Engineering Solution:
1. **Source of Truth:** Immutable `core_banking.ledger_entries` (strictly normalized, permanent double-entry record).
2. **Materialized Cache:** `available_balance` and `ledger_balance` are stored on `core_banking.accounts`.
3. **Safety Guarantee:** Row-level pessimistic locking (`SELECT ... FOR UPDATE`) and database triggers ensure the cached balance always matches the ledger total.
