# Liquibase CI/CD Setup Guide

Complete setup guide for Liquibase with AWS Secrets Manager and GitHub Actions.

## Prerequisites

- AWS Account with admin access
- GitHub repository with Actions enabled
- Access to database servers (PostgreSQL, MySQL, SQL Server, Oracle)

---

## 1. AWS IAM Setup

### Create GitHub OIDC Provider

Check if it already exists:
```bash
aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `token.actions.githubusercontent.com`)]'
```

If empty, create it:
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Create IAM Role for GitHub Actions

**Step 1:** Create `trust-policy.json` (replace YOUR_ACCOUNT_ID, YOUR_GITHUB_USERNAME, YOUR_REPO_NAME):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/main",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/*",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:pull_request"
          ]
        }
      }
    }
  ]
}
```

**Step 2:** Create `permissions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:*:*:secret:liquibase-*"
      ]
    }
  ]
}
```

**Step 3:** Create the IAM role:

```bash
# Create the role
aws iam create-role \
  --role-name GitHubActionsLiquibaseRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for GitHub Actions to access Liquibase database credentials"

# Attach permissions
aws iam put-role-policy \
  --role-name GitHubActionsLiquibaseRole \
  --policy-name LiquibaseSecretsAccess \
  --policy-document file://permissions-policy.json

# Get the role ARN (save this for GitHub configuration)
aws iam get-role \
  --role-name GitHubActionsLiquibaseRole \
  --query 'Role.Arn' \
  --output text
```

---

## 2. AWS Secrets Manager Setup

This system uses **per-server secrets** - one secret per database server containing multiple databases and users.

### Secret Structure

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
    }
  }
}
```

### Create Secrets Using Interactive Scripts

**PostgreSQL:**
```bash
.github/scripts/create-secret-postgres.sh
```

**MySQL:**
```bash
.github/scripts/create-secret-mysql.sh
```

**SQL Server:**
```bash
.github/scripts/create-secret-sqlserver.sh
```

**Oracle:**
```bash
.github/scripts/create-secret-oracle.sh
```

Each script will:
1. Check if secret already exists
2. Prompt for master connection details
3. Allow you to add multiple databases
4. For each database, allow you to add multiple users
5. Create or update the secret in AWS Secrets Manager

### Secret Naming Convention

- `liquibase-postgres-prod` - PostgreSQL server
- `liquibase-mysql-prod` - MySQL server
- `liquibase-sqlserver-prod` - SQL Server instance
- `liquibase-oracle-prod` - Oracle instance

### Bulk Setup for Multiple Servers

If you have dozens of servers:

```bash
.github/scripts/setup-multiple-servers.sh
```

This script creates secrets for multiple servers efficiently.

---

## 3. Database-Specific Setup

### PostgreSQL

**Requirements:**
- PostgreSQL 12+
- Network access from GitHub Actions
- User with `CREATEDB` privilege for auto-database creation

**Master Connection:**
```json
{
  "master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-host:5432/postgres",
    "username": "postgres",
    "password": "your_password"
  }
}
```

**User Privileges:**
```sql
-- For master user
GRANT CREATEDB TO postgres;

-- For application admin user
GRANT CONNECT, CREATE ON DATABASE yourdb TO admin_user;
```

---

### MySQL

**Requirements:**
- MySQL 8.0+ or MariaDB 10.5+
- Network access from GitHub Actions
- User with `CREATE DATABASE` privilege

**Master Connection:**
```json
{
  "master": {
    "type": "mysql",
    "url": "jdbc:mysql://your-host:3306/mysql?useSSL=true&serverTimezone=UTC",
    "username": "root",
    "password": "your_password"
  }
}
```

**User Privileges:**
```sql
-- For master user
GRANT CREATE, CREATE USER ON *.* TO 'root'@'%';
FLUSH PRIVILEGES;
```

---

### SQL Server

**Requirements:**
- SQL Server 2017+
- Network access from GitHub Actions
- User with `CREATE DATABASE` privilege

**Master Connection:**
```json
{
  "master": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://your-host:1433;databaseName=master;encrypt=true;trustServerCertificate=true",
    "username": "sa",
    "password": "your_password"
  }
}
```

**User Privileges:**
```sql
-- For master user
ALTER SERVER ROLE sysadmin ADD MEMBER [sa];
-- Or at minimum:
GRANT CREATE DATABASE TO [sa];
```

**SSL Note:** The pipeline automatically adds `encrypt=false;trustServerCertificate=true` if not present in the URL.

---

### Oracle

**Requirements:**
- Oracle 12c+ or Oracle RDS
- Network access from GitHub Actions
- User with DBA privileges or equivalent

**Master Connection:**
```json
{
  "master": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@your-host:1521/ORCL",
    "username": "admin",
    "password": "your_password"
  }
}
```

**User Privileges:**
```sql
-- For master user
GRANT CONNECT, RESOURCE TO admin;
GRANT CREATE SESSION TO admin;
GRANT CREATE TABLE TO admin;
GRANT CREATE SEQUENCE TO admin;
GRANT CREATE VIEW TO admin;
```

**URL Format Notes:**
- Service Name format: `jdbc:oracle:thin:@//host:port/service`
- SID format: `jdbc:oracle:thin:@host:port:SID`
- The pipeline auto-converts SID to Service Name format
- Default service name: `ORCL`

**Common Oracle Issues:**

| Error | Solution |
|-------|----------|
| `ORA-12505` (SID not known) | ✅ Fixed automatically - URL converted to service name |
| `ORA-12514` (Service not known) | ✅ Fixed automatically - uses `ORCL` service name |
| `ORA-01017` (Invalid credentials) | Update AWS Secrets Manager with correct credentials |
| `ORA-00942` (Table not found) | ✅ Normal - Liquibase will create tracking tables |

---

## 4. GitHub Repository Configuration

Go to **Settings > Secrets and variables > Actions > Variables** and add:

- `AWS_ROLE_ARN`: The ARN from step 1 above (e.g., `arn:aws:iam::123456789:role/GitHubActionsLiquibaseRole`)
- `AWS_REGION`: Your AWS region (e.g., `us-east-1`)

**No other variables needed!** The pipeline auto-discovers everything from changelog files and secrets.

---

## 5. Create Your First Database

### Step 1: Add Database to Server Secret

Use the interactive script:

```bash
.github/scripts/add-database-to-server.sh
```

Or manually:

```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Add new database using jq
UPDATED=$(echo "$SECRET" | jq \
  '.databases.myapp = {
    connection: {
      url: "jdbc:postgresql://host:5432/myapp",
      username: "admin",
      password: "admin_pass"
    },
    users: {
      "app_user": "app_password"
    }
  }')

# Save back to AWS
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$UPDATED"
```

### Step 2: Create Changelog File

Create `changelog-postgres-myapp.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
    http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.9.xsd">

    <!-- Users -->
    <include file="db/changelog/postgres/myapp/users/001-create-users.sql" relativeToChangelogFile="true"/>

    <!-- Tables -->
    <include file="db/changelog/postgres/myapp/tables/001-create-tables.sql" relativeToChangelogFile="true"/>

</databaseChangeLog>
```

**Important:** Changelog filename must match the database identifier: `changelog-{server}-{dbname}.xml`

### Step 3: Create SQL Changesets

Create `db/changelog/postgres/myapp/users/001-create-users.sql`:

```sql
--liquibase formatted sql

--changeset admin:001 splitStatements:false
--comment: Create application user
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE USER app_user WITH PASSWORD 'CHANGE_ME_TEMP_PASSWORD';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE myapp TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
```

Create `db/changelog/postgres/myapp/tables/001-create-tables.sql`:

```sql
--liquibase formatted sql

--changeset admin:002
--comment: Create initial tables
CREATE TABLE IF NOT EXISTS users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(320) UNIQUE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### Step 4: Test and Deploy

```bash
# Create feature branch
git checkout -b feature/add-myapp-db

# Add all files
git add .
git commit -m "Add myapp database"
git push origin feature/add-myapp-db

# Pipeline runs in TEST mode automatically
# - Validates SQL syntax
# - Generates SQL preview
# - No database connection required

# Create PR
gh pr create --title "Add myapp database" --body "Initial database setup"

# After approval, merge to main
# Pipeline runs in DEPLOY mode:
# - Creates database
# - Runs changesets
# - Sets user passwords from AWS Secrets Manager
```

---

## 6. Local Development Setup

Copy the template and configure:

```bash
# Copy template
cp liquibase.properties.template liquibase.properties

# Edit with your local database credentials
vim liquibase.properties
```

Set environment variables:

```bash
# PostgreSQL example
export LIQUIBASE_CHANGELOG_FILE=changelog-postgres-myapp.xml
export LIQUIBASE_URL=jdbc:postgresql://localhost:5432/myapp
export LIQUIBASE_USERNAME=postgres
export LIQUIBASE_PASSWORD=your_local_password
export LIQUIBASE_DRIVER=org.postgresql.Driver
```

Run Liquibase locally:

```bash
# Validate changelog
liquibase --defaults-file=liquibase.properties validate

# Preview SQL
liquibase --defaults-file=liquibase.properties update-sql

# Apply changes
liquibase --defaults-file=liquibase.properties update
```

---

## 7. Verify Setup

### Test the Pipeline

Create a test branch:

```bash
git checkout -b test/setup-verification
git push origin test/setup-verification
```

The pipeline should:
- ✅ Discover all databases from changelog files
- ✅ Run in test mode (no AWS credentials needed)
- ✅ Validate SQL syntax
- ✅ Generate SQL previews

### Test Deployment

Trigger a manual deployment:

```bash
gh workflow run liquibase-cicd.yml \
  -f action=deploy \
  -f database=postgres-myapp
```

The pipeline should:
- ✅ Connect to AWS Secrets Manager
- ✅ Create database if needed
- ✅ Deploy changesets
- ✅ Set user passwords

---

## Security Features

- ✅ **OIDC Authentication**: No long-lived AWS keys in GitHub
- ✅ **Least Privilege**: IAM role has minimal required permissions
- ✅ **Password Masking**: Passwords automatically masked in logs
- ✅ **Secure Storage**: All credentials in AWS Secrets Manager
- ✅ **Per-Server Secrets**: Organized by database server
- ✅ **User Passwords Separate**: Application user passwords in `.databases.{dbname}.users`

---

## Troubleshooting

### "Secret value can't be converted to key name and value pairs"

**Cause:** Invalid JSON format in AWS Secrets Manager

**Solution:**
- Use "Plaintext" tab in AWS Console, not "Key/value pairs"
- Validate JSON format before uploading
- Use `jq` to validate: `echo "$JSON" | jq .`

### "Permission denied on Secrets Manager"

**Cause:** IAM role ARN incorrect or permissions missing

**Solution:**
- Verify the IAM role ARN in GitHub variables
- Check the permission policy includes correct secret ARNs (`liquibase-*`)
- Test with AWS CLI: `aws secretsmanager get-secret-value --secret-id liquibase-postgres-prod`

### "Database not found in secret"

**Cause:** Database not added to the per-server secret

**Solution:**
```bash
# Check what's in the secret
aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text | jq '.databases | keys'

# Add the missing database
.github/scripts/add-database-to-server.sh
```

### Pipeline can't find changelog file

**Cause:** Changelog filename doesn't match secret structure

**Solution:**
- Changelog must be: `changelog-{server}-{dbname}.xml`
- Example: `changelog-postgres-myapp.xml` matches secret key in `liquibase-postgres-prod.databases.myapp`

---

## Next Steps

- **User Management**: See [USER-MANAGEMENT.md](USER-MANAGEMENT.md) for creating and managing database users
- **Workflow Modes**: See [WORKFLOW-GUIDE.md](WORKFLOW-GUIDE.md) for understanding test vs deploy modes
- **Reference**: See [REFERENCE.md](REFERENCE.md) for secrets management and Docker container details

---

## Quick Reference

### Common Commands

```bash
# View secret contents
aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text | jq .

# Add database to server
.github/scripts/add-database-to-server.sh

# Update user password
.github/scripts/update-secret.sh postgres add-user myapp app_user new_password

# Test specific database
gh workflow run liquibase-cicd.yml -f action=test -f database=postgres-myapp

# Deploy specific database
gh workflow run liquibase-cicd.yml -f action=deploy -f database=postgres-myapp
```

### Database Identifier Format

- Format: `{server}-{dbname}`
- Examples:
  - `postgres-myapp` → PostgreSQL database named "myapp"
  - `mysql-ecommerce` → MySQL database named "ecommerce"
  - `sqlserver-inventory` → SQL Server database named "inventory"
  - `oracle-erp` → Oracle database/schema named "erp"

### Changelog File Naming

Changelog XML files must match the database identifier:
- `changelog-postgres-myapp.xml`
- `changelog-mysql-ecommerce.xml`
- `changelog-sqlserver-inventory.xml`
- `changelog-oracle-erp.xml`
