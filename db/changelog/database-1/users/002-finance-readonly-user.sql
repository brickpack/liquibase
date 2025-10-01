--liquibase formatted sql

--changeset DM-6006:006
--comment: Create user finance_readonly for Oracle
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username = UPPER('finance_readonly')
CREATE USER finance_readonly IDENTIFIED BY "{{PASSWORD:finance_readonly}}"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    QUOTA 10M ON USERS
    PROFILE DEFAULT
    ACCOUNT UNLOCK;

--changeset DM-6007:007
--comment: Grant system privileges to finance_readonly
--runOnChange:true
-- Grant system privileges (customize based on role)
GRANT CREATE SESSION TO finance_readonly;

--changeset DM-6008:008
--comment: Grant object privileges to finance_readonly (currently skipped - configure schema owner if needed)
--runOnChange:true
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_tables WHERE table_name = 'ACCOUNTS'
-- This changeset is currently disabled via precondition
-- Object privileges can be granted manually or configure schema owner in future changesets
SELECT 1 FROM DUAL;

--changeset DM-6009:009
--comment: Grant roles to finance_readonly
--runOnChange:true
-- Grant predefined roles (customize based on role)
-- Could grant CONNECT role if desired
-- GRANT CONNECT TO finance_readonly;

--changeset DM-6010:010
--comment: Document finance_readonly user (Oracle does not support COMMENT ON USER)
-- User: finance_readonly
-- Purpose: Read-only access for reporting and analytics on finance data
-- Documented in code comments only since Oracle does not support user comments
SELECT 1 FROM DUAL;