--liquibase formatted sql

--changeset users-team:006 splitStatements:false
--comment: Create function to update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--changeset users-team:007
--comment: Create trigger to auto-update users.updated_at
DROP TRIGGER IF EXISTS trigger_update_users_updated_at ON users;
CREATE TRIGGER trigger_update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

--changeset users-team:008
--comment: Create trigger to auto-update user_profiles.updated_at
DROP TRIGGER IF EXISTS trigger_update_user_profiles_updated_at ON user_profiles;
CREATE TRIGGER trigger_update_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

--changeset users-team:009 splitStatements:false
--comment: Create function to log user changes to audit log
CREATE OR REPLACE FUNCTION log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO user_audit_log (user_id, action, entity_type, entity_id, old_values, new_values)
        VALUES (
            NEW.id,
            'UPDATE',
            TG_TABLE_NAME,
            NEW.id,
            to_jsonb(OLD),
            to_jsonb(NEW)
        );
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO user_audit_log (user_id, action, entity_type, entity_id, old_values)
        VALUES (
            OLD.id,
            'DELETE',
            TG_TABLE_NAME,
            OLD.id,
            to_jsonb(OLD)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--changeset users-team:010
--comment: Create trigger to audit users table changes
DROP TRIGGER IF EXISTS trigger_audit_users ON users;
CREATE TRIGGER trigger_audit_users
    AFTER UPDATE OR DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION log_user_changes();

--changeset users-team:011 splitStatements:false
--comment: Create function to check if session is valid
CREATE OR REPLACE FUNCTION is_session_valid(p_session_token TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_expires_at TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT expires_at INTO v_expires_at
    FROM user_sessions
    WHERE session_token = p_session_token;

    IF v_expires_at IS NULL THEN
        RETURN false;
    END IF;

    RETURN v_expires_at > CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

--changeset users-team:012 splitStatements:false
--comment: Create function to clean up expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM user_sessions
    WHERE expires_at < CURRENT_TIMESTAMP;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

--changeset users-team:013 splitStatements:false
--comment: Create function to clean up expired password reset tokens
CREATE OR REPLACE FUNCTION cleanup_expired_reset_tokens()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM password_reset_tokens
    WHERE expires_at < CURRENT_TIMESTAMP
       OR used_at IS NOT NULL;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

--changeset users-team:014 splitStatements:false
--comment: Create function to get user statistics
CREATE OR REPLACE FUNCTION get_user_stats()
RETURNS TABLE (
    total_users BIGINT,
    active_users BIGINT,
    verified_users BIGINT,
    locked_users BIGINT,
    users_created_last_30_days BIGINT,
    active_sessions BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT as total_users,
        COUNT(*) FILTER (WHERE is_active = true)::BIGINT as active_users,
        COUNT(*) FILTER (WHERE is_verified = true)::BIGINT as verified_users,
        COUNT(*) FILTER (WHERE locked_until > CURRENT_TIMESTAMP)::BIGINT as locked_users,
        COUNT(*) FILTER (WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '30 days')::BIGINT as users_created_last_30_days,
        (SELECT COUNT(*)::BIGINT FROM user_sessions WHERE expires_at > CURRENT_TIMESTAMP) as active_sessions
    FROM users;
END;
$$ LANGUAGE plpgsql;
