-- ============================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2: Query Optimisation
-- Case Study: ApexPay Bank / Fintech Platform
-- Student Name: Ifenna Victor Okany | ID: 301923302
-- Advanced SQL: Multi-Table Joins, CTEs, Window Functions, and Fraud Detection
-- ============================================================================

-- ----------------------------------------------------------------------------
-- QUERY 1: High-Frequency Transfer Reconciliation & Multi-Table Balance Audit
-- Purpose: Identifies accounts where the cached available balance diverges from
-- the computed sum of double-entry ledger postings by > 0.0001 currency units.
-- Demonstrates: Multi-table JOINs, conditional aggregation, and COALESCE.
-- ----------------------------------------------------------------------------
SELECT 
    acc.account_id,
    acc.account_number,
    c.first_name || ' ' || c.last_name AS customer_full_name,
    c.email,
    acc.currency,
    acc.available_balance AS cached_available_balance,
    acc.ledger_balance AS cached_ledger_balance,
    COALESCE(SUM(
        CASE 
            WHEN le.entry_type = 'CREDIT' THEN le.amount
            WHEN le.entry_type = 'DEBIT' THEN -le.amount
            ELSE 0.0000 
        END
    ), 0.0000) AS audited_calculated_balance,
    ABS(acc.ledger_balance - COALESCE(SUM(
        CASE 
            WHEN le.entry_type = 'CREDIT' THEN le.amount
            WHEN le.entry_type = 'DEBIT' THEN -le.amount
            ELSE 0.0000 
        END
    ), 0.0000)) AS discrepancy_variance
FROM core_banking.accounts acc
INNER JOIN core_banking.customers c 
    ON acc.customer_id = c.customer_id
LEFT JOIN core_banking.ledger_entries le 
    ON acc.account_id = le.account_id
WHERE acc.status IN ('ACTIVE', 'DORMANT')
GROUP BY 
    acc.account_id,
    acc.account_number,
    c.first_name,
    c.last_name,
    c.email,
    acc.currency,
    acc.available_balance,
    acc.ledger_balance
HAVING ABS(acc.ledger_balance - COALESCE(SUM(
    CASE 
        WHEN le.entry_type = 'CREDIT' THEN le.amount
        WHEN le.entry_type = 'DEBIT' THEN -le.amount
        ELSE 0.0000 
    END
), 0.0000)) > 0.0001
ORDER BY discrepancy_variance DESC;


-- ----------------------------------------------------------------------------
-- QUERY 2: Rolling 30-Day Customer Transaction Velocity & KYC Limit Utilization
-- Purpose: Computes rolling 30-day cumulative spending, peak single transactions,
-- and ranking within customer KYC tiers to trigger proactive limit increases or AML alerts.
-- Demonstrates: Window functions (SUM, AVG, MAX, DENSE_RANK) with frame specifications.
-- ----------------------------------------------------------------------------
WITH CustomerDailyMetrics AS (
    SELECT 
        c.customer_id,
        c.first_name || ' ' || c.last_name AS customer_name,
        c.kyc_tier,
        t.initiated_at::DATE AS transaction_date,
        COUNT(t.transaction_id) AS daily_tx_count,
        SUM(t.gross_amount) AS daily_total_outflow,
        MAX(t.gross_amount) AS max_single_outflow
    FROM core_banking.customers c
    INNER JOIN core_banking.accounts a 
        ON c.customer_id = a.customer_id
    INNER JOIN core_banking.transactions t 
        ON a.account_id = t.source_account_id
    WHERE t.status = 'COMPLETED'
      AND t.initiated_at >= (CURRENT_TIMESTAMP - INTERVAL '90 days')
    GROUP BY 
        c.customer_id, 
        c.first_name, 
        c.last_name, 
        c.kyc_tier, 
        t.initiated_at::DATE
)
SELECT 
    customer_id,
    customer_name,
    kyc_tier,
    transaction_date,
    daily_tx_count,
    daily_total_outflow,
    -- 30-day rolling aggregate window
    SUM(daily_total_outflow) OVER (
        PARTITION BY customer_id 
        ORDER BY transaction_date 
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30day_total_spend,
    AVG(daily_total_outflow) OVER (
        PARTITION BY customer_id 
        ORDER BY transaction_date 
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30day_avg_daily_spend,
    -- Rank customers within their KYC tier by highest 30-day rolling total spend
    DENSE_RANK() OVER (
        PARTITION BY kyc_tier 
        ORDER BY SUM(daily_total_outflow) OVER (
            PARTITION BY customer_id 
            ORDER BY transaction_date 
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) DESC
    ) AS tier_spend_rank
FROM CustomerDailyMetrics
ORDER BY kyc_tier, tier_spend_rank, transaction_date DESC;


-- ----------------------------------------------------------------------------
-- QUERY 3: Multi-Hop Recursive Fraud Ring & Rapid Fund Dispersion Detection
-- Purpose: Identifies rapid fund movement (mule accounts) where funds are transferred
-- across 3 or more intermediate accounts within 6 hours of initial receipt.
-- Demonstrates: Advanced Recursive Common Table Expressions (rCTEs).
-- ----------------------------------------------------------------------------
WITH RECURSIVE TransferChain AS (
    -- Anchor member: Starting transfers of high value (>= 1,000,000)
    SELECT 
        t.transaction_id,
        t.source_account_id,
        t.destination_account_id,
        t.gross_amount,
        t.initiated_at,
        1 AS hop_depth,
        ARRAY[t.source_account_id, t.destination_account_id] AS account_path,
        t.source_account_id AS root_source_account
    FROM core_banking.transactions t
    WHERE t.status = 'COMPLETED'
      AND t.transaction_type = 'TRANSFER'
      AND t.gross_amount >= 1000000.0000
      AND t.initiated_at >= (CURRENT_TIMESTAMP - INTERVAL '7 days')

    UNION ALL

    -- Recursive member: Successive transfers where recipient transfers money onwards within 6 hours
    SELECT 
        next_tx.transaction_id,
        next_tx.source_account_id,
        next_tx.destination_account_id,
        next_tx.gross_amount,
        next_tx.initiated_at,
        tc.hop_depth + 1,
        tc.account_path || next_tx.destination_account_id,
        tc.root_source_account
    FROM core_banking.transactions next_tx
    INNER JOIN TransferChain tc 
        ON next_tx.source_account_id = tc.destination_account_id
    WHERE next_tx.status = 'COMPLETED'
      AND next_tx.transaction_type = 'TRANSFER'
      AND next_tx.initiated_at > tc.initiated_at
      AND next_tx.initiated_at <= (tc.initiated_at + INTERVAL '6 hours')
      AND tc.hop_depth < 5 -- Guard against circular infinite recursion
      AND NOT (next_tx.destination_account_id = ANY(tc.account_path)) -- Prevent cycles
)
SELECT 
    root_source_account,
    hop_depth,
    gross_amount AS last_hop_amount,
    account_path,
    initiated_at AS last_hop_timestamp
FROM TransferChain
WHERE hop_depth >= 3
ORDER BY hop_depth DESC, gross_amount DESC;


-- ----------------------------------------------------------------------------
-- QUERY 4: Monthly Ledger Inactivity, Dormancy Risk, and Cash-Flow Profiling
-- Purpose: Uses LAG to detect dormancy intervals and calculates cumulative inflows/outflows.
-- Demonstrates: LAG(), LEAD(), and multi-dimensional analysis.
-- ----------------------------------------------------------------------------
WITH MonthlyAccountFlows AS (
    SELECT 
        DATE_TRUNC('month', le.created_at) AS report_month,
        a.account_number,
        c.customer_id,
        c.kyc_tier,
        SUM(CASE WHEN le.entry_type = 'CREDIT' THEN le.amount ELSE 0 END) AS total_inflow,
        SUM(CASE WHEN le.entry_type = 'DEBIT' THEN le.amount ELSE 0 END) AS total_outflow
    FROM core_banking.accounts a
    INNER JOIN core_banking.customers c ON a.customer_id = c.customer_id
    INNER JOIN core_banking.ledger_entries le ON a.account_id = le.account_id
    WHERE le.created_at >= (CURRENT_TIMESTAMP - INTERVAL '12 months')
    GROUP BY DATE_TRUNC('month', le.created_at), a.account_number, c.customer_id, c.kyc_tier
)
SELECT 
    report_month,
    account_number,
    kyc_tier,
    total_inflow,
    total_outflow,
    LAG(total_inflow, 1, 0.0000) OVER (
        PARTITION BY account_number 
        ORDER BY report_month
    ) AS previous_month_inflow,
    total_inflow - LAG(total_inflow, 1, 0.0000) OVER (
        PARTITION BY account_number 
        ORDER BY report_month
    ) AS month_over_month_inflow_delta,
    CASE 
        WHEN LAG(total_inflow, 1, 0.0000) OVER (PARTITION BY account_number ORDER BY report_month) = 0 
             AND total_inflow = 0 THEN 'CHRONICALLY_DORMANT'
        WHEN total_inflow < 0.20 * LAG(total_inflow, 1, 0.0000) OVER (PARTITION BY account_number ORDER BY report_month) THEN 'RAPID_DECLINE'
        ELSE 'STABLE_OR_GROWING'
    END AS activity_velocity_status
FROM MonthlyAccountFlows
ORDER BY account_number, report_month DESC;
