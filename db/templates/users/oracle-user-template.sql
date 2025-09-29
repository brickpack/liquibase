--liquibase formatted sql

--changeset user-management:create-{{USERNAME}}-user
--comment: Create user {{USERNAME}} for Oracle
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username = UPPER('{{USERNAME}}')
CREATE USER {{USERNAME}} IDENTIFIED BY "{{PASSWORD:{{USERNAME}}}}"
    DEFAULT TABLESPACE {{DEFAULT_TABLESPACE}}
    TEMPORARY TABLESPACE {{TEMP_TABLESPACE}}
    QUOTA {{TABLESPACE_QUOTA}} ON {{DEFAULT_TABLESPACE}}
    PROFILE {{USER_PROFILE}}
    ACCOUNT UNLOCK;

--changeset user-management:grant-{{USERNAME}}-system-privileges
--comment: Grant system privileges to {{USERNAME}}
--runOnChange:true
-- Grant system privileges (customize based on role)
{{SYSTEM_PRIVILEGES}}

--changeset user-management:grant-{{USERNAME}}-object-privileges
--comment: Grant object privileges to {{USERNAME}}
--runOnChange:true
-- Grant object privileges (customize based on role)
{{OBJECT_PRIVILEGES}}

--changeset user-management:grant-{{USERNAME}}-roles
--comment: Grant roles to {{USERNAME}}
--runOnChange:true
-- Grant predefined roles (customize based on role)
{{ROLE_GRANTS}}

--changeset user-management:create-{{USERNAME}}-comment
--comment: Add comment to {{USERNAME}} user for documentation
COMMENT ON USER {{USERNAME}} IS '{{ROLE_DESCRIPTION}}';