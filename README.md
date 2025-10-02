# Liquibase Multi-Database CI/CD Pipeline

A production-ready, optimized Liquibase CI/CD pipeline supporting PostgreSQL, MySQL, SQL Server, and Oracle with AWS integration and automated database creation.

## Prerequisites

**Before using this pipeline, complete the AWS setup:**

- **AWS Setup**: Configure IAM roles and Secrets Manager → `docs/1-AWS-SETUP.md`

This is required for the pipeline to function. See the [full documentation](#documentation) below for complete setup.

## Overview

This pipeline automatically:

- **Discovers databases** from changelog files
- **Tests on feature branches** (offline validation)
- **Deploys on main branch** (after PR approval)
- **Creates databases** automatically if they don't exist
- **Uses safety patterns** (`IF NOT EXISTS` for tables, `CREATE OR REPLACE` for functions only)

**Directory Structure:**
```text
db/changelog/
└── postgres-prod-server/        # RDS instance name
    ├── userdb/                  # Database 1 on this server
    │   ├── 001-initial-schema.sql
    │   ├── 002-user-management.sql
    │   └── 003-add-indexes.sql
    └── myappdb/                 # Database 2 on this server
        ├── 001-initial-schema.sql
        ├── 002-user-management.sql
        └── 003-add-indexes.sql
```

## Quick Start

### 1. Create Feature Branch

```bash
# Start with a feature branch for your database changes
git checkout -b add-myappdb
```

### 2. Add Database Configuration

**You need TWO types of secrets in AWS Secrets Manager:**

#### A) Master Database Secret (Required Once Per RDS Server)

This gives the pipeline permission to CREATE new databases on your RDS server:

```json
{
  "postgres-master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/postgres",
    "username": "postgres_user",
    "password": "your-master-password"
  }
}
```

**Key Points:**
- Points to the **system database** (`/postgres` not `/myappdb`)
- User must have **CREATE DATABASE privileges**
- Only needed **once per RDS server** - can create unlimited databases
- Used by pipeline to create databases that don't exist

#### B) Application Database Secret (Required For Each Database)

This tells the pipeline how to connect to your specific database:

```json
{
  "postgres-master": { ... from above ... },
  "postgres-myappdb": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/myappdb",
    "username": "postgres_user",
    "password": "your-password"
  }
}
```

**Key Points:**
- Points to your **application database** (`/myappdb`)
- Used for deploying changesets to your database
- Pipeline uses this to discover which databases to deploy to

#### Examples for All Platforms

```json
{
  "postgres-master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/postgres",
    "username": "postgres_user",
    "password": "master-password"
  },
  "postgres-myappdb": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/myappdb",
    "username": "postgres_user",
    "password": "app-password"
  },
  "mysql-master": {
    "type": "mysql",
    "url": "jdbc:mysql://your-rds-endpoint:3306/mysql",
    "username": "root",
    "password": "master-password"
  },
  "mysql-ecommerce": {
    "type": "mysql",
    "url": "jdbc:mysql://your-rds-endpoint:3306/ecommerce",
    "username": "mysql_user",
    "password": "app-password"
  },
  "sqlserver-master": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://your-rds-endpoint:1433;databaseName=master",
    "username": "sa",
    "password": "master-password"
  },
  "sqlserver-inventory": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://your-rds-endpoint:1433;databaseName=inventory",
    "username": "sqlserver_user",
    "password": "app-password"
  },
  "oracle-master": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@your-rds-endpoint:1521:ORCL",
    "username": "admin",
    "password": "master-password"
  },
  "oracle-finance": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@your-rds-endpoint:1521:ORCL",
    "username": "admin",
    "password": "app-password"
  }
}
```

**How It Works:**
1. **Step 1**: Pipeline scans for `changelog-postgres-myappdb.xml` file → extracts secret name `postgres-myappdb`
2. **Step 2**: Pipeline finds `postgres-myappdb` secret → discovers you want a database called `myappdb`
3. **Step 3**: Pipeline checks if `myappdb` database exists
4. **Step 4**: If not, pipeline uses `postgres-master` secret to CREATE the database
5. **Step 5**: Pipeline uses `postgres-myappdb` secret to deploy your changesets

### 3. Create Your Changesets

```bash
# Create directory structure
mkdir -p db/changelog/postgres-prod-server/myappdb/

# Create your SQL changeset files
cat > db/changelog/postgres-prod-server/myappdb/001-initial-schema.sql << 'EOF'
--liquibase formatted sql

--changeset myapp-team:001-create-users-table
--comment: Create users table for myappdb
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(320) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    profile JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
EOF

# Copy and customize the changelog template
cp changelog-postgres-prod.xml changelog-postgres-myappdb.xml

# Edit changelog to include your SQL files
sed -i 's|postgres-prod-server/userdb|postgres-prod-server/myappdb|g' changelog-postgres-myappdb.xml
```

**IMPORTANT - Filename Mapping:**
- Changelog file: `changelog-postgres-myappdb.xml`
- Secret name: `postgres-myappdb`
- **The pipeline extracts the secret name from the changelog filename!**
- Pattern: `changelog-{SECRET_NAME}.xml` → looks up secret `{SECRET_NAME}`

**Directory naming:** `{server-name}/{database-name}/` - mirrors your actual RDS and database structure.

## Safety & Testing

### GitHub Actions Testing
The pipeline automatically tests all changes safely:

- **Feature branches**: Test mode only (no database connections)
- **Pull requests**: Validation + code review
- **Main branch**: Deploy mode (after PR approval)

### What to Review in GitHub Actions
Check the action results for:
- **SQL Preview**: Download generated SQL files to review changes
- **Safety Analysis**: Confirms IF NOT EXISTS patterns
- **Validation Results**: Ensures proper changeset format

### Key Safety Rules
1. Never merge without GitHub Actions showing green checkmarks
2. Always review the generated SQL preview files
3. Use feature branches and code review for all changes
4. Monitor deployment logs during production runs

### Test and Deploy Workflow

```bash
# Commit and test changes
git add changelog-postgres-myappdb.xml
git add db/changelog/postgres-prod-server/myappdb/
git commit -m "Add myappdb database with initial schema"
git push origin add-myappdb
# → Pipeline validates changesets in offline mode

# Create Pull Request and get approval
gh pr create --title "Add myappdb database" --body "Adds new myappdb database with user management schema"
# → Get PR reviewed and approved by team

# Merge PR to main triggers deployment
# Once PR is approved and merged to main:
# → Pipeline automatically creates myappdb database if it doesn't exist
# → Then deploys your changesets to the new database
```

## Pipeline Behavior

The pipeline has two modes controlled by the `action` input (default: `auto`):

### Test Mode
- **When**: Feature branches, pull requests, or manual `action=test`
- **What it does**:
  - Validates SQL syntax
  - Runs Liquibase offline validation
  - Generates SQL preview files
  - Does NOT connect to databases
  - Does NOT set user passwords
- **AWS Credentials**: Not required

### Deploy Mode
- **When**: Main branch (after PR merge) or manual `action=deploy`
- **What it does**:
  - Creates databases if they don't exist
  - Deploys Liquibase changesets to live databases
  - Sets real user passwords from AWS Secrets Manager
  - Connects to actual databases
- **AWS Credentials**: Required

### Manual Workflow Triggers

```bash
# Test mode (validate only, no database connections)
gh workflow run liquibase-cicd.yml -f action=test -f database=all

# Deploy mode (connect and deploy to databases)
gh workflow run liquibase-cicd.yml -f action=deploy -f database=sqlserver

# Auto mode (decides based on branch)
gh workflow run liquibase-cicd.yml  # defaults to auto
```

| Mode | AWS Credentials | Database Connection | User Password Management |
|------|----------------|-------------------|------------------------|
| Test | Not needed | Offline validation only | Skipped |
| Deploy | Required | Live databases | Passwords set from AWS Secrets Manager |

## Features

- **Dynamic Discovery**: Automatically finds databases from changelog files
- **Mode-Aware**: Test mode for validation, deploy mode for actual deployments
- **Secure**: No credentials needed for testing, AWS Secrets Manager for passwords
- **Parallel**: All databases deploy simultaneously via matrix strategy
- **Auto-Create**: Creates missing databases automatically
- **Safe**: Uses `IF NOT EXISTS` for tables, preconditions for users
- **Docker-Based**: Custom container with all database tools pre-installed (PostgreSQL, MySQL, Oracle, SQL Server)
- **Multi-Platform**: Supports PostgreSQL, MySQL, SQL Server, and Oracle

## User Management

The pipeline uses a two-step approach for secure user creation:

### Step 1: Liquibase Creates Users (Temporary Password)

User changesets create users with temporary passwords:

```sql
--liquibase formatted sql

--changeset DM-6001:001
--comment: Create application user
-- Note: Real password set by manage-users.sh after deployment
CREATE USER finance_app IDENTIFIED BY "TemporaryPassword123"
    DEFAULT TABLESPACE FINANCE_DATA
    TEMPORARY TABLESPACE TEMP;

GRANT CREATE SESSION TO finance_app;
GRANT CREATE TABLE TO finance_app;
```

### Step 2: Pipeline Sets Real Passwords

After Liquibase deployment, the `manage-users.sh` script automatically sets real passwords from AWS Secrets Manager:

```bash
# Store user passwords in AWS Secrets Manager
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --secret-string '{
    "finance_app": "SecureAppPassword123!",
    "finance_readonly": "ReadOnlyPassword456!",
    "myapp_readwrite": "MyAppPassword789!",
    "ecommerce_app": "EcommercePassword012!",
    "inventory_app": "InventoryPassword345!"
  }'
```

**How it works:**
1. Liquibase creates users/logins with temporary passwords (tracked in version control)
2. `manage-users.sh` script runs after deployment and sets real passwords from AWS Secrets Manager
3. Passwords are never stored in version control, only in AWS Secrets Manager

**Important:** Only runs in **deploy mode** (main branch or manual deploy action), not in test mode.

See `docs/3-USER-MANAGEMENT.md` for complete setup guide.

## Current Status - All Databases Working

- **PostgreSQL**: `postgres-prod-myappdb`, `postgres-prod-userdb` - Deployed successfully
- **MySQL**: `mysql-ecommerce` - Deployed successfully
- **SQL Server**: `sqlserver-inventory` - Deployed successfully with T-SQL syntax
- **Oracle**: `oracle-finance` - Deployed successfully to ADMIN schema
- **User Management**: AWS Secrets Manager integration ready

## Performance Optimizations

- **Minimal setup**: Lightweight configuration without heavy dependencies
- **Smart AWS permissions**: Graceful handling of limited Secrets Manager access
- **Conditional database creation**: Only creates databases when needed
- **Parallel execution**: Matrix strategy for concurrent database deployments

## Documentation

Complete documentation for setup and usage:

### Setup Guides (Read in Order)

1. **[AWS Setup](docs/1-AWS-SETUP.md)** - AWS IAM roles and Secrets Manager configuration
   - OIDC provider setup
   - IAM role creation
   - Secrets Manager configuration
   - GitHub repository variables

2. **[Oracle Setup](docs/2-ORACLE-SETUP.md)** - Oracle-specific configuration (if using Oracle)
   - Oracle RDS requirements
   - User privileges
   - Connection troubleshooting

3. **[User Management](docs/3-USER-MANAGEMENT.md)** - Database user creation with AWS Secrets Manager
   - Two-step approach (Liquibase + password script)
   - Platform-specific examples (Oracle, PostgreSQL, MySQL, SQL Server)
   - Password rotation
   - Troubleshooting

### Reference Documentation

4. **[Docker Container](docs/4-DOCKER-CONTAINER.md)** - Custom container with pre-installed tools
   - What's included (database clients, JDBC drivers, tools)
   - Build process and optimizations
   - Local development usage
   - Troubleshooting

5. **[Workflow Modes](docs/5-WORKFLOW-MODES.md)** - Test vs Deploy modes
   - When each mode runs
   - What each mode does
   - Manual triggers
   - Best practices and troubleshooting
