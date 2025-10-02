# Liquibase Best Practices & Lessons Learned

This document contains important best practices learned from real-world implementation.

## PostgreSQL Best Practices

### Functions and Triggers

#### Always Use `splitStatements:false` for Functions

PostgreSQL functions use dollar-quoted strings (`$$`). Liquibase's SQL parser can incorrectly split these, causing "Unterminated dollar quote" errors.

**❌ Wrong:**
```sql
--changeset author:001
CREATE OR REPLACE FUNCTION my_function()
RETURNS TRIGGER AS $$
BEGIN
    -- function body
END;
$$ LANGUAGE plpgsql;
```

**✅ Correct:**
```sql
--changeset author:001 splitStatements:false
CREATE OR REPLACE FUNCTION my_function()
RETURNS TRIGGER AS $$
BEGIN
    -- function body
END;
$$ LANGUAGE plpgsql;
```

#### Make Triggers Idempotent

Always use `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER` to make changesets idempotent.

**❌ Wrong:**
```sql
--changeset author:002
CREATE TRIGGER my_trigger
    BEFORE UPDATE ON my_table
    FOR EACH ROW
    EXECUTE FUNCTION my_function();
```

**✅ Correct:**
```sql
--changeset author:002
DROP TRIGGER IF EXISTS my_trigger ON my_table;
CREATE TRIGGER my_trigger
    BEFORE UPDATE ON my_table
    FOR EACH ROW
    EXECUTE FUNCTION my_function();
```

### Partial Indexes

#### Only Use IMMUTABLE Functions in WHERE Clauses

Partial indexes (indexes with WHERE clauses) require IMMUTABLE functions. `CURRENT_TIMESTAMP` is NOT immutable.

**❌ Wrong:**
```sql
CREATE INDEX idx_active_sessions
ON user_sessions(user_id, expires_at)
WHERE expires_at > CURRENT_TIMESTAMP;
-- ERROR: functions in index predicate must be marked IMMUTABLE
```

**✅ Alternative Solutions:**

1. **Remove the WHERE clause:**
```sql
CREATE INDEX idx_active_sessions
ON user_sessions(user_id, expires_at);
-- Still useful for session queries
```

2. **Use a boolean column instead:**
```sql
-- Add column
ALTER TABLE user_sessions ADD COLUMN is_active BOOLEAN;

-- Update with trigger
CREATE FUNCTION update_session_status()
RETURNS TRIGGER AS $$
BEGIN
    NEW.is_active = (NEW.expires_at > CURRENT_TIMESTAMP);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create partial index
CREATE INDEX idx_active_sessions
ON user_sessions(user_id, expires_at)
WHERE is_active = true;
```

## User Management Best Practices

### Use Two-Step Approach

**Recommended approach:**

1. **Liquibase creates users with temporary passwords:**
```sql
--changeset DM-001:001
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_user WHERE usename = 'myapp_user'
-- Note: Real password set by manage-users.sh after deployment
CREATE USER myapp_user WITH PASSWORD 'TemporaryPassword123';
```

2. **Pipeline sets real passwords from AWS Secrets Manager:**
   - Runs automatically in deploy mode
   - Uses `manage-users.sh` script
   - Fetches passwords from AWS at runtime

**Why this works:**
- ✅ Passwords never in version control
- ✅ Liquibase tracks user creation (schema change)
- ✅ Secrets managed separately (runtime concern)
- ✅ Password rotation doesn't require new changesets

### Password Rotation

To rotate a password:

1. **Update AWS Secrets Manager:**
```bash
aws secretsmanager update-secret \
  --secret-id liquibase-users \
  --secret-string '{"myapp_user": "NewPassword123!"}'
```

2. **Trigger deploy mode:**
```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=postgres-mydb
```

**No new changeset needed!** The `manage-users.sh` script updates passwords automatically.

## Test vs Deploy Mode

### When Each Mode Runs

| Trigger | Mode | Behavior |
|---------|------|----------|
| Feature branch push | Test | Validates only, no DB connections |
| Pull request | Test | Validates only, no DB connections |
| Main branch merge | Deploy | Creates DBs, deploys changes, sets passwords |
| Manual: `action=test` | Test | Always test mode |
| Manual: `action=deploy` | Deploy | Always deploy mode |
| Manual: `action=auto` | Auto | Branch-aware (test on features, deploy on main) |

### Common Mistakes

**❌ Expecting deployment on feature branch push:**
```bash
git push origin feature/add-users
# This runs TEST mode only - no deployment!
```

**✅ Correct deployment workflow:**
```bash
# 1. Push to feature branch (test mode)
git push origin feature/add-users

# 2. Create PR (test mode)
gh pr create

# 3. Merge to main (deploy mode)
# After approval, merge triggers deployment
```

**✅ Manual deployment (if needed):**
```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=all
```

## Database Creation

### Master Credentials Required

To automatically create databases, add "master" secrets:

```json
{
  "postgres-master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://host:5432/postgres",
    "username": "postgres_user",
    "password": "master_password"
  },
  "postgres-myapp": {
    "type": "postgresql",
    "url": "jdbc:postgresql://host:5432/myapp",
    "username": "postgres_user",
    "password": "app_password"
  }
}
```

**Key points:**
- Master URL points to **system database** (postgres, mysql, master)
- App URL points to **your application database**
- User needs **CREATE DATABASE** privilege
- Only runs in **deploy mode**

### Supported Platforms

| Platform | Auto-Create? | Master Database |
|----------|--------------|-----------------|
| PostgreSQL | ✅ Yes | postgres |
| MySQL | ✅ Yes | mysql |
| Oracle | ✅ Yes | Uses SID/Service |
| SQL Server | ❌ No | Must create manually |

## Docker Container Usage

### Why We Use a Custom Container

**Benefits:**
- All database tools pre-installed (psql, mysql, sqlcmd, sqlplus)
- All JDBC drivers pre-configured
- Saves ~2 minutes per workflow run
- Consistent environment across all runs

### JDBC Driver Configuration

**In Docker container, drivers are in `/opt/liquibase/lib/`:**

```bash
# configure-database.sh automatically sets:
DRIVER_PATH=""  # Empty string - Liquibase auto-loads from lib/
```

**Do NOT use hardcoded paths like:**
```bash
DRIVER_PATH="drivers/sqlserver.jar"  # ❌ Won't work in Docker
```

### Environment Variable Warning

This warning is **harmless** and can be ignored:

```
WARNING: Liquibase detected the following invalid LIQUIBASE_* environment variables:
- LIQUIBASE_VERSION
```

The `LIQUIBASE_VERSION` env var is set in the Dockerfile for documentation purposes.

## Changeset Organization

### Recommended Structure

```
db/changelog/
├── postgres-server-name/
│   ├── database-name/
│   │   ├── 001-initial-schema.sql
│   │   ├── 002-functions-and-triggers.sql
│   │   ├── 003-indexes.sql
│   │   └── users/
│   │       └── 001-app-user.sql
```

### Naming Convention

**Changelog XML:** `changelog-{secret-name}.xml`
- Must match AWS Secrets Manager key
- Example: `changelog-postgres-myapp.xml` → secret key `postgres-myapp`

**SQL Files:** `{number}-{description}.sql`
- Sequential numbering
- Descriptive names
- Lowercase with hyphens

**Changeset IDs:** `{team}:{sequential-number}`
- Example: `users-team:001`, `users-team:002`
- Makes tracking easier across teams

## Preconditions

### Use for Idempotency

Always use preconditions for CREATE statements:

**Users (PostgreSQL):**
```sql
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_user WHERE usename = 'myapp_user'
CREATE USER myapp_user WITH PASSWORD 'temp';
```

**Tables:**
```sql
--changeset author:001
CREATE TABLE IF NOT EXISTS my_table (...);
-- IF NOT EXISTS handles idempotency
```

**Functions:**
```sql
--changeset author:002 splitStatements:false
CREATE OR REPLACE FUNCTION my_func() ...
-- CREATE OR REPLACE handles idempotency
```

## Troubleshooting

### "Unterminated dollar quote" Error

**Cause:** Missing `splitStatements:false` on function changeset

**Solution:** Add attribute to changeset:
```sql
--changeset author:001 splitStatements:false
```

### "Functions in index predicate must be marked IMMUTABLE"

**Cause:** Using non-immutable function in partial index WHERE clause

**Solution:** Remove WHERE clause or use immutable expression:
```sql
-- Instead of: WHERE expires_at > CURRENT_TIMESTAMP
-- Use: Remove WHERE clause entirely
```

### "User created but password doesn't work"

**Cause:** Workflow ran in test mode, not deploy mode

**Solution:** Run deploy mode explicitly:
```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=your-db
```

### "Database not found" During Deployment

**Cause:** Missing "master" credentials for database creation

**Solution:** Add master secret to AWS Secrets Manager:
```bash
# Add postgres-master secret pointing to system database
```

### Trigger Already Exists Error

**Cause:** Not using `DROP TRIGGER IF EXISTS`

**Solution:** Always drop before create:
```sql
DROP TRIGGER IF EXISTS my_trigger ON my_table;
CREATE TRIGGER my_trigger ...
```

## Performance Tips

### Index Creation

1. **Use CREATE INDEX CONCURRENTLY for large tables:**
```sql
CREATE INDEX CONCURRENTLY idx_large_table ON large_table(column);
```

2. **Create indexes in separate changesets:**
```sql
-- 001-tables.sql
CREATE TABLE users ...

-- 002-indexes.sql (separate file)
CREATE INDEX idx_users_email ON users(email);
```

3. **Use partial indexes when possible:**
```sql
CREATE INDEX idx_active_users ON users(id) WHERE is_active = true;
```

### Function Optimization

1. **Mark functions appropriately:**
```sql
CREATE FUNCTION get_constant()
RETURNS TEXT
LANGUAGE sql
IMMUTABLE  -- If result never changes
AS $$
    SELECT 'constant_value'::TEXT;
$$;
```

2. **Use STABLE for functions that don't modify data:**
```sql
CREATE FUNCTION get_user_count()
RETURNS INTEGER
LANGUAGE sql
STABLE  -- Result doesn't change within transaction
AS $$
    SELECT COUNT(*)::INTEGER FROM users;
$$;
```

## Summary Checklist

Before deploying changesets:

- [ ] PostgreSQL functions have `splitStatements:false`
- [ ] Triggers use `DROP TRIGGER IF EXISTS`
- [ ] Partial indexes don't use `CURRENT_TIMESTAMP` in WHERE
- [ ] Users created with temporary passwords
- [ ] Real passwords in AWS Secrets Manager (`liquibase-users`)
- [ ] Preconditions on CREATE USER statements
- [ ] Tables use `CREATE TABLE IF NOT EXISTS`
- [ ] Tested in test mode first (feature branch)
- [ ] Deployed via PR merge or manual deploy mode
- [ ] Master credentials exist for auto-database creation
