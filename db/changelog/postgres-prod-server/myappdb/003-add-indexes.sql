--liquibase formatted sql

--changeset DM-2005:0.1.005 runInTransaction:false
--comment: Add performance indexes for myappdb
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email_lower ON users(LOWER(email));
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organizations_slug_lower ON organizations(LOWER(slug));
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_organizations_role ON user_organizations(role);

--changeset DM-2006:0.1.006 runInTransaction:false
--comment: Add search vector column for myappdb
ALTER TABLE users ADD COLUMN IF NOT EXISTS search_vector tsvector;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_search_vector ON users USING GIN(search_vector);

--changeset DM-2007:0.1.007
--comment: Add search vector function for myappdb
CREATE OR REPLACE FUNCTION update_user_search_vector() RETURNS trigger AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', coalesce(NEW.username, '') || ' ' || coalesce(NEW.email, ''));
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_search_vector
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_user_search_vector();

--changeset DM-2008:0.1.008
--comment: Add audit table for myappdb user changes
CREATE TABLE IF NOT EXISTS user_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    operation VARCHAR(10),
    changed_data JSONB,
    changed_by BIGINT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

--changeset DM-2009:0.1.009 splitStatements:false
--comment: Add audit function for myappdb user changes
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

CREATE TRIGGER trigger_audit_user_changes
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_user_changes();