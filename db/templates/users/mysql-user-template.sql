--liquibase formatted sql

--changeset user-management:create-{{USERNAME}}-user
--comment: Create user {{USERNAME}} for MySQL
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM mysql.user WHERE User = '{{USERNAME}}' AND Host = '{{HOST_PATTERN}}'
CREATE USER '{{USERNAME}}'@'{{HOST_PATTERN}}' IDENTIFIED BY '{{PASSWORD:{{USERNAME}}}}';

--changeset user-management:grant-{{USERNAME}}-privileges
--comment: Grant privileges to {{USERNAME}}
--runOnChange:true
-- Grant database privileges (customize based on role)
{{DATABASE_PRIVILEGES}}

-- Flush privileges to ensure changes take effect
FLUSH PRIVILEGES;

--changeset user-management:create-{{USERNAME}}-comment
--comment: Add comment for {{USERNAME}} user documentation
-- User: {{USERNAME}}
-- Role: {{ROLE_DESCRIPTION}}
-- Host Pattern: {{HOST_PATTERN}}
-- Created: {{CREATION_DATE}}