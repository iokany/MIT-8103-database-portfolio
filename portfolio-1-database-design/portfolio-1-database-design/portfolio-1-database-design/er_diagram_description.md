# Entity-Relationship Architecture Description
**Course:** MIT 8103 Advanced Database Systems  
**System:** ApexPay Global Bank / Fintech Platform  
**Student Name:** Ifenna Victor Okany  
**Student ID:** 301923302  

---

## 1. High-Level Entity Catalog

| Entity | Schema | Primary Key | Description |
| :--- | :--- | :--- | :--- |
| **`customers`** | `core_banking` | `customer_id` (UUID) | Individual or business customer profile with KYC status. |
| **`customer_identities`** | `core_banking` | `identity_id` (UUID) | Official KYC verification documents (Passports, National ID). |
| **`account_types`** | `core_banking` | `account_type_id` (INT) | Product catalog defining transaction limits and interest rates. |
| **`accounts`** | `core_banking` | `account_id` (UUID) | Operating financial accounts storing cached balances. |
| **`transactions`** | `core_banking` | `transaction_id` (UUID) | Parent transaction recording payment intent and status. |
| **`ledger_entries`** | `core_banking` | `entry_id` (UUID) | Immutable double-entry bookkeeping ledger (Debits & Credits). |
| **`audit_logs`** | `audit_system` | `log_id` (BIGINT) | SHA-256 cryptographically chained forensic activity trail. |

---

## 2. Mermaid Structural ER Diagram

GitHub automatically renders this diagram visually:

```mermaid
erDiagram
    CUSTOMERS ||--o{ CUSTOMER_IDENTITIES : "verifies with"
    CUSTOMERS ||--o{ ACCOUNTS : "owns"
    ACCOUNT_TYPES ||--o{ ACCOUNTS : "classifies"
    ACCOUNTS ||--o{ TRANSACTIONS : "initiates as source"
    ACCOUNTS ||--o{ TRANSACTIONS : "receives as destination"
    TRANSACTIONS ||--|{ LEDGER_ENTRIES : "generates double-entry"
    ACCOUNTS ||--|{ LEDGER_ENTRIES : "posts to"

    CUSTOMERS {
        uuid customer_id PK
        varchar first_name
        varchar last_name
        varchar email UK
        varchar phone_number
        varchar bvn_or_nin UK
        kyc_tier_enum kyc_tier
        customer_status_enum status
    }

    CUSTOMER_IDENTITIES {
        uuid identity_id PK
        uuid customer_id FK
        varchar document_type
        varchar document_number
        char document_hash_sha256
        date expiry_date
    }

    ACCOUNT_TYPES {
        int account_type_id PK
        varchar type_code UK
        varchar currency
        numeric daily_transfer_limit
        numeric minimum_balance
    }

    ACCOUNTS {
        uuid account_id PK
        varchar account_number UK
        uuid customer_id FK
        int account_type_id FK
        numeric ledger_balance
        numeric available_balance
        account_status_enum status
    }

    TRANSACTIONS {
        uuid transaction_id PK
        varchar transaction_reference UK
        varchar idempotency_key UK
        uuid source_account_id FK
        uuid destination_account_id FK
        numeric gross_amount
        numeric fee_amount
        numeric net_amount
        transaction_status_enum status
    }

    LEDGER_ENTRIES {
        uuid entry_id PK
        uuid transaction_id FK
        uuid account_id FK
        ledger_entry_type_enum entry_type
        numeric amount
        numeric running_balance_after
    }

    AUDIT_LOGS {
        bigint log_id PK
        uuid actor_id
        varchar action
        varchar entity_name
        varchar entity_id
        char previous_hash
        char current_hash
    }
```

---

## 3. Structural Relationships & Referential Integrity Rules

1. **`customers` to `customer_identities` (1 to 0..N):**
   - **Relationship:** One customer can submit multiple identity verification documents over time.
   - **Referential Action:** `ON DELETE RESTRICT`. A customer record cannot be deleted if active KYC document proofs exist.

2. **`customers` to `accounts` (1 to 1..N):**
   - **Relationship:** A customer owns one or more accounts (e.g. Savings, Current, and USD Domiciliary Wallet).
   - **Referential Action:** `ON DELETE RESTRICT`. Accounts holding balances or financial records cannot be accidentally deleted or orphaned.

3. **`account_types` to `accounts` (1 to 0..N):**
   - **Relationship:** Product types define the operational limits (daily withdrawal and transfer caps) for multiple accounts.

4. **`accounts` to `transactions` (1 to 0..N):**
   - **Relationship:** An account can act as the source or destination across numerous financial transactions.

5. **`transactions` to `ledger_entries` (1 to 2..N):**
   - **Relationship:** Every completed transaction must create at least two balanced ledger entries (one Debit and one Credit) to satisfy the fundamental rule of double-entry accounting.
