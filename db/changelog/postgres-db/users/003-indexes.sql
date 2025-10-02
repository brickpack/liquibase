--liquibase formatted sql

--changeset users-team:015
--comment: Create index on users.email for fast lookups during login
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

--changeset users-team:016
--comment: Create index on users.username for fast lookups
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

--changeset users-team:017
--comment: Create index on users.is_active for filtering active users
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);

--changeset users-team:018
--comment: Create index on users.created_at for date range queries
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at DESC);

--changeset users-team:019
--comment: Create composite index for active verified users
CREATE INDEX IF NOT EXISTS idx_users_active_verified ON users(is_active, is_verified) WHERE is_active = true;

--changeset users-team:020
--comment: Create index on user_profiles.user_id
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);

--changeset users-team:021
--comment: Create index on user_sessions.user_id for user session lookups
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);

--changeset users-team:022
--comment: Create index on user_sessions.session_token for validation
CREATE INDEX IF NOT EXISTS idx_user_sessions_session_token ON user_sessions(session_token);

--changeset users-team:023
--comment: Create index on user_sessions.expires_at for cleanup operations
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions(expires_at);

--changeset users-team:024
--comment: Create composite index for active sessions (removed WHERE clause - CURRENT_TIMESTAMP not immutable)
CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON user_sessions(user_id, expires_at);

--changeset users-team:025
--comment: Create index on user_audit_log.user_id for audit queries
CREATE INDEX IF NOT EXISTS idx_user_audit_log_user_id ON user_audit_log(user_id);

--changeset users-team:026
--comment: Create index on user_audit_log.created_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_user_audit_log_created_at ON user_audit_log(created_at DESC);

--changeset users-team:027
--comment: Create composite index for audit log queries by user and action
CREATE INDEX IF NOT EXISTS idx_user_audit_log_user_action ON user_audit_log(user_id, action, created_at DESC);

--changeset users-team:028
--comment: Create index on password_reset_tokens.user_id
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);

--changeset users-team:029
--comment: Create index on password_reset_tokens.token for validation
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_token ON password_reset_tokens(token);

--changeset users-team:030
--comment: Create index on password_reset_tokens.expires_at for cleanup
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_expires_at ON password_reset_tokens(expires_at);

--changeset users-team:031
--comment: Create GIN index on user_profiles.metadata for JSONB queries
CREATE INDEX IF NOT EXISTS idx_user_profiles_metadata ON user_profiles USING GIN (metadata);
