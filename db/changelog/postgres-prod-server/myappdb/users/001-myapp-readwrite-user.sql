--liquibase formatted sql

--changeset DM-7001:001
--comment: Create myapp_readwrite user for PostgreSQL
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_user WHERE usename = 'myapp_readwrite'
-- Note: Password will be set separately by manage-users.sh script
CREATE USER myapp_readwrite WITH PASSWORD 'TemporaryPassword123';

--changeset DM-7002:002
--comment: Grant database connection privileges to myapp_readwrite
--runOnChange:true
GRANT CONNECT ON DATABASE myappdb TO myapp_readwrite;

--changeset DM-7003:003
--comment: Grant schema usage to myapp_readwrite
--runOnChange:true
GRANT USAGE ON SCHEMA public TO myapp_readwrite;

--changeset DM-7004:004
--comment: Grant table privileges to myapp_readwrite
--runOnChange:true
-- Grant SELECT, INSERT, UPDATE, DELETE on all existing tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myapp_readwrite;

-- Grant privileges on future tables (requires PostgreSQL 9.0+)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO myapp_readwrite;

--changeset DM-7005:005
--comment: Grant sequence privileges to myapp_readwrite
--runOnChange:true
-- Grant USAGE on all existing sequences (for serial/bigserial columns)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO myapp_readwrite;

-- Grant privileges on future sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO myapp_readwrite;

--changeset DM-7006:006
--comment: Grant function execution privileges to myapp_readwrite
--runOnChange:true
-- Grant EXECUTE on all existing functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO myapp_readwrite;

-- Grant privileges on future functions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO myapp_readwrite;
