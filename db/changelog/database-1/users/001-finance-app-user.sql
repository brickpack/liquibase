--liquibase formatted sql

--changeset user-management:create-finance_app-user
--comment: Create user finance_app for Oracle
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username = UPPER('finance_app')
CREATE USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP
    QUOTA 500M ON FINANCE_DATA
    PROFILE DEFAULT
    ACCOUNT UNLOCK;

--changeset user-management:grant-finance_app-system-privileges
--comment: Grant system privileges to finance_app
--runOnChange:true
-- Grant system privileges (customize based on role)
GRANT CREATE SESSION TO finance_app;
GRANT CREATE TABLE TO finance_app;
GRANT CREATE SEQUENCE TO finance_app;
GRANT CREATE TRIGGER TO finance_app;

--changeset user-management:grant-finance_app-object-privileges
--comment: Grant object privileges to finance_app
--runOnChange:true
-- Grant object privileges (customize based on role)
GRANT SELECT, INSERT, UPDATE, DELETE ON accounts TO finance_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON transactions TO finance_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON transaction_details TO finance_app;
GRANT SELECT ON account_balance_view TO finance_app;

--changeset user-management:grant-finance_app-roles
--comment: Grant roles to finance_app
--runOnChange:true
-- Grant predefined roles (customize based on role)
-- No predefined roles needed for this user

--changeset user-management:create-finance_app-comment
--comment: Add comment to finance_app user for documentation
COMMENT ON USER finance_app IS 'Finance application service account with read/write access to finance schema';