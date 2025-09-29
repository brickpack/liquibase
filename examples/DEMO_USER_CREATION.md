# Demo: Creating Database Users with AWS Secrets Manager

This demonstration shows how to create database users using the new user management system.

## 📋 Example Scenario

We want to create two users for the Oracle finance database:
1. **finance_app** - Application user with read/write access
2. **finance_readonly** - Analytics user with read-only access

## 🔧 Step-by-Step Process

### Step 1: Store Passwords in AWS Secrets Manager

```bash
# Create the secret with both user passwords
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --description "Database user passwords for Liquibase deployments" \
  --secret-string '{
    "finance_app": "MySecureAppPassword123!",
    "finance_readonly": "ReadOnlyPassword456!"
  }'
```

### Step 2: User Changesets Already Created

The example user changesets are already created:
- `db/changelog/database-1/users/001-finance-app-user.sql`
- `db/changelog/database-1/users/002-finance-readonly-user.sql`

### Step 3: Include Users in Main Changelog

Add to `changelog-oracle-finance.xml`:

```xml
<databaseChangeLog>
  <!-- Existing includes -->
  <include file="db/changelog/database-1/finance/001-schema-setup.sql"/>
  <include file="db/changelog/database-1/finance/002-transactions.sql"/>
  <include file="db/changelog/database-1/finance/003-indexes-and-constraints.sql"/>
  <include file="db/changelog/database-1/finance/004-seed-data.sql"/>

  <!-- NEW: User management -->
  <include file="db/changelog/database-1/users/001-finance-app-user.sql"/>
  <include file="db/changelog/database-1/users/002-finance-readonly-user.sql"/>
</databaseChangeLog>
```

### Step 4: Test Password Retrieval (Local Testing)

```bash
# Test that passwords can be retrieved
./.github/scripts/get-user-password.sh "liquibase-users" "finance_app"
./.github/scripts/get-user-password.sh "liquibase-users" "finance_readonly"
```

### Step 5: Deploy via CI/CD

The standard deployment process will now:

1. **Discover** the user changesets in the changelog
2. **Process** password placeholders by reading from AWS Secrets Manager
3. **Replace** `{{PASSWORD:finance_app}}` with actual passwords
4. **Execute** the SQL to create users with real passwords
5. **Track** the changes in Liquibase changelog tables

## 🔍 What Happens During Deployment

### Before (Template with Placeholders):
```sql
CREATE USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP;
```

### After (Processed with Real Password):
```sql
CREATE USER finance_app IDENTIFIED BY "MySecureAppPassword123!"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP;
```

## ✅ Verification

After deployment, you can verify the users were created:

```sql
-- Check users exist
SELECT username, default_tablespace, account_status
FROM dba_users
WHERE username IN ('FINANCE_APP', 'FINANCE_READONLY');

-- Check privileges
SELECT grantee, privilege
FROM dba_sys_privs
WHERE grantee IN ('FINANCE_APP', 'FINANCE_READONLY');

-- Test connection (from application)
sqlplus finance_app/MySecureAppPassword123!@oracle-finance
```

## 🛡️ Security Benefits

1. **No Hardcoded Passwords**: Passwords never appear in version control
2. **Centralized Management**: All passwords managed in AWS Secrets Manager
3. **Access Control**: AWS IAM controls who can read/modify passwords
4. **Audit Trail**: All user creation tracked in Liquibase changelog
5. **Rotation Ready**: Easy to rotate passwords by updating the secret

## 🔄 Password Rotation Example

To rotate the finance_app password:

```bash
# 1. Update password in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id "liquibase-users" \
  --secret-string '{
    "finance_app": "NewRotatedPassword789!",
    "finance_readonly": "ReadOnlyPassword456!"
  }'

# 2. Create password rotation changeset
cat > db/changelog/database-1/users/003-rotate-finance-app-password.sql << 'EOF'
--liquibase formatted sql

--changeset user-management:rotate-finance_app-password
--comment: Rotate password for finance_app user
--runOnChange:true
ALTER USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}";
EOF

# 3. Include in changelog and deploy
```

## 📊 Supported User Types

The system supports creating various user types:

| User Type | PostgreSQL | MySQL | SQL Server | Oracle |
|-----------|------------|-------|------------|--------|
| Application User | ✅ ROLE with LOGIN | ✅ USER@'host' | ✅ LOGIN + USER | ✅ USER with tablespace |
| Read-Only User | ✅ SELECT privileges | ✅ SELECT grants | ✅ db_datareader | ✅ SELECT grants |
| Admin User | ✅ CREATEDB, etc. | ✅ ALL PRIVILEGES | ✅ db_owner | ✅ DBA role |
| Service Account | ✅ Limited privileges | ✅ Specific database | ✅ Application roles | ✅ Object privileges |

## 🚀 Next Steps

1. **Customize Templates**: Modify templates for your specific requirements
2. **Add More Users**: Create additional user configurations as needed
3. **Environment Separation**: Use different secret names for dev/staging/prod
4. **Integration**: Integrate with your application deployment process
5. **Monitoring**: Set up alerts for failed user creation/authentication

This system provides a production-ready, secure foundation for database user management across your entire infrastructure!