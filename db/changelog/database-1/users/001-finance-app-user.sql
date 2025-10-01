--liquibase formatted sql

--changeset DM-6001:001
--comment: Create user finance_app for Oracle
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username = UPPER('finance_app')
CREATE USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP
    QUOTA 500M ON FINANCE_DATA
    PROFILE DEFAULT
    ACCOUNT UNLOCK;

--changeset DM-6002:002
--comment: Grant system privileges to finance_app
--runOnChange:true
-- Grant system privileges (customize based on role)
GRANT CREATE SESSION TO finance_app;
GRANT CREATE TABLE TO finance_app;
GRANT CREATE SEQUENCE TO finance_app;
GRANT CREATE TRIGGER TO finance_app;

--changeset DM-6003:003
--comment: Grant object privileges to finance_app
--runOnChange:true
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_tables WHERE table_name = 'ACCOUNTS'
-- Grant object privileges (customize based on schema - update SCHEMA_NAME)
-- Note: Replace these with actual schema owner or remove if objects don't exist yet
-- GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA_NAME.accounts TO finance_app;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA_NAME.transactions TO finance_app;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA_NAME.transaction_details TO finance_app;
-- GRANT SELECT ON SCHEMA_NAME.account_balance_view TO finance_app;
-- For now, grant basic connection privileges only
NULL;

--changeset DM-6004:004
--comment: Grant roles to finance_app
--runOnChange:true
-- Grant predefined roles (customize based on role)
-- No predefined roles needed for this user

--changeset DM-6005:005
--comment: Add comment to finance_app user for documentation
COMMENT ON USER finance_app IS 'Finance application service account with read/write access to finance schema';