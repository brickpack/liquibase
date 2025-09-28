--liquibase formatted sql

--changeset myapp-team:004-create-application-users splitStatements:false
--comment: Create application users for userdb
--runOnChange:false
DO $user_creation$
BEGIN
    -- Create read-only user for reporting
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'userdb_readonly') THEN
        CREATE USER userdb_readonly WITH PASSWORD 'secure_readonly_password_2024';
        COMMENT ON ROLE userdb_readonly IS 'Read-only user for reporting and analytics';
    END IF;

    -- Create application user for API access
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'userdb_api') THEN
        CREATE USER userdb_api WITH PASSWORD 'secure_api_password_2024';
        COMMENT ON ROLE userdb_api IS 'API user for application access';
    END IF;

    -- Create backup user
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'userdb_backup') THEN
        CREATE USER userdb_backup WITH PASSWORD 'secure_backup_password_2024';
        COMMENT ON ROLE userdb_backup IS 'Backup user for database backups';
    END IF;
END
$user_creation$;

--changeset myapp-team:004-grant-readonly-privileges
--comment: Grant read-only privileges to readonly user
--runOnChange:true
-- Grant schema usage
GRANT USAGE ON SCHEMA public TO userdb_readonly;

-- Grant select on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO userdb_readonly;

-- Grant select on all future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO userdb_readonly;

-- Grant usage on all existing sequences (for serial columns)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO userdb_readonly;

-- Grant usage on all future sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO userdb_readonly;

--changeset myapp-team:004-grant-api-privileges
--comment: Grant API user appropriate privileges
--runOnChange:true
-- Grant schema usage
GRANT USAGE ON SCHEMA public TO userdb_api;

-- Grant full access to main application tables
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO userdb_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON organizations TO userdb_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_organizations TO userdb_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_sessions TO userdb_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_permissions TO userdb_api;

-- Grant read access to audit table (no modifications allowed)
GRANT SELECT ON user_audit TO userdb_api;

-- Grant usage on sequences for serial/auto-increment columns
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO userdb_api;

--changeset myapp-team:004-grant-backup-privileges
--comment: Grant backup user necessary privileges
--runOnChange:true
-- Grant schema usage
GRANT USAGE ON SCHEMA public TO userdb_backup;

-- Grant select on all tables for backup purposes
GRANT SELECT ON ALL TABLES IN SCHEMA public TO userdb_backup;

-- Grant select on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO userdb_backup;

--changeset myapp-team:004-create-user-profiles-table
--comment: Create user profiles table for extended user information
CREATE TABLE IF NOT EXISTS user_profiles (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    display_name VARCHAR(200),
    bio TEXT,
    avatar_url VARCHAR(500),
    phone_number VARCHAR(20),
    timezone VARCHAR(50) DEFAULT 'UTC',
    language_preference VARCHAR(10) DEFAULT 'en',
    notification_preferences JSONB DEFAULT '{}',
    privacy_settings JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

--changeset myapp-team:004-create-user-activity-table
--comment: Create user activity tracking table
CREATE TABLE IF NOT EXISTS user_activity (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(50) NOT NULL,
    activity_description TEXT,
    ip_address INET,
    user_agent TEXT,
    session_id UUID REFERENCES user_sessions(id) ON DELETE SET NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

--changeset myapp-team:004-create-organization-invites-table
--comment: Create organization invitations table
CREATE TABLE IF NOT EXISTS organization_invites (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    invited_email VARCHAR(320) NOT NULL,
    invited_by BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invite_token UUID DEFAULT gen_random_uuid(),
    role VARCHAR(50) DEFAULT 'member',
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    accepted_at TIMESTAMP WITH TIME ZONE,
    accepted_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(invite_token)
);

--changeset myapp-team:004-create-sequences-for-external-ids
--comment: Create sequences for external ID generation
CREATE SEQUENCE IF NOT EXISTS user_external_id_seq
    START WITH 100000
    INCREMENT BY 1
    MINVALUE 100000
    MAXVALUE 999999999
    CACHE 1;

CREATE SEQUENCE IF NOT EXISTS organization_external_id_seq
    START WITH 1000
    INCREMENT BY 1
    MINVALUE 1000
    MAXVALUE 999999999
    CACHE 1;

CREATE SEQUENCE IF NOT EXISTS invite_sequence
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 999999999
    CACHE 1;

--changeset myapp-team:004-add-external-id-columns
--comment: Add external ID columns to existing tables
ALTER TABLE users
ADD COLUMN IF NOT EXISTS external_id BIGINT DEFAULT nextval('user_external_id_seq'),
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE organizations
ADD COLUMN IF NOT EXISTS external_id BIGINT DEFAULT nextval('organization_external_id_seq'),
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS subscription_tier VARCHAR(20) DEFAULT 'free';

--changeset myapp-team:004-update-api-user-privileges-for-new-tables
--comment: Grant API user access to new tables
--runOnChange:true
-- Grant access to new tables
GRANT SELECT, INSERT, UPDATE, DELETE ON user_profiles TO userdb_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_activity TO userdb_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization_invites TO userdb_api;

-- Grant usage on new sequences
GRANT USAGE, SELECT ON user_external_id_seq TO userdb_api;
GRANT USAGE, SELECT ON organization_external_id_seq TO userdb_api;
GRANT USAGE, SELECT ON invite_sequence TO userdb_api;

--changeset myapp-team:004-create-user-management-functions
--comment: Create utility functions for user management
CREATE OR REPLACE FUNCTION get_user_display_name(user_id_param BIGINT)
RETURNS VARCHAR(200) AS $$
DECLARE
    display_name_result VARCHAR(200);
BEGIN
    SELECT COALESCE(up.display_name, up.first_name || ' ' || up.last_name, u.username)
    INTO display_name_result
    FROM users u
    LEFT JOIN user_profiles up ON u.id = up.user_id
    WHERE u.id = user_id_param;

    RETURN display_name_result;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cleanup_expired_invites()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM organization_invites
    WHERE expires_at < CURRENT_TIMESTAMP
    AND accepted_at IS NULL;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_user_last_login(user_id_param BIGINT)
RETURNS VOID AS $$
BEGIN
    UPDATE users
    SET last_login_at = CURRENT_TIMESTAMP
    WHERE id = user_id_param;
END;
$$ LANGUAGE plpgsql;