-- ============================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1: Database Design
-- Case Study: ApexPay Bank / Fintech Platform
-- Target RDBMS: PostgreSQL 15+
-- Student Name: Ifenna Victor Okany | ID: 301923302
-- ============================================================================

DROP SCHEMA IF EXISTS audit_system CASCADE;
DROP SCHEMA IF EXISTS core_banking CASCADE;

CREATE SCHEMA core_banking;
CREATE SCHEMA audit_system;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- ENUM TYPES
-- ============================================================================
CREATE TYPE core_banking.customer_status_enum AS ENUM (
    'PENDING_VERIFICATION', 
    'ACTIVE', 
    'SUSPENDED', 
    'CLOSED', 
    'BLACKLISTED'
);

CREATE TYPE core_banking.kyc_tier_enum AS ENUM (
    'TIER_1_BASIC', 
    'TIER_2_STANDARD', 
    'TIER_3_PREMIUM'
);

CREATE TYPE core_banking.account_status_enum AS ENUM (
    'ACTIVE', 
    'DORMANT', 
    'FROZEN', 
    'CLOSED'
);

CREATE TYPE core_banking.transaction_type_enum AS ENUM (
    'DEPOSIT', 
    'WITHDRAWAL', 
    'TRANSFER', 
    'FEE', 
    'INTEREST', 
    'REVERSAL'
);

CREATE TYPE core_banking.transaction_status_enum AS ENUM (
    'INITIATED', 
    'PROCESSING', 
    'COMPLETED', 
    'FAILED', 
    'REVERSED'
);

CREATE TYPE core_banking.ledger_entry_type_enum AS ENUM (
    'DEBIT', 
    'CREDIT'
);

-- ============================================================================
-- TABLE 1: CUSTOMERS
-- ============================================================================
CREATE TABLE core_banking.customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    tax_identification_number VARCHAR(30) UNIQUE,
    bvn_or_nin VARCHAR(20) UNIQUE NOT NULL,
    kyc_tier core_banking.kyc_tier_enum NOT NULL DEFAULT 'TIER_1_BASIC',
    status core_banking.customer_status_enum NOT NULL DEFAULT 'PENDING_VERIFICATION',
    residential_address TEXT NOT NULL,
    city VARCHAR(80) NOT NULL,
    country_iso VARCHAR(3) NOT NULL DEFAULT 'NGA',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_phone_format CHECK (phone_number ~* '^\+?[0-9]{10,15}$'),
    CONSTRAINT chk_country_code CHECK (LENGTH(country_iso) = 3)
);

CREATE UNIQUE INDEX uq_customers_email ON core_banking.customers (LOWER(email));
CREATE INDEX idx_customers_status_kyc ON core_banking.customers (status, kyc_tier);
CREATE INDEX idx_customers_created_at ON core_banking.customers (created_at DESC);

-- ============================================================================
-- TABLE 2: CUSTOMER IDENTITIES & DOCUMENTS
-- ============================================================================
CREATE TABLE core_banking.customer_identities (
    identity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL,
    document_type VARCHAR(50) NOT NULL,
    document_number VARCHAR(100) NOT NULL,
    document_hash_sha256 CHAR(64) NOT NULL,
    verified_at TIMESTAMPTZ,
    expiry_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_identities_customer FOREIGN KEY (customer_id) 
        REFERENCES core_banking.customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT uq_customer_doc_type UNIQUE (customer_id, document_type),
    CONSTRAINT chk_future_expiry CHECK (expiry_date > created_at::DATE)
);

CREATE INDEX idx_identities_cust_id ON core_banking.customer_identities (customer_id);

-- ============================================================================
-- TABLE 3: ACCOUNT TYPES
-- ============================================================================
CREATE TABLE core_banking.account_types (
    account_type_id SERIAL PRIMARY KEY,
    type_code VARCHAR(20) UNIQUE NOT NULL,
    type_name VARCHAR(100) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'NGN',
    interest_rate_annual NUMERIC(5, 4) NOT NULL DEFAULT 0.0000,
    daily_withdrawal_limit NUMERIC(15, 2) NOT NULL,
    daily_transfer_limit NUMERIC(15, 2) NOT NULL,
    minimum_balance NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_positive_limits CHECK (
        daily_withdrawal_limit >= 0 AND 
        daily_transfer_limit >= 0 AND 
        minimum_balance >= 0
    )
);

-- ============================================================================
-- TABLE 4: ACCOUNTS
-- ============================================================================
CREATE TABLE core_banking.accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_number VARCHAR(10) UNIQUE NOT NULL,
    customer_id UUID NOT NULL,
    account_type_id INT NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'NGN',
    ledger_balance NUMERIC(18, 4) NOT NULL DEFAULT 0.0000,
    available_balance NUMERIC(18, 4) NOT NULL DEFAULT 0.0000,
    status core_banking.account_status_enum NOT NULL DEFAULT 'ACTIVE',
    row_version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id) 
        REFERENCES core_banking.customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_accounts_type FOREIGN KEY (account_type_id) 
        REFERENCES core_banking.account_types(account_type_id) ON DELETE RESTRICT,
    CONSTRAINT chk_account_nuban CHECK (account_number ~ '^[0-9]{10}$'),
    CONSTRAINT chk_balances CHECK (ledger_balance >= -50000.0000 AND available_balance >= -50000.0000)
);

CREATE INDEX idx_accounts_customer_id ON core_banking.accounts (customer_id);
CREATE INDEX idx_accounts_status ON core_banking.accounts (status);

-- ============================================================================
-- TABLE 5: TRANSACTIONS
-- ============================================================================
CREATE TABLE core_banking.transactions (
    transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_reference VARCHAR(64) UNIQUE NOT NULL,
    idempotency_key VARCHAR(128) UNIQUE NOT NULL,
    source_account_id UUID,
    destination_account_id UUID,
    transaction_type core_banking.transaction_type_enum NOT NULL,
    gross_amount NUMERIC(18, 4) NOT NULL,
    fee_amount NUMERIC(18, 4) NOT NULL DEFAULT 0.0000,
    net_amount NUMERIC(18, 4) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'NGN',
    status core_banking.transaction_status_enum NOT NULL DEFAULT 'INITIATED',
    narration VARCHAR(255) NOT NULL,
    failure_reason VARCHAR(255),
    ip_address INET,
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    
    CONSTRAINT fk_transactions_source FOREIGN KEY (source_account_id) 
        REFERENCES core_banking.accounts(account_id) ON DELETE RESTRICT,
    CONSTRAINT fk_transactions_destination FOREIGN KEY (destination_account_id) 
        REFERENCES core_banking.accounts(account_id) ON DELETE RESTRICT,
    CONSTRAINT chk_positive_gross_amount CHECK (gross_amount > 0.0000),
    CONSTRAINT chk_positive_fee CHECK (fee_amount >= 0.0000),
    CONSTRAINT chk_net_amount_calc CHECK (net_amount = gross_amount - fee_amount),
    CONSTRAINT chk_source_dest_not_equal CHECK (
        source_account_id IS NULL OR 
        destination_account_id IS NULL OR 
        source_account_id <> destination_account_id
    )
);

CREATE INDEX idx_transactions_source ON core_banking.transactions (source_account_id, initiated_at DESC);
CREATE INDEX idx_transactions_dest ON core_banking.transactions (destination_account_id, initiated_at DESC);
CREATE INDEX idx_transactions_status_date ON core_banking.transactions (status, initiated_at DESC);

-- ============================================================================
-- TABLE 6: LEDGER ENTRIES (Double-Entry Bookkeeping)
-- ============================================================================
CREATE TABLE core_banking.ledger_entries (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL,
    account_id UUID NOT NULL,
    entry_type core_banking.ledger_entry_type_enum NOT NULL,
    amount NUMERIC(18, 4) NOT NULL,
    running_balance_after NUMERIC(18, 4) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_ledger_transaction FOREIGN KEY (transaction_id) 
        REFERENCES core_banking.transactions(transaction_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_account FOREIGN KEY (account_id) 
        REFERENCES core_banking.accounts(account_id) ON DELETE RESTRICT,
    CONSTRAINT chk_entry_amount_positive CHECK (amount > 0.0000)
);

CREATE INDEX idx_ledger_account_created ON core_banking.ledger_entries (account_id, created_at DESC);
CREATE INDEX idx_ledger_transaction_id ON core_banking.ledger_entries (transaction_id);

-- ============================================================================
-- TABLE 7: AUDIT LOGS
-- ============================================================================
CREATE TABLE audit_system.audit_logs (
    log_id BIGSERIAL PRIMARY KEY,
    actor_id UUID,
    actor_role VARCHAR(50) NOT NULL,
    action VARCHAR(100) NOT NULL,
    entity_name VARCHAR(100) NOT NULL,
    entity_id VARCHAR(128) NOT NULL,
    old_state JSONB,
    new_state JSONB,
    ip_address INET,
    user_agent TEXT,
    log_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    previous_hash CHAR(64) NOT NULL,
    current_hash CHAR(64) NOT NULL,
    
    CONSTRAINT chk_hash_length CHECK (LENGTH(previous_hash) = 64 AND LENGTH(current_hash) = 64)
);

CREATE INDEX idx_audit_logs_entity ON audit_system.audit_logs (entity_name, entity_id);
CREATE INDEX idx_audit_logs_jsonb_gin ON audit_system.audit_logs USING GIN (new_state);
