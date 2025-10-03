# Liquibase Secrets Management Guide

## Overview

This system uses **per-server secrets** in AWS Secrets Manager to organize database credentials. Each database server (PostgreSQL, MySQL, SQL Server, Oracle) has its own secret containing:
- Master/superuser connection for creating databases
- Individual database connections
- Application user passwords for each database

## Secret Naming Convention

- `liquibase-postgres-prod` - PostgreSQL server
- `liquibase-mysql-prod` - MySQL server
- `liquibase-sqlserver-prod` - SQL Server instance
- `liquibase-oracle-prod` - Oracle instance

## Secret Structure

```json
{
  "master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://host:5432/postgres",
    "username": "postgres",
    "password": "master_password"
  },
  "databases": {
    "thedb": {
      "connection": {
        "url": "jdbc:postgresql://host:5432/thedb",
        "username": "admin_user",
        "password": "admin_password"
      },
      "users": {
        "app_readwrite": "rw_password",
        "app_readonly": "ro_password"
      }
    },
    "another_db": {
      "connection": {
        "url": "jdbc:postgresql://host:5432/another_db",
        "username": "admin_user",
        "password": "admin_password"
      },
      "users": {
        "api_user": "api_password"
      }
    }
  }
}
```

## Creating Secrets

Use the provided interactive scripts to create secrets:

### PostgreSQL
```bash
chmod +x .github/scripts/create-secret-postgres.sh
.github/scripts/create-secret-postgres.sh
```

### SQL Server
```bash
chmod +x .github/scripts/create-secret-sqlserver.sh
.github/scripts/create-secret-sqlserver.sh
```

### MySQL
```bash
chmod +x .github/scripts/create-secret-mysql.sh
.github/scripts/create-secret-mysql.sh
```

### Oracle
```bash
chmod +x .github/scripts/create-secret-oracle.sh
.github/scripts/create-secret-oracle.sh
```

Each script will:
1. Check if secret already exists (create or update mode)
2. Prompt for master connection details
3. Allow you to add multiple databases
4. For each database, allow you to add multiple users
5. Show a summary before creating/updating
6. Create or update the secret in AWS Secrets Manager

## Database Identifier Format

In your changelogs and workflows, use this format: `{server}-{dbname}`

Examples:
- `postgres-thedb` - PostgreSQL database named "thedb"
- `sqlserver-ecommerce` - SQL Server database named "ecommerce"
- `mysql-analytics` - MySQL database named "analytics"
- `oracle-erp` - Oracle database/schema named "erp"

## Changelog File Naming

Your changelog XML files should match the database identifier:
- `changelog-postgres-thedb.xml`
- `changelog-sqlserver-ecommerce.xml`
- `changelog-mysql-analytics.xml`

## Adding a New Database

### Option 1: Re-run the creation script
```bash
.github/scripts/create-secret-postgres.sh
```
The script detects existing secrets and lets you add new databases.

### Option 2: Manual update via AWS CLI

```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Add new database using jq
NEW_SECRET=$(echo "$SECRET" | jq \
  '.databases.newdb = {
    connection: {
      url: "jdbc:postgresql://host:5432/newdb",
      username: "admin",
      password: "admin_pass"
    },
    users: {
      "app_user": "app_pass"
    }
  }')

# Update secret
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$NEW_SECRET"
```

## Adding Users to Existing Database

```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Add user to existing database
NEW_SECRET=$(echo "$SECRET" | jq \
  '.databases.thedb.users.new_user = "new_password"')

# Update secret
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$NEW_SECRET"
```

## Viewing Secret Contents

```bash
# PostgreSQL
aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text | jq .

# SQL Server
aws secretsmanager get-secret-value \
  --secret-id liquibase-sqlserver-prod \
  --query SecretString --output text | jq .

# MySQL
aws secretsmanager get-secret-value \
  --secret-id liquibase-mysql-prod \
  --query SecretString --output text | jq .

# Oracle
aws secretsmanager get-secret-value \
  --secret-id liquibase-oracle-prod \
  --query SecretString --output text | jq .
```

## How Scripts Use Secrets

### configure-database.sh
Parses `postgres-thedb` → reads `liquibase-postgres-prod` → extracts `.databases.thedb.connection`

### create-database.sh
Uses `.master` connection to create database, then updates `.databases.{dbname}` entry

### manage-users.sh
Reads `.databases.{dbname}.users` to set passwords for application users

## Migration from Old Structure

If you have existing secrets in the old format (`liquibase-databases`, `liquibase-users`), you'll need to:

1. Run the creation scripts for each database server type
2. Manually input your existing connection details
3. Test with workflow dispatch in test mode
4. Once verified, delete old secrets (optional)

## Benefits of This Structure

✅ **Scalability**: Supports 100+ databases per server
✅ **Organization**: All databases for a server in one secret
✅ **No Conflicts**: Users are scoped to specific databases
✅ **Clear Hierarchy**: master → databases → users
✅ **Easy to Navigate**: Use database name to find all related info
✅ **Version Controlled**: Secret structure is documented and consistent

## Troubleshooting

### Database not found error
```
❌ Database 'thedb' not found in secret 'liquibase-postgres-prod'
```
**Solution**: Add the database using the creation script or manual update

### User passwords not set
```
ℹ️  No users configured for database 'thedb'
```
**Solution**: Add users to `.databases.thedb.users` in the secret

### Wrong server type
```
❌ Cannot determine database type from server name 'pg'
```
**Solution**: Use standard server names: `postgres`, `mysql`, `sqlserver`, `oracle`
