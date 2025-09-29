--liquibase formatted sql

--changeset user-management:create-finance_readonly-user
--comment: Create user finance_readonly for Oracle
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username = UPPER('finance_readonly')
CREATE USER finance_readonly IDENTIFIED BY "{{PASSWORD:finance_readonly}}"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    QUOTA 10M ON USERS
    PROFILE DEFAULT
    ACCOUNT UNLOCK;

--changeset user-management:grant-finance_readonly-system-privileges
--comment: Grant system privileges to finance_readonly
--runOnChange:true
-- Grant system privileges (customize based on role)
GRANT CREATE SESSION TO finance_readonly;

--changeset user-management:grant-finance_readonly-object-privileges
--comment: Grant object privileges to finance_readonly
--runOnChange:true
-- Grant object privileges (customize based on role)
GRANT SELECT ON accounts TO finance_readonly;
GRANT SELECT ON transactions TO finance_readonly;
GRANT SELECT ON transaction_details TO finance_readonly;
GRANT SELECT ON account_balance_view TO finance_readonly;
GRANT SELECT ON monthly_summary_view TO finance_readonly;

--changeset user-management:grant-finance_readonly-roles
--comment: Grant roles to finance_readonly
--runOnChange:true
-- Grant predefined roles (customize based on role)
-- Could grant CONNECT role if desired
-- GRANT CONNECT TO finance_readonly;

--changeset user-management:create-finance_readonly-comment
--comment: Add comment to finance_readonly user for documentation
COMMENT ON USER finance_readonly IS 'Read-only access for reporting and analytics on finance data';