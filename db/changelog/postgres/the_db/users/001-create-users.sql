--liquibase formatted sql

--changeset db-admin:001
--comment: Create read-write user for application
CREATE USER app_readwrite WITH PASSWORD 'CHANGE_ME_TEMP_PASSWORD';
GRANT CONNECT ON DATABASE the_db TO app_readwrite;
GRANT USAGE ON SCHEMA public TO app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_readwrite;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO app_readwrite;

--changeset db-admin:002
--comment: Create read-only user for reporting
CREATE USER app_readonly WITH PASSWORD 'CHANGE_ME_TEMP_PASSWORD';
GRANT CONNECT ON DATABASE the_db TO app_readonly;
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_readonly;
