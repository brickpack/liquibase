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
--comment: Grant object privileges to finance_app (currently skipped - configure schema owner if needed)
--runOnChange:true
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_tables WHERE table_name = 'ACCOUNTS'
-- This changeset is currently disabled via precondition
-- Object privileges can be granted manually or configure schema owner in future changesets
SELECT 1 FROM DUAL;

--changeset DM-6004:004
--comment: Grant roles to finance_app
--runOnChange:true
-- Grant predefined roles (customize based on role)
-- No predefined roles needed for this user

--changeset DM-6005:005
--comment: Document finance_app user (Oracle does not support COMMENT ON USER)
-- User: finance_app
-- Purpose: Finance application service account with read/write access to finance schema
-- Documented in code comments only since Oracle does not support user comments
SELECT 1 FROM DUAL;

--changeset DM-6011:011
--comment: Reset finance_app password (use for password rotation)
--runOnChange:true
ALTER USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}";