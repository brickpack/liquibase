--liquibase formatted sql

--changeset DM-5004-insert-standard-account-types
--comment: Insert standard chart of accounts
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM accounts WHERE account_code IN ('1000', '2000', '3000', '4000', '5000')

-- Assets
INSERT INTO accounts (account_code, account_name, account_type, is_active)
VALUES ('1000', 'Current Assets', 'ASSET', 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('1100', 'Cash and Cash Equivalents', 'ASSET',
        (SELECT account_id FROM accounts WHERE account_code = '1000'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('1110', 'Checking Account', 'ASSET',
        (SELECT account_id FROM accounts WHERE account_code = '1100'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('1120', 'Savings Account', 'ASSET',
        (SELECT account_id FROM accounts WHERE account_code = '1100'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('1200', 'Accounts Receivable', 'ASSET',
        (SELECT account_id FROM accounts WHERE account_code = '1000'), 'Y');

-- Liabilities
INSERT INTO accounts (account_code, account_name, account_type, is_active)
VALUES ('2000', 'Current Liabilities', 'LIABILITY', 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('2100', 'Accounts Payable', 'LIABILITY',
        (SELECT account_id FROM accounts WHERE account_code = '2000'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('2200', 'Accrued Liabilities', 'LIABILITY',
        (SELECT account_id FROM accounts WHERE account_code = '2000'), 'Y');

-- Equity
INSERT INTO accounts (account_code, account_name, account_type, is_active)
VALUES ('3000', 'Equity', 'EQUITY', 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('3100', 'Common Stock', 'EQUITY',
        (SELECT account_id FROM accounts WHERE account_code = '3000'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('3200', 'Retained Earnings', 'EQUITY',
        (SELECT account_id FROM accounts WHERE account_code = '3000'), 'Y');

-- Revenue
INSERT INTO accounts (account_code, account_name, account_type, is_active)
VALUES ('4000', 'Revenue', 'REVENUE', 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('4100', 'Sales Revenue', 'REVENUE',
        (SELECT account_id FROM accounts WHERE account_code = '4000'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('4200', 'Service Revenue', 'REVENUE',
        (SELECT account_id FROM accounts WHERE account_code = '4000'), 'Y');

-- Expenses
INSERT INTO accounts (account_code, account_name, account_type, is_active)
VALUES ('5000', 'Expenses', 'EXPENSE', 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('5100', 'Cost of Goods Sold', 'EXPENSE',
        (SELECT account_id FROM accounts WHERE account_code = '5000'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('5200', 'Operating Expenses', 'EXPENSE',
        (SELECT account_id FROM accounts WHERE account_code = '5000'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('5210', 'Salaries and Wages', 'EXPENSE',
        (SELECT account_id FROM accounts WHERE account_code = '5200'), 'Y');

INSERT INTO accounts (account_code, account_name, account_type, parent_account_id, is_active)
VALUES ('5220', 'Office Supplies', 'EXPENSE',
        (SELECT account_id FROM accounts WHERE account_code = '5200'), 'Y');

COMMIT;

--changeset DM-5004-create-audit-table
--comment: Create audit table for transaction changes
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_tables WHERE table_name = 'TRANSACTION_AUDIT'
CREATE TABLE transaction_audit (
    audit_id NUMBER(15) PRIMARY KEY,
    transaction_id NUMBER(15) NOT NULL,
    old_status VARCHAR2(20),
    new_status VARCHAR2(20),
    changed_by VARCHAR2(100) DEFAULT USER,
    change_date DATE DEFAULT SYSDATE,
    change_reason VARCHAR2(500)
) TABLESPACE FINANCE_DATA;

--changeset DM-5004-create-audit-sequence
--comment: Create sequence for audit IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_sequences WHERE sequence_name = 'TRANSACTION_AUDIT_SEQ'
CREATE SEQUENCE transaction_audit_seq
    START WITH 1
    INCREMENT BY 1
    CACHE 50
    NOCYCLE;

--changeset DM-5004-create-audit-trigger
--comment: Create audit trigger for transaction status changes
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_triggers WHERE trigger_name = 'TRANSACTIONS_AUDIT_TRG'
CREATE OR REPLACE TRIGGER transactions_audit_trg
    AFTER UPDATE OF status ON transactions
    FOR EACH ROW
    WHEN (OLD.status != NEW.status)
BEGIN
    INSERT INTO transaction_audit (
        audit_id,
        transaction_id,
        old_status,
        new_status,
        changed_by,
        change_date
    ) VALUES (
        transaction_audit_seq.NEXTVAL,
        :NEW.transaction_id,
        :OLD.status,
        :NEW.status,
        USER,
        SYSDATE
    );
END;
/