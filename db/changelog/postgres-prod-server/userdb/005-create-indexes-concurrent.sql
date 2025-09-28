--liquibase formatted sql

--changeset myapp-team:005-create-indexes-concurrent runInTransaction:false
--comment: Create performance indexes for new tables (concurrent)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_profiles_display_name ON user_profiles(display_name);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_activity_user_id ON user_activity(user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_activity_type ON user_activity(activity_type);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_activity_created_at ON user_activity(created_at);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_activity_session_id ON user_activity(session_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organization_invites_org_id ON organization_invites(organization_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organization_invites_email ON organization_invites(invited_email);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organization_invites_token ON organization_invites(invite_token);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organization_invites_expires_at ON organization_invites(expires_at);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_external_id ON users(external_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_last_login ON users(last_login_at);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organizations_external_id ON organizations(external_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organizations_is_active ON organizations(is_active);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_organizations_subscription_tier ON organizations(subscription_tier);
