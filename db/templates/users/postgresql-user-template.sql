--liquibase formatted sql

--changeset user-management:create-{{USERNAME}}-role
--comment: Create role {{USERNAME}} for PostgreSQL
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_roles WHERE rolname = '{{USERNAME}}'
CREATE ROLE "{{USERNAME}}" WITH
    LOGIN
    PASSWORD '{{PASSWORD:{{USERNAME}}}}'
    {{ADDITIONAL_OPTIONS}};

--changeset user-management:grant-{{USERNAME}}-privileges
--comment: Grant privileges to {{USERNAME}}
--runOnChange:true
-- Grant database connection
GRANT CONNECT ON DATABASE {{DATABASE_NAME}} TO "{{USERNAME}}";

-- Grant schema usage (customize as needed)
GRANT USAGE ON SCHEMA {{SCHEMA_NAME}} TO "{{USERNAME}}";

-- Grant table privileges (customize based on role)
{{TABLE_PRIVILEGES}}

-- Grant sequence privileges if needed
{{SEQUENCE_PRIVILEGES}}

--changeset user-management:create-{{USERNAME}}-comment
--comment: Add comment to {{USERNAME}} role for documentation
COMMENT ON ROLE "{{USERNAME}}" IS '{{ROLE_DESCRIPTION}}';