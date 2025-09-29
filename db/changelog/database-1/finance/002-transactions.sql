--liquibase formatted sql

--changeset finance-team:002-create-transactions-table
--comment: Create financial transactions table
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_tables WHERE table_name = 'TRANSACTIONS'
CREATE TABLE transactions (
    transaction_id NUMBER(15) PRIMARY KEY,
    transaction_date DATE NOT NULL,
    reference_number VARCHAR2(50) UNIQUE NOT NULL,
    description VARCHAR2(500) NOT NULL,
    total_amount NUMBER(15,2) NOT NULL,
    currency_code CHAR(3) DEFAULT 'USD',
    transaction_type VARCHAR2(20) NOT NULL CHECK (transaction_type IN ('DEBIT', 'CREDIT', 'TRANSFER')),
    status VARCHAR2(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'POSTED', 'CANCELLED')),
    created_date DATE DEFAULT SYSDATE,
    created_by VARCHAR2(100) DEFAULT USER,
    approved_date DATE,
    approved_by VARCHAR2(100),
    posted_date DATE
) TABLESPACE FINANCE_DATA;

--changeset finance-team:002-create-transaction-sequence
--comment: Create sequence for transaction IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_sequences WHERE sequence_name = 'TRANSACTIONS_SEQ'
CREATE SEQUENCE transactions_seq
    START WITH 100000
    INCREMENT BY 1
    CACHE 100
    NOCYCLE;

--changeset finance-team:002-create-transaction-trigger splitStatements:false
--comment: Create trigger for auto-incrementing transaction IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_triggers WHERE trigger_name = 'TRANSACTIONS_TRG'
CREATE OR REPLACE TRIGGER transactions_trg
    BEFORE INSERT ON transactions
    FOR EACH ROW
BEGIN
    IF :NEW.transaction_id IS NULL THEN
        :NEW.transaction_id := transactions_seq.NEXTVAL;
    END IF;

    -- Auto-generate reference number if not provided
    IF :NEW.reference_number IS NULL THEN
        :NEW.reference_number := 'TXN-' || TO_CHAR(SYSDATE, 'YYYYMMDD') || '-' || LPAD(transactions_seq.CURRVAL, 6, '0');
    END IF;
END;
/

--changeset finance-team:002-create-transaction-details-table
--comment: Create transaction line items table
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_tables WHERE table_name = 'TRANSACTION_DETAILS'
CREATE TABLE transaction_details (
    detail_id NUMBER(15) PRIMARY KEY,
    transaction_id NUMBER(15) NOT NULL,
    account_id NUMBER(10) NOT NULL,
    debit_amount NUMBER(15,2) DEFAULT 0,
    credit_amount NUMBER(15,2) DEFAULT 0,
    description VARCHAR2(255),
    line_number NUMBER(3) NOT NULL,
    CONSTRAINT fk_trans_detail_trans FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id) ON DELETE CASCADE,
    CONSTRAINT fk_trans_detail_account FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    CONSTRAINT chk_debit_or_credit CHECK ((debit_amount > 0 AND credit_amount = 0) OR (credit_amount > 0 AND debit_amount = 0))
) TABLESPACE FINANCE_DATA;

--changeset finance-team:002-create-transaction-details-sequence
--comment: Create sequence for transaction detail IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_sequences WHERE sequence_name = 'TRANSACTION_DETAILS_SEQ'
CREATE SEQUENCE transaction_details_seq
    START WITH 1
    INCREMENT BY 1
    CACHE 100
    NOCYCLE;

--changeset finance-team:002-create-transaction-details-trigger splitStatements:false
--comment: Create trigger for auto-incrementing transaction detail IDs
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM user_triggers WHERE trigger_name = 'TRANSACTION_DETAILS_TRG'
CREATE OR REPLACE TRIGGER transaction_details_trg
    BEFORE INSERT ON transaction_details
    FOR EACH ROW
BEGIN
    IF :NEW.detail_id IS NULL THEN
        :NEW.detail_id := transaction_details_seq.NEXTVAL;
    END IF;
END;
/