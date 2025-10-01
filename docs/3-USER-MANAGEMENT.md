# Database User Management

Secure database user creation using Liquibase changesets with passwords stored in AWS Secrets Manager.

## Quick Setup

### 1. Store User Passwords in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --secret-string '{
    "finance_app": "SecurePassword123!",
    "finance_readonly": "ReadOnlyPassword456!",
    "mysql_app_user": "MySQLPassword789!",
    "sqlserver_app_user": "SQLServerPassword012!"
  }'
```

### 2. Use Password Templates in SQL Changesets

```sql
--liquibase formatted sql

--changeset DM-6001:001
--comment: Create application user
CREATE USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP;

GRANT CREATE SESSION TO finance_app;
GRANT CREATE TABLE TO finance_app;
```

### 3. Deploy

The pipeline automatically:
- Replaces `{{PASSWORD:username}}` with real passwords from AWS
- Executes user creation changesets
- Restores template files afterward

## Current Password Template Mappings

### Oracle (`oracle-finance`)
- `finance_app` - Application user with full access
- `finance_readonly` - Read-only reporting user

### MySQL (`mysql-ecommerce`)
- `mysql_app_user` - Application user
- `mysql_report_user` - Reporting user

### SQL Server (`sqlserver-inventory`)
- `sqlserver_app_user` - Application login/user
- `sqlserver_report_user` - Reporting login/user

## How It Works

1. **Template Processing**: Before deployment, password templates are replaced with real passwords from AWS Secrets Manager
2. **Secure Deployment**: Liquibase executes changesets with actual passwords
3. **Cleanup**: Original template files are restored, temporary files cleaned up
4. **Security**: Passwords are masked in logs and never stored in repository

## Security Features

- ✅ No hardcoded passwords in version control
- ✅ Passwords stored securely in AWS Secrets Manager
- ✅ Passwords masked in GitHub Actions logs
- ✅ AWS IAM controls access to secrets
- ✅ Audit trail through Liquibase changelog tracking

## Configuration

Set these GitHub repository variables:
- `USER_SECRET_NAME` (optional): AWS secret name containing user passwords (default: `liquibase-users`)

## Example: Adding a New User

1. **Add password to AWS Secrets Manager**:
   ```bash
   # Get current secret and add new password
   current=$(aws secretsmanager get-secret-value --secret-id liquibase-users --query SecretString --output text)
   updated=$(echo "$current" | jq '. + {"new_user": "NewPassword123!"}')
   aws secretsmanager put-secret-value --secret-id liquibase-users --secret-string "$updated"
   ```

2. **Create SQL changeset**:
   ```sql
   --changeset DM-6010:010
   --comment: Create new analytics user
   CREATE USER analytics_user IDENTIFIED BY "{{PASSWORD:new_user}}";
   GRANT SELECT ON schema.* TO analytics_user;
   ```

3. **Deploy**: The pipeline handles password substitution automatically.

## Password Rotation

Update the secret in AWS Secrets Manager and create an ALTER USER changeset:

```sql
--changeset DM-6011:011
--comment: Rotate user password
--runOnChange:true
ALTER USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}";
```

That's it! The user management system provides secure, automated database user creation across all platforms.