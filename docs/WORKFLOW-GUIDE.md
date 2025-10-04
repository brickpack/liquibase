# Liquibase Workflow Guide

Complete guide to using the Liquibase CI/CD pipeline effectively, including workflow modes, best practices, and troubleshooting.

---

## Table of Contents

- [Workflow Modes](#workflow-modes)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Performance Tips](#performance-tips)

---

## Workflow Modes

The Liquibase CI/CD pipeline has two distinct modes: **Test Mode** and **Deploy Mode**.

### Quick Reference

| Trigger | Mode | Database Connection | User Passwords | AWS Credentials |
|---------|------|-------------------|----------------|-----------------|
| Feature branch push | Test | ❌ Offline only | ❌ Not set | ❌ Not required |
| Pull request | Test | ❌ Offline only | ❌ Not set | ❌ Not required |
| Main branch (after merge) | Deploy | ✅ Live databases | ✅ Set from AWS | ✅ Required |
| Manual: `action=test` | Test | ❌ Offline only | ❌ Not set | ❌ Not required |
| Manual: `action=deploy` | Deploy | ✅ Live databases | ✅ Set from AWS | ✅ Required |
| Manual: `action=auto` | Auto-detect | Depends on branch | Depends on branch | Depends on branch |

---

### Test Mode

#### When It Runs

Test mode runs automatically when:
- Pushing to feature branches (any branch except `main`)
- Opening or updating pull requests
- Manually triggered with `action=test`

#### What It Does

1. **SQL Syntax Validation**
   - Checks all SQL files for basic syntax errors
   - Validates Liquibase headers and changeset format
   - Checks for unterminated quotes and dollar quotes
   - Ensures required preconditions

2. **Liquibase Offline Validation**
   - Validates changelog XML structure
   - Checks changeset syntax
   - Verifies file references
   - Uses offline PostgreSQL driver (no actual connection)

3. **SQL Preview Generation**
   - Generates SQL that would be executed
   - Uploads as workflow artifact
   - Available for download and review
   - Shows exactly what would happen in deploy mode

4. **Changelog Structure Analysis**
   - Analyzes directory structure
   - Validates naming conventions
   - Checks for missing files

#### What It Doesn't Do

- ❌ Does NOT connect to actual databases
- ❌ Does NOT execute any SQL
- ❌ Does NOT create databases
- ❌ Does NOT set user passwords
- ❌ Does NOT require AWS credentials
- ❌ Does NOT modify any data

#### Why Use Test Mode

- **Fast feedback**: Catches errors before deployment
- **No credentials needed**: Works on any branch without AWS access
- **Safe**: Cannot accidentally modify databases
- **Code review**: Generated SQL can be reviewed in PR
- **CI/CD best practice**: Test before deploy

#### Example Workflow

```bash
# Create feature branch
git checkout -b feature/add-products-table

# Make changes to SQL
vim db/changelog/postgres/thedb/tables/002-add-products.sql

# Commit and push
git add .
git commit -m "Add products table"
git push origin feature/add-products-table

# Pipeline automatically runs in TEST mode
# - Validates SQL syntax
# - Generates SQL preview
# - No database connection required

# Create PR
gh pr create --title "Add products table" --body "New table for product catalog"

# Pipeline runs TEST mode again on PR
# Team reviews generated SQL in artifacts
# Get approval and merge
```

---

### Deploy Mode

#### When It Runs

Deploy mode runs when:
- Pushing directly to `main` branch (after PR merge)
- Manually triggered with `action=deploy`

#### What It Does

1. **All Test Mode Steps** (first)
   - Validates syntax
   - Runs offline validation
   - Ensures safety before deployment

2. **Database Discovery**
   - Fetches credentials from AWS Secrets Manager
   - Identifies all target databases
   - Determines which need changesets applied

3. **Database Creation** (if needed)
   - Checks if database exists
   - Uses master credentials to CREATE DATABASE
   - Skips if database already exists

4. **Liquibase Deployment**
   - Connects to live databases
   - Executes pending changesets
   - Updates DATABASECHANGELOG table
   - Applies schema changes

5. **User Password Management**
   - Runs `manage-users.sh` script
   - Fetches passwords from AWS Secrets Manager (`.databases.{dbname}.users`)
   - Sets real passwords for all users
   - Updates passwords in live databases

#### What It Requires

- ✅ AWS credentials (via OIDC)
- ✅ Database credentials in AWS Secrets Manager
- ✅ Network access to databases
- ✅ Valid changelog files

#### Security Safeguards

Even in deploy mode, the pipeline is safe:

1. **PR required**: Only runs after code review and approval
2. **Preconditions**: Uses `IF NOT EXISTS` for idempotency
3. **Transactions**: Liquibase uses transactions where supported
4. **Rollback tracking**: DATABASECHANGELOG tracks what ran
5. **Password masking**: Secrets masked in logs

#### Example Workflow

```bash
# After PR is approved and merged to main
git checkout main
git pull

# Pipeline automatically runs in DEPLOY mode
# 1. Validates changesets (test mode checks)
# 2. Connects to databases
# 3. Creates database if needed
# 4. Deploys changesets
# 5. Sets user passwords from AWS Secrets Manager

# Monitor the deployment
gh run watch

# Verify deployment
# Check DATABASECHANGELOG table in your database
```

---

### Manual Workflow Triggers

You can manually trigger the workflow with specific modes:

#### Test Mode (Safe)

```bash
# Test all databases
gh workflow run liquibase-cicd.yml -f action=test -f database=all

# Test specific database
gh workflow run liquibase-cicd.yml -f action=test -f database=postgres-thedb

# Test specific platform
gh workflow run liquibase-cicd.yml -f action=test -f database=postgresql
```

#### Deploy Mode (Requires AWS Credentials)

```bash
# Deploy all databases
gh workflow run liquibase-cicd.yml -f action=deploy -f database=all

# Deploy specific database
gh workflow run liquibase-cicd.yml -f action=deploy -f database=sqlserver-thedb

# Deploy specific platform
gh workflow run liquibase-cicd.yml -f action=deploy -f database=mysql
```

#### Auto Mode (Branch-aware)

```bash
# Auto-detect based on branch
gh workflow run liquibase-cicd.yml -f action=auto -f database=all

# If on main: runs deploy mode
# If on feature branch: runs test mode
```

---

## Best Practices

### PostgreSQL Best Practices

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

#### Partial Indexes - Only Use IMMUTABLE Functions

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

---

### SQL Server Best Practices

#### Always Use `splitStatements:false` for Multi-Statement Batches

SQL Server uses `GO` to separate batches. Use `splitStatements:false` for changesets with multiple GO statements.

**✅ Correct:**
```sql
--changeset db-admin:101 splitStatements:false
--comment: Create read-write user for application
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'app_readwrite')
BEGIN
    CREATE LOGIN app_readwrite WITH PASSWORD = 'CHANGE_ME_TEMP_PASSWORD';
END
GO

USE thedb;
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'app_readwrite')
BEGIN
    CREATE USER app_readwrite FOR LOGIN app_readwrite;
END
GO
```

---

### User Management Best Practices

#### Use Two-Step Approach

**Recommended approach:**

1. **Liquibase creates users with temporary passwords:**
```sql
--changeset DM-001:001 splitStatements:false
--comment: Create application user
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE USER app_user WITH PASSWORD 'CHANGE_ME_TEMP_PASSWORD';
    END IF;
END
$$;

-- Note: Real password set by manage-users.sh after deployment
GRANT CONNECT ON DATABASE thedb TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
```

2. **Pipeline sets real passwords from AWS Secrets Manager:**
   - Runs automatically in deploy mode
   - Uses `manage-users.sh` script
   - Fetches passwords from `.databases.{dbname}.users` in the per-server secret

**Why this works:**
- ✅ Passwords never in version control
- ✅ Liquibase tracks user creation (schema change)
- ✅ Secrets managed separately (runtime concern)
- ✅ Password rotation doesn't require new changesets

#### Password Rotation

To rotate a password:

1. **Update AWS Secrets Manager:**
```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Update specific user password
UPDATED=$(echo "$SECRET" | jq \
  '.databases.thedb.users.app_user = "NewPassword123!"')

# Save back to AWS
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$UPDATED"
```

2. **Trigger deploy mode:**
```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=postgres-thedb
```

**No new changeset needed!** The `manage-users.sh` script updates passwords automatically.

---

### Changeset Organization

#### Recommended Structure

```
db/changelog/
├── postgres/
│   ├── thedb/
│   │   ├── users/
│   │   │   └── 001-create-users.sql
│   │   ├── tables/
│   │   │   └── 001-create-tables.sql
│   │   ├── sequences/
│   │   │   └── 001-create-sequences.sql
│   │   ├── indexes/
│   │   │   └── 001-create-indexes.sql
│   │   └── functions/
│   │       └── 001-create-functions.sql
```

#### Naming Convention

**Changelog XML:** `changelog-{server}-{dbname}.xml`
- Must match database identifier in secrets
- Example: `changelog-postgres-thedb.xml` → secret `liquibase-postgres-prod.databases.thedb`

**SQL Files:** `{number}-{description}.sql`
- Sequential numbering
- Descriptive names
- Lowercase with hyphens

**Changeset IDs:** `{team}:{sequential-number}`
- Example: `db-admin:001`, `db-admin:002`
- Makes tracking easier across teams

---

### Preconditions for Idempotency

Always use preconditions for CREATE statements:

**Users (PostgreSQL):**
```sql
--changeset db-admin:001 splitStatements:false
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE USER app_user WITH PASSWORD 'CHANGE_ME_TEMP_PASSWORD';
    END IF;
END
$$;
```

**Tables:**
```sql
--changeset author:001
CREATE TABLE IF NOT EXISTS my_table (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);
```

**Functions:**
```sql
--changeset author:002 splitStatements:false
CREATE OR REPLACE FUNCTION my_func() ...
-- CREATE OR REPLACE handles idempotency
```

---

### Common Workflow Mistakes

#### ❌ Expecting deployment on feature branch push

```bash
git push origin feature/add-users
# This runs TEST mode only - no deployment!
```

#### ✅ Correct deployment workflow

```bash
# 1. Push to feature branch (test mode)
git push origin feature/add-users

# 2. Create PR (test mode)
gh pr create

# 3. Merge to main (deploy mode)
# After approval, merge triggers deployment
```

#### ✅ Manual deployment (if needed)

```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=all
```

---

## Troubleshooting

### "Unterminated dollar quote" Error

**Cause:** Missing `splitStatements:false` on function changeset

**Solution:** Add attribute to changeset:
```sql
--changeset author:001 splitStatements:false
```

---

### "Functions in index predicate must be marked IMMUTABLE"

**Cause:** Using non-immutable function in partial index WHERE clause

**Solution:** Remove WHERE clause or use immutable expression:
```sql
-- Instead of: WHERE expires_at > CURRENT_TIMESTAMP
-- Use: Remove WHERE clause entirely or use boolean column
```

---

### "User created but password doesn't work"

**Cause:** Workflow ran in test mode, not deploy mode

**Solution:** Run deploy mode explicitly:
```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=postgres-thedb
```

---

### "Database not found" During Deployment

**Cause:** Missing "master" credentials for database creation

**Solution:** Add master secret to per-server AWS Secrets Manager secret:
```json
{
  "master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://host:5432/postgres",
    "username": "postgres",
    "password": "master_password"
  }
}
```

---

### Trigger Already Exists Error

**Cause:** Not using `DROP TRIGGER IF EXISTS`

**Solution:** Always drop before create:
```sql
DROP TRIGGER IF EXISTS my_trigger ON my_table;
CREATE TRIGGER my_trigger ...
```

---

### "Permission denied" in Deploy Mode

**Cause:** AWS OIDC authentication failed

**Solution:**
- Verify `AWS_ROLE_ARN` variable is set in GitHub
- Check IAM role trust policy includes your repository
- Ensure workflow has `id-token: write` permission

---

### Password Not Set (User Can't Login)

**Cause:** Workflow ran in Test mode instead of Deploy mode

**Solution:**
- Check which mode ran in workflow logs
- If test mode: trigger deploy mode manually:
  ```bash
  gh workflow run liquibase-cicd.yml -f action=deploy -f database=your-db
  ```

---

### Changes Not Applied to Database

**Cause:** Workflow ran in Test mode (no database connection)

**Solution:**
- Test mode only validates, doesn't deploy
- Merge PR to main for Deploy mode
- Or manually trigger deploy mode

---

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

---

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

---

## Deployment Checklist

Before deploying changesets:

- [ ] PostgreSQL functions have `splitStatements:false`
- [ ] SQL Server multi-statement batches have `splitStatements:false`
- [ ] Triggers use `DROP TRIGGER IF EXISTS`
- [ ] Partial indexes don't use `CURRENT_TIMESTAMP` in WHERE
- [ ] Users created with temporary passwords
- [ ] Real passwords in AWS Secrets Manager (`.databases.{dbname}.users`)
- [ ] Preconditions on CREATE USER statements
- [ ] Tables use `CREATE TABLE IF NOT EXISTS`
- [ ] Tested in test mode first (feature branch)
- [ ] Deployed via PR merge or manual deploy mode
- [ ] Master credentials exist for auto-database creation

---

## Common Scenarios

### Scenario 1: Feature Development

**Goal**: Add a new table safely

**Process**:
1. Create feature branch → **Test mode** runs automatically
2. Commit SQL changes → **Test mode** validates
3. Create PR → **Test mode** runs again
4. Team reviews generated SQL
5. Merge to main → **Deploy mode** runs
6. Table created in database

**Mode**: Test → Test → Deploy

---

### Scenario 2: Hotfix Deployment

**Goal**: Fix critical issue quickly

**Process**:
1. Create hotfix branch
2. Make minimal change
3. Push → **Test mode** validates
4. Merge to main → **Deploy mode** deploys

**Mode**: Test → Deploy

---

### Scenario 3: Password Rotation

**Goal**: Rotate user password without schema changes

**Process**:
1. Update AWS Secrets Manager password (`.databases.{dbname}.users.username`)
2. Run manual deploy:
   ```bash
   gh workflow run liquibase-cicd.yml -f action=deploy -f database=postgres-thedb
   ```
3. Pipeline updates password (no Liquibase changes needed)

**Mode**: Deploy only (no changeset required)

---

### Scenario 4: Testing New Database Setup

**Goal**: Validate changelog before creating database

**Process**:
1. Add new changelog file
2. Create feature branch
3. Push → **Test mode** validates offline
4. Review generated SQL
5. Merge to main → **Deploy mode** creates database and runs changesets

**Mode**: Test → Deploy

---

## Summary

**Test Mode**:
- Safe, fast validation
- No AWS credentials required
- No database connections
- Runs on feature branches and PRs

**Deploy Mode**:
- Actual deployment
- Requires AWS credentials
- Connects to live databases
- Runs on main branch or manual trigger

**Best Practice**: Test on branches → Review in PR → Deploy from main
