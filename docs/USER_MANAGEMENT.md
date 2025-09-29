# Database User Management with AWS Secrets Manager

This system provides a secure, standardized way to create and manage database users across multiple database platforms using Liquibase changesets with passwords stored in AWS Secrets Manager.

## 🏗️ Architecture Overview

### Components

1. **Templates** (`db/templates/users/`): Database-specific user creation templates
2. **Configuration Files** (`db/user-configs/`): YAML files defining user parameters
3. **Scripts** (`.github/scripts/`): Automation scripts for AWS Secrets Manager integration
4. **Generated Changesets** (`db/changelog/*/users/`): Final SQL changesets with password placeholders

### Supported Databases

- ✅ **PostgreSQL**: Roles with LOGIN capability
- ✅ **MySQL**: Users with host-based access control
- ✅ **SQL Server**: Logins and database users with role assignments
- ✅ **Oracle**: Users with tablespace quotas and privilege grants

## 🚀 Quick Start

### 1. Store User Passwords in AWS Secrets Manager

Create or update the secrets manager entry for user passwords:

```bash
# Create a new secret with user passwords
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --description "Database user passwords for Liquibase deployments" \
  --secret-string '{
    "finance_app": "SecureAppPassword123!",
    "finance_readonly": "ReadOnlyPassword456!",
    "myapp_user": "PostgresAppPass789!"
  }'

# Or update an existing secret
aws secretsmanager update-secret \
  --secret-id "liquibase-users" \
  --secret-string '{
    "finance_app": "SecureAppPassword123!",
    "finance_readonly": "ReadOnlyPassword456!"
  }'
```

### 2. Create User Configuration

Create a YAML configuration file (example for Oracle):

```yaml
# db/user-configs/my-app-user.yaml
username: "finance_app"
role_description: "Finance application service account"
database_name: "oracle-finance"
default_tablespace: "FINANCE_DATA"
temp_tablespace: "TEMP"
tablespace_quota: "500M"
user_profile: "DEFAULT"

system_privileges: |
  GRANT CREATE SESSION TO finance_app;
  GRANT CREATE TABLE TO finance_app;

object_privileges: |
  GRANT SELECT, INSERT, UPDATE, DELETE ON accounts TO finance_app;
  GRANT SELECT, INSERT, UPDATE, DELETE ON transactions TO finance_app;
```

### 3. Generate Changeset (when yq is available)

```bash
# Generate changeset from configuration
./.github/scripts/generate-user-changeset.sh oracle \
  db/user-configs/my-app-user.yaml \
  db/changelog/database-1/users/001-app-user.sql
```

### 4. Include in Main Changelog

Add the user changeset to your main changelog file:

```xml
<!-- changelog-oracle-finance.xml -->
<databaseChangeLog>
  <!-- ... existing includes ... -->
  <include file="db/changelog/database-1/users/001-app-user.sql"/>
</databaseChangeLog>
```

### 5. Deploy

The standard Liquibase pipeline will automatically:
- Read passwords from AWS Secrets Manager
- Replace `{{PASSWORD:username}}` placeholders
- Execute the user creation changesets

## 📁 File Structure

```
liquibase/
├── .github/scripts/
│   ├── get-user-password.sh       # Retrieves passwords from AWS
│   ├── run-user-changeset.sh      # Executes changesets with password substitution
│   └── generate-user-changeset.sh # Generates changesets from templates
├── db/
│   ├── templates/users/            # Database-specific templates
│   │   ├── postgresql-user-template.sql
│   │   ├── mysql-user-template.sql
│   │   ├── sqlserver-user-template.sql
│   │   └── oracle-user-template.sql
│   ├── user-configs/               # User configuration files
│   │   └── examples/
│   └── changelog/                  # Generated changesets
│       └── database-1/users/
└── docs/
    └── USER_MANAGEMENT.md          # This documentation
```

## 🛡️ Security Features

### Password Protection
- ✅ Passwords stored securely in AWS Secrets Manager
- ✅ No hardcoded passwords in version control
- ✅ Passwords masked in GitHub Actions logs
- ✅ Temporary files cleaned up after deployment

### Access Control
- ✅ AWS IAM controls access to secrets
- ✅ Principle of least privilege for database users
- ✅ Role-based permission templates
- ✅ Audit trail through Liquibase changelog tracking

## 📋 Configuration Reference

### Common Parameters (All Databases)
- `username`: Database username (required)
- `role_description`: Documentation/comment for the user
- `database_name`: Target database name

### PostgreSQL Specific
- `schema_name`: Default schema (default: "public")
- `additional_options`: Extra CREATE ROLE options
- `table_privileges`: Table-level permissions
- `sequence_privileges`: Sequence permissions

### MySQL Specific
- `host_pattern`: Host access pattern (default: "%")
- `database_privileges`: Database-level privileges

### SQL Server Specific
- `default_schema`: Default schema (default: "dbo")
- `role_memberships`: Database role assignments
- `specific_permissions`: Additional permissions

### Oracle Specific
- `default_tablespace`: Default tablespace (default: "USERS")
- `temp_tablespace`: Temporary tablespace (default: "TEMP")
- `tablespace_quota`: Tablespace quota (default: "100M")
- `user_profile`: User profile (default: "DEFAULT")
- `system_privileges`: System-level privileges
- `object_privileges`: Object-specific privileges
- `role_grants`: Predefined role assignments

## 🔧 Advanced Usage

### Custom Templates

You can create custom templates by copying and modifying the base templates:

```bash
cp db/templates/users/oracle-user-template.sql \
   db/templates/users/oracle-admin-template.sql
# Edit the new template for admin users
```

### Multiple Secret Stores

Use different secret names for different environments:

```bash
# Development
./get-user-password.sh "liquibase-users-dev" "app_user"

# Production
./get-user-password.sh "liquibase-users-prod" "app_user"
```

### Batch User Creation

Create multiple users efficiently:

```bash
for config in db/user-configs/prod-users/*.yaml; do
  output="db/changelog/database-1/users/$(basename $config .yaml).sql"
  ./generate-user-changeset.sh oracle "$config" "$output"
done
```

## 🚨 Troubleshooting

### Common Issues

1. **AWS Credentials Not Configured**
   ```
   Error: Unable to locate credentials
   ```
   Solution: Configure AWS CLI or set environment variables

2. **Secret Not Found**
   ```
   Error: Failed to retrieve secret 'liquibase-users'
   ```
   Solution: Verify secret name and AWS permissions

3. **User Already Exists**
   ```
   Error: ORA-01920: user name 'FINANCE_APP' conflicts with another user
   ```
   Solution: Preconditions should prevent this, check changeset IDs

4. **Invalid Password**
   ```
   Error: Password for user 'app_user' not found
   ```
   Solution: Verify username matches the key in AWS Secrets Manager

### Debugging

Enable debug output:
```bash
set -x  # Enable shell debugging
AWS_CLI_PROFILE=debug ./get-user-password.sh secret-name username
```

## 🔄 Integration with CI/CD

The user management system integrates seamlessly with the existing Liquibase CI/CD pipeline:

1. **Test Mode**: Validates changeset syntax without connecting to real databases
2. **Deploy Mode**: Reads passwords from AWS and creates users in production
3. **Rollback**: User creation changesets can be rolled back if needed
4. **Audit**: All changes tracked in Liquibase changelog tables

## 📈 Best Practices

1. **Password Rotation**: Regularly rotate passwords in AWS Secrets Manager
2. **Least Privilege**: Grant minimum required permissions to each user
3. **Documentation**: Always include meaningful role descriptions
4. **Testing**: Test user creation in development before production
5. **Monitoring**: Monitor user access patterns and failed login attempts
6. **Cleanup**: Remove unused users promptly
7. **Backup**: Back up user configurations along with your database schemas

---

## 🎯 Example Workflows

### Creating an Application User

1. Design the user requirements
2. Create configuration YAML
3. Generate changeset from template
4. Add password to AWS Secrets Manager
5. Include changeset in changelog
6. Deploy through CI/CD pipeline
7. Verify user access and permissions

### Rotating User Passwords

1. Generate new secure password
2. Update AWS Secrets Manager
3. Use ALTER USER changeset (with runOnChange:true)
4. Deploy password change
5. Update application configurations
6. Verify connectivity

This system provides a secure, auditable, and maintainable approach to database user management at scale.