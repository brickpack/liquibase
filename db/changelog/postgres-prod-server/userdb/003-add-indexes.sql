--liquibase formatted sql

--changeset DM-1007:0.1.007 runInTransaction:false
--comment: Add performance indexes and constraints
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email_lower ON users(LOWER(email));
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organizations_slug_lower ON organizations(LOWER(slug));
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_organizations_role ON user_organizations(role);

--changeset DM-1008:0.1.008 runInTransaction:false
--comment: Add search vector column and index
ALTER TABLE users ADD COLUMN IF NOT EXISTS search_vector tsvector;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_search_vector ON users USING GIN(search_vector);

--changeset DM-1009:0.1.009
--comment: Add search vector function and trigger
CREATE OR REPLACE FUNCTION update_user_search_vector() RETURNS trigger AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', coalesce(NEW.username, '') || ' ' || coalesce(NEW.email, ''));
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_user_search_vector ON users;
CREATE TRIGGER trigger_update_user_search_vector
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_user_search_vector();

--changeset DM-1010:0.1.010
--comment: Add audit table for user changes
CREATE TABLE IF NOT EXISTS user_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    operation VARCHAR(10),
    changed_data JSONB,
    changed_by BIGINT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

--changeset DM-1011:0.1.011 splitStatements:false
--comment: Add audit function and trigger for user changes
CREATE OR REPLACE FUNCTION audit_user_changes() RETURNS trigger AS $audit_func$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO user_audit(user_id, operation, changed_data, changed_at)
        VALUES (OLD.id, 'DELETE', to_jsonb(OLD), CURRENT_TIMESTAMP);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO user_audit(user_id, operation, changed_data, changed_at)
        VALUES (NEW.id, 'UPDATE', to_jsonb(NEW), CURRENT_TIMESTAMP);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO user_audit(user_id, operation, changed_data, changed_at)
        VALUES (NEW.id, 'INSERT', to_jsonb(NEW), CURRENT_TIMESTAMP);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$audit_func$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_audit_user_changes ON users;
CREATE TRIGGER trigger_audit_user_changes
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_user_changes();