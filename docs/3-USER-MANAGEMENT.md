# Database User Management

Secure database user creation using a two-step approach: Liquibase creates users with temporary passwords, then the pipeline sets real passwords from AWS Secrets Manager.

## Overview

This approach separates concerns:
- **Liquibase**: Manages user creation and grants (version-controlled schema changes)
- **Pipeline Script**: Manages passwords (runtime secrets from AWS)

This solves password rotation complexity and keeps secrets out of version control.

## Quick Setup

### 1. Store User Passwords in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --description "Database user passwords for automated password management" \
  --secret-string '{
    "finance_app": "SecureFinancePassword123!",
    "finance_readonly": "ReadOnlyFinancePass456!",
    "myapp_readwrite": "PostgresAppPassword789!",
    "ecommerce_app": "MySQLAppPassword012!",
    "inventory_app": "SQLServerAppPass345!"
  }'
```

### 2. Create User Changesets with Temporary Passwords

Each database platform has its own syntax:

#### Oracle User Example

```sql
--liquibase formatted sql

--changeset DM-6001:001
--comment: Create user finance_app for Oracle
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username = UPPER('finance_app')
-- Note: Password will be set separately by manage-users.sh script
CREATE USER finance_app IDENTIFIED BY "TemporaryPassword123"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP
    QUOTA 500M ON FINANCE_DATA
    PROFILE DEFAULT
    ACCOUNT UNLOCK;

--changeset DM-6002:002
--comment: Grant system privileges to finance_app
--runOnChange:true
GRANT CREATE SESSION TO finance_app;
GRANT CREATE TABLE TO finance_app;
GRANT CREATE SEQUENCE TO finance_app;
GRANT CREATE TRIGGER TO finance_app;
```

#### PostgreSQL User Example

```sql
--liquibase formatted sql

--changeset DM-7001:001
--comment: Create myapp_readwrite user for PostgreSQL
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_user WHERE usename = 'myapp_readwrite'
-- Note: Password will be set separately by manage-users.sh script
CREATE USER myapp_readwrite WITH PASSWORD 'TemporaryPassword123';

--changeset DM-7002:002
--comment: Grant database connection privileges to myapp_readwrite
--runOnChange:true
GRANT CONNECT ON DATABASE myappdb TO myapp_readwrite;
GRANT USAGE ON SCHEMA public TO myapp_readwrite;

--changeset DM-7003:003
--comment: Grant table privileges to myapp_readwrite
--runOnChange:true
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myapp_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO myapp_readwrite;
```

#### MySQL User Example

```sql
--liquibase formatted sql

--changeset DM-8001:001
--comment: Create ecommerce_app user for MySQL
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM mysql.user WHERE user = 'ecommerce_app'
-- Note: Password will be set separately by manage-users.sh script
CREATE USER 'ecommerce_app'@'%' IDENTIFIED BY 'TemporaryPassword123';

--changeset DM-8002:002
--comment: Grant database privileges to ecommerce_app
--runOnChange:true
GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce.* TO 'ecommerce_app'@'%';
GRANT EXECUTE ON ecommerce.* TO 'ecommerce_app'@'%';
FLUSH PRIVILEGES;
```

#### SQL Server User Example

```sql
--liquibase formatted sql

--changeset DM-9001:001
--comment: Create inventory_app login for SQL Server
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.sql_logins WHERE name = 'inventory_app'
-- Note: Password will be set separately by manage-users.sh script
CREATE LOGIN inventory_app WITH PASSWORD = 'TemporaryPassword123!';

--changeset DM-9002:002
--comment: Create inventory_app database user
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = 'inventory_app'
CREATE USER inventory_app FOR LOGIN inventory_app;

--changeset DM-9003:003
--comment: Grant role memberships to inventory_app
--runOnChange:true
ALTER ROLE db_datareader ADD MEMBER inventory_app;
ALTER ROLE db_datawriter ADD MEMBER inventory_app;

--changeset DM-9004:004
--comment: Grant additional privileges to inventory_app
--runOnChange:true
GRANT EXECUTE TO inventory_app;
GRANT VIEW DEFINITION TO inventory_app;
```

### 3. How the Pipeline Works

When you run the pipeline in **deploy mode**:

1. **Liquibase runs first**:
   - Creates users/logins with temporary passwords
   - Applies grants and permissions
   - Tracks changes in DATABASECHANGELOG table

2. **manage-users.sh script runs after**:
   - Fetches real passwords from AWS Secrets Manager (`liquibase-users` secret)
   - Connects to each database using admin credentials
   - Sets real passwords for each user
   - Uses platform-specific password update commands

**Important**: This only runs in **deploy mode**. Test mode skips password management entirely.

## How manage-users.sh Works

The script is located at `.github/scripts/manage-users.sh` and does the following for each database platform:

### Oracle
Uses Liquibase's execute-sql command with PL/SQL:
```sql
ALTER USER username IDENTIFIED BY "real_password"
```

### PostgreSQL
Uses psql client:
```sql
ALTER USER username WITH PASSWORD 'real_password'
```

### MySQL
Uses mysql client:
```sql
ALTER USER 'username'@'%' IDENTIFIED BY 'real_password';
FLUSH PRIVILEGES;
```

### SQL Server
Uses sqlcmd client:
```sql
ALTER LOGIN [username] WITH PASSWORD = 'real_password';
```

## Password Rotation

To rotate a password:

1. **Update AWS Secrets Manager**:
   ```bash
   aws secretsmanager update-secret \
     --secret-id liquibase-users \
     --secret-string '{
       "finance_app": "NewRotatedPassword123!",
       ...other users...
     }'
   ```

2. **Trigger deploy mode**:
   ```bash
   gh workflow run liquibase-cicd.yml -f action=deploy -f database=oracle-finance
   ```

The script will automatically update the password in the database.

**Note**: No Liquibase changeset needed for password rotation - just update the secret and run the workflow.

## Security Features

- ✅ **No passwords in version control**: Only temporary passwords tracked by Liquibase
- ✅ **Secrets in AWS**: Real passwords stored securely in AWS Secrets Manager
- ✅ **Password masking**: Passwords automatically masked in GitHub Actions logs
- ✅ **IAM controls**: AWS IAM role controls access to secrets
- ✅ **Audit trail**: Liquibase tracks user creation, AWS CloudTrail tracks secret access
- ✅ **Separation of concerns**: Schema changes (Liquibase) separate from secrets (AWS)

## Configuration

Set these GitHub repository variables (Settings > Secrets and variables > Actions > Variables):

- `USER_SECRET_NAME` (optional): AWS secret name containing user passwords (default: `liquibase-users`)

The pipeline automatically:
- Discovers which database needs user management
- Fetches the correct passwords from AWS Secrets Manager
- Updates passwords after Liquibase deployment

## Troubleshooting

### User created but password doesn't work

**Cause**: Workflow ran in test mode, which skips password management.

**Solution**: Run in deploy mode:
```bash
gh workflow run liquibase-cicd.yml -f action=deploy -f database=your-database
```

### "Login failed for user" after deployment

**Cause**: Password not updated or incorrect in AWS Secrets Manager.

**Solution**:
1. Verify password exists in `liquibase-users` secret
2. Check workflow logs for "Setting real passwords for database users" step
3. Ensure username in secret matches username in changeset exactly

### Oracle: Password update failed

**Cause**: Password may not meet Oracle complexity requirements.

**Solution**: Ensure password has:
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least 8 characters

### SQL Server: Login exists but can't authenticate

**Cause**: SQL Server has both LOGIN (server-level) and USER (database-level).

**Solution**: Ensure changeset creates both:
```sql
CREATE LOGIN username WITH PASSWORD = 'temp';
CREATE USER username FOR LOGIN username;
```

## Adding a New User

1. **Add password to AWS Secrets Manager**:
   ```bash
   current=$(aws secretsmanager get-secret-value --secret-id liquibase-users --query SecretString --output text)
   updated=$(echo "$current" | jq '. + {"new_analytics_user": "NewPassword123!"}')
   aws secretsmanager update-secret --secret-id liquibase-users --secret-string "$updated"
   ```

2. **Create changeset** (see examples above for your platform)

3. **Deploy**:
   ```bash
   git add db/changelog/
   git commit -m "Add new_analytics_user with read-only access"
   git push
   # Create PR, get approval, merge to main
   # Pipeline automatically creates user and sets password
   ```

That's it! The user management system provides secure, automated database user creation across all platforms.
