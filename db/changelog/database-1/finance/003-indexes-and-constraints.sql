--liquibase formatted sql

--changeset finance-team:003-create-accounts-indexes
--comment: Create performance indexes for accounts table (skip if Oracle auto-created for UNIQUE constraint)
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_ind_columns WHERE table_name = 'ACCOUNTS' AND column_name = 'ACCOUNT_CODE'
-- Skip creating index - Oracle automatically creates index for UNIQUE constraint
-- If needed later, use: CREATE INDEX idx_accounts_code ON accounts(account_code) TABLESPACE FINANCE_DATA;

--changeset finance-team:003-create-accounts-type-index
--comment: Create index for account type lookups
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_indexes WHERE index_name = 'IDX_ACCOUNTS_TYPE'
CREATE INDEX idx_accounts_type ON accounts(account_type, is_active) TABLESPACE FINANCE_DATA;

--changeset finance-team:003-create-transactions-date-index
--comment: Create index for transaction date queries
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_indexes WHERE index_name = 'IDX_TRANSACTIONS_DATE'
CREATE INDEX idx_transactions_date ON transactions(transaction_date, status) TABLESPACE FINANCE_DATA;

--changeset finance-team:003-create-transactions-reference-index
--comment: Create index for reference number lookups (skip if Oracle auto-created for UNIQUE constraint)
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_ind_columns WHERE table_name = 'TRANSACTIONS' AND column_name = 'REFERENCE_NUMBER'
-- Skip creating index - Oracle automatically creates index for UNIQUE constraint
-- If needed later, use: CREATE INDEX idx_transactions_ref ON transactions(reference_number) TABLESPACE FINANCE_DATA;

--changeset finance-team:003-create-transaction-details-account-index
--comment: Create index for account-based queries
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_indexes WHERE index_name = 'IDX_TRANS_DETAILS_ACCOUNT'
CREATE INDEX idx_trans_details_account ON transaction_details(account_id, transaction_id) TABLESPACE FINANCE_DATA;

--changeset finance-team:003-create-balanced-transaction-constraint
--comment: Create constraint to ensure transactions are balanced
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_constraints WHERE constraint_name = 'CHK_TRANSACTION_BALANCED'
ALTER TABLE transactions ADD CONSTRAINT chk_transaction_balanced
CHECK (transaction_id IN (
    SELECT transaction_id
    FROM transaction_details
    GROUP BY transaction_id
    HAVING SUM(debit_amount) = SUM(credit_amount)
)) DEFERRABLE INITIALLY DEFERRED;

--changeset finance-team:003-create-account-balance-view
--comment: Create view for account balances
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_views WHERE view_name = 'ACCOUNT_BALANCES'
CREATE OR REPLACE VIEW account_balances AS
SELECT
    a.account_id,
    a.account_code,
    a.account_name,
    a.account_type,
    NVL(SUM(td.debit_amount), 0) - NVL(SUM(td.credit_amount), 0) AS balance,
    COUNT(td.detail_id) AS transaction_count,
    MAX(t.transaction_date) AS last_transaction_date
FROM accounts a
LEFT JOIN transaction_details td ON a.account_id = td.account_id
LEFT JOIN transactions t ON td.transaction_id = t.transaction_id
    AND t.status = 'POSTED'
WHERE a.is_active = 'Y'
GROUP BY a.account_id, a.account_code, a.account_name, a.account_type;

--changeset finance-team:003-create-monthly-summary-view
--comment: Create view for monthly financial summaries
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_views WHERE view_name = 'MONTHLY_SUMMARY'
CREATE OR REPLACE VIEW monthly_summary AS
SELECT
    TO_CHAR(t.transaction_date, 'YYYY-MM') AS month_year,
    a.account_type,
    SUM(td.debit_amount) AS total_debits,
    SUM(td.credit_amount) AS total_credits,
    COUNT(DISTINCT t.transaction_id) AS transaction_count
FROM transactions t
JOIN transaction_details td ON t.transaction_id = td.transaction_id
JOIN accounts a ON td.account_id = a.account_id
WHERE t.status = 'POSTED'
GROUP BY TO_CHAR(t.transaction_date, 'YYYY-MM'), a.account_type
ORDER BY month_year DESC, a.account_type;