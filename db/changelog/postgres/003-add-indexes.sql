--liquibase formatted sql

--changeset postgres-team:003-add-performance-indexes
--comment: Add performance indexes and constraints
CREATE INDEX CONCURRENTLY idx_users_email_lower ON users(LOWER(email));
CREATE INDEX CONCURRENTLY idx_users_created_at ON users(created_at);
CREATE INDEX CONCURRENTLY idx_organizations_slug_lower ON organizations(LOWER(slug));
CREATE INDEX CONCURRENTLY idx_user_organizations_role ON user_organizations(role);

--changeset postgres-team:003-add-full-text-search
--comment: Add full-text search capabilities
ALTER TABLE users ADD COLUMN search_vector tsvector;

CREATE INDEX CONCURRENTLY idx_users_search_vector ON users USING GIN(search_vector);

CREATE OR REPLACE FUNCTION update_user_search_vector() RETURNS trigger AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', coalesce(NEW.username, '') || ' ' || coalesce(NEW.email, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_search_vector
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_user_search_vector();

--changeset postgres-team:003-add-audit-trigger
--comment: Add audit trail for user changes
CREATE TABLE user_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    operation VARCHAR(10),
    changed_data JSONB,
    changed_by BIGINT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION audit_user_changes() RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_audit_user_changes
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_user_changes();