-- ============================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3: Transactions & Concurrency
-- Case Study: ApexPay Bank / Fintech Platform
-- Student Name: Ifenna Victor Okany | ID: 301923302
-- Demonstrations: ACID Properties, Strict Row-Level Locking, SAVEPOINTS, Idempotency
-- ============================================================================

-- ============================================================================
-- DEMO 1: Production Peer-to-Peer Inter-Account Fund Transfer Procedure
-- Features: Explicit BEGIN, Pessimistic Row Locking (FOR UPDATE) in deterministic
-- order to prevent deadlocks, balance validation, double-entry ledger insertion,
-- and atomic COMMIT.
-- ============================================================================
CREATE OR REPLACE PROCEDURE core_banking.sp_execute_p2p_transfer(
    p_idempotency_key VARCHAR(128),
    p_source_account_id UUID,
    p_destination_account_id UUID,
    p_transfer_amount NUMERIC(18, 4),
    p_fee_amount NUMERIC(18, 4),
    p_narration VARCHAR(255),
    INOUT p_transaction_reference VARCHAR(64) DEFAULT NULL,
    INOUT p_status VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_source_balance NUMERIC(18, 4);
    v_dest_balance NUMERIC(18, 4);
    v_net_amount NUMERIC(18, 4);
    v_first_lock_id UUID;
    v_second_lock_id UUID;
    v_txn_id UUID;
    v_source_acc_status core_banking.account_status_enum;
    v_dest_acc_status core_banking.account_status_enum;
BEGIN
    -- 1. Check for duplicate execution via Idempotency Key
    SELECT transaction_reference, status::VARCHAR
    INTO p_transaction_reference, p_status
    FROM core_banking.transactions
    WHERE idempotency_key = p_idempotency_key;

    IF FOUND THEN
        -- Idempotent exit: transaction already received and processed
        RETURN;
    END IF;

    -- Validate input sanity
    IF p_transfer_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be strictly positive.';
    END IF;

    IF p_source_account_id = p_destination_account_id THEN
        RAISE EXCEPTION 'Source and Destination accounts cannot be identical.';
    END IF;

    v_net_amount := p_transfer_amount - p_fee_amount;

    -- 2. Prevent Deadlocks: Enforce deterministic locking order by UUID comparison
    IF p_source_account_id < p_destination_account_id THEN
        v_first_lock_id := p_source_account_id;
        v_second_lock_id := p_destination_account_id;
    ELSE
        v_first_lock_id := p_destination_account_id;
        v_second_lock_id := p_source_account_id;
    END IF;

    -- Acquire exclusive row-level locks
    PERFORM 1 FROM core_banking.accounts WHERE account_id = v_first_lock_id FOR UPDATE;
    PERFORM 1 FROM core_banking.accounts WHERE account_id = v_second_lock_id FOR UPDATE;

    -- 3. Verify Source Account State & Funds
    SELECT available_balance, status 
    INTO v_source_balance, v_source_acc_status
    FROM core_banking.accounts
    WHERE account_id = p_source_account_id;

    IF v_source_acc_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Source account is not active. Current status: %', v_source_acc_status;
    END IF;

    IF v_source_balance < p_transfer_amount THEN
        RAISE EXCEPTION 'Insufficient funds: Available %, Required %', v_source_balance, p_transfer_amount;
    END IF;

    -- Verify Destination Account State
    SELECT status 
    INTO v_dest_acc_status
    FROM core_banking.accounts
    WHERE account_id = p_destination_account_id;

    IF v_dest_acc_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Destination account is not active. Current status: %', v_dest_acc_status;
    END IF;

    -- 4. Generate Unique Transaction Reference
    p_transaction_reference := 'TXN-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS') || '-' || SUBSTRING(gen_random_uuid()::TEXT FROM 1 FOR 8);
    v_txn_id := gen_random_uuid();

    -- 5. Insert Parent Master Transaction Record
    INSERT INTO core_banking.transactions (
        transaction_id,
        transaction_reference,
        idempotency_key,
        source_account_id,
        destination_account_id,
        transaction_type,
        gross_amount,
        fee_amount,
        net_amount,
        currency,
        status,
        narration,
        initiated_at,
        completed_at
    ) VALUES (
        v_txn_id,
        p_transaction_reference,
        p_idempotency_key,
        p_source_account_id,
        p_destination_account_id,
        'TRANSFER',
        p_transfer_amount,
        p_fee_amount,
        v_net_amount,
        'NGN',
        'COMPLETED',
        p_narration,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    );

    -- 6. Execute Balanced Double-Entry Postings
    -- 6a. DEBIT Source Account
    UPDATE core_banking.accounts
    SET available_balance = available_balance - p_transfer_amount,
        ledger_balance = ledger_balance - p_transfer_amount,
        row_version = row_version + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = p_source_account_id
    RETURNING available_balance INTO v_source_balance;

    INSERT INTO core_banking.ledger_entries (
        transaction_id,
        account_id,
        entry_type,
        amount,
        running_balance_after
    ) VALUES (
        v_txn_id,
        p_source_account_id,
        'DEBIT',
        p_transfer_amount,
        v_source_balance
    );

    -- 6b. CREDIT Destination Account
    UPDATE core_banking.accounts
    SET available_balance = available_balance + v_net_amount,
        ledger_balance = ledger_balance + v_net_amount,
        row_version = row_version + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = p_destination_account_id
    RETURNING available_balance INTO v_dest_balance;

    INSERT INTO core_banking.ledger_entries (
        transaction_id,
        account_id,
        entry_type,
        amount,
        running_balance_after
    ) VALUES (
        v_txn_id,
        p_destination_account_id,
        'CREDIT',
        v_net_amount,
        v_dest_balance
    );

    p_status := 'COMPLETED';
END;
$$;


-- ============================================================================
-- DEMO 2: Batch Corporate Payroll with SAVEPOINTs (Partial Rollback)
-- Features: Demonstrates BEGIN, iterative debit processing, SAVEPOINT creation,
-- conditional ROLLBACK TO SAVEPOINT on failure, and global COMMIT.
-- ============================================================================
DO $$
DECLARE
    v_corporate_acc_id UUID;
    v_employee_rec RECORD;
    v_payroll_batch_id VARCHAR(64) := 'BATCH-PAYROLL-202611';
    v_success_count INT := 0;
    v_failure_count INT := 0;
BEGIN
    SELECT account_id INTO v_corporate_acc_id 
    FROM core_banking.accounts 
    LIMIT 1;

    RAISE NOTICE 'Starting Payroll Processing for Batch %', v_payroll_batch_id;

    -- Temporary table of employees scheduled for payment
    CREATE TEMP TABLE tmp_payroll_queue (
        emp_acc_id UUID,
        salary_amount NUMERIC(18, 4),
        emp_name VARCHAR(100)
    ) ON COMMIT DROP;

    INSERT INTO tmp_payroll_queue VALUES 
    ('11111111-1111-1111-1111-111111111111'::UUID, 250000.00, 'Amina Bello'),
    ('22222222-2222-2222-2222-222222222222'::UUID, 320000.00, 'Chukwudi Okafor'),
    ('99999999-9999-9999-9999-999999999999'::UUID, 180000.00, 'Invalid Account / Frozen');

    FOR v_employee_rec IN SELECT * FROM tmp_payroll_queue LOOP
        BEGIN
            -- Set Savepoint for isolated employee processing
            SAVEPOINT sp_individual_payroll;

            CALL core_banking.sp_execute_p2p_transfer(
                p_idempotency_key := v_payroll_batch_id || '-' || v_employee_rec.emp_acc_id::TEXT,
                p_source_account_id := v_corporate_acc_id,
                p_destination_account_id := v_employee_rec.emp_acc_id,
                p_transfer_amount := v_employee_rec.salary_amount,
                p_fee_amount := 0.0000,
                p_narration := 'Monthly Salary'
            );

            v_success_count := v_success_count + 1;
            RELEASE SAVEPOINT sp_individual_payroll;
            RAISE NOTICE 'Payment succeeded for %', v_employee_rec.emp_name;

        EXCEPTION WHEN OTHERS THEN
            -- Rollback solely the failed individual without breaking entire batch
            ROLLBACK TO SAVEPOINT sp_individual_payroll;
            v_failure_count := v_failure_count + 1;
            RAISE WARNING 'Payroll failed for employee %. Reason: %', v_employee_rec.emp_name, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Payroll Completed: % Successes, % Failures', v_success_count, v_failure_count;
END $$;
