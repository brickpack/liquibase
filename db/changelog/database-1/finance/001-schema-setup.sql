--liquibase formatted sql

--changeset finance-team:001-create-tablespace
--comment: Create dedicated tablespace for finance data
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_tablespaces WHERE tablespace_name = 'FINANCE_DATA'
CREATE TABLESPACE FINANCE_DATA;

--changeset finance-team:001-create-accounts-table
--comment: Create chart of accounts table
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_tables WHERE table_name = 'ACCOUNTS'
CREATE TABLE accounts (
    account_id NUMBER(10) PRIMARY KEY,
    account_code VARCHAR2(20) UNIQUE NOT NULL,
    account_name VARCHAR2(255) NOT NULL,
    account_type VARCHAR2(50) NOT NULL,
    parent_account_id NUMBER(10),
    is_active CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y','N')),
    created_date DATE DEFAULT SYSDATE,
    created_by VARCHAR2(100) DEFAULT USER,
    CONSTRAINT fk_parent_account FOREIGN KEY (parent_account_id) REFERENCES accounts(account_id)
) TABLESPACE FINANCE_DATA;

--changeset finance-team:001-create-account-sequence
--comment: Create sequence for account IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_sequences WHERE sequence_name = 'ACCOUNTS_SEQ'
CREATE SEQUENCE accounts_seq
    START WITH 1000
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

--changeset finance-team:001-create-account-trigger splitStatements:false
--comment: Create trigger for auto-incrementing account IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_triggers WHERE trigger_name = 'ACCOUNTS_TRG'
CREATE OR REPLACE TRIGGER accounts_trg
    BEFORE INSERT ON accounts
    FOR EACH ROW
BEGIN
    IF :NEW.account_id IS NULL THEN
        :NEW.account_id := accounts_seq.NEXTVAL;
    END IF;
END;
/