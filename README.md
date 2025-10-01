# Liquibase Multi-Database CI/CD Pipeline

A production-ready, optimized Liquibase CI/CD pipeline supporting PostgreSQL, MySQL, SQL Server, and Oracle with AWS integration and automated database creation.

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
cp changelog-postgres-prod.xml changelog-postgres-prod-myappdb.xml

# Edit changelog to include your SQL files
sed -i 's|postgres-prod-server/userdb|postgres-prod-server/myappdb|g' changelog-postgres-prod-myappdb.xml
```

**IMPORTANT - Filename Mapping:**
- Changelog file: `changelog-postgres-prod-myappdb.xml`
- Secret name: `postgres-prod-myappdb`
- **The pipeline extracts the secret name from the changelog filename!**
- Pattern: `changelog-{SECRET_NAME}.xml` → looks up secret `{SECRET_NAME}`

**Directory naming:** `{server-name}/{database-name}/` - mirrors your actual RDS and database structure.

### 4. Test and Deploy

```bash
# Commit and test changes
git add changelog-postgres-prod-myappdb.xml
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

## Advanced Configuration

### Manual Database Creation

If you prefer to create databases manually instead of automatic creation:

```bash
# Create database ahead of time (optional)
./.github/scripts/create-database.sh postgresql myappdb
./.github/scripts/create-database.sh mysql ecommerce
./.github/scripts/create-database.sh sqlserver inventory
./.github/scripts/create-database.sh oracle finance
```

**Note:** You still need both master and application secrets in AWS Secrets Manager even with manual creation.

## Pipeline Behavior

| Branch Type | Action | AWS Credentials | Database Connection |
|-------------|--------|----------------|-------------------|
| Feature branches | Test & validate | Not needed | Offline mode |
| Pull requests | Test & preview | Not needed | Offline mode |
| Main branch (after PR merge) | Deploy changes | Required | Live databases |

## Features

- **Dynamic Discovery**: Automatically finds databases from changelog files
- **Branch-Aware**: Test mode on branches, deploy mode on main
- **Secure**: No credentials needed for testing
- **Parallel**: All databases deploy simultaneously
- **Auto-Create**: Creates missing databases automatically
- **Safe**: Uses `IF NOT EXISTS` for tables, continues on individual failures

## User Management

The pipeline includes AWS Secrets Manager integration for secure database user creation:

```bash
# Add user passwords to a separate secret
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --secret-string '{
    "finance_app": "SecureAppPassword123!",
    "finance_readonly": "ReadOnlyPassword456!"
  }'

# User changesets use password placeholders
CREATE USER finance_app IDENTIFIED BY "{{PASSWORD:finance_app}}";
```

See `docs/USER_MANAGEMENT.md` and `examples/DEMO_USER_CREATION.md` for complete setup guide.

## Documentation

- `docs/AWS-SETUP.md` - Complete AWS setup guide
- `docs/ORACLE_SETUP.md` - Oracle database configuration
- `docs/USER_MANAGEMENT.md` - Database user creation with AWS Secrets Manager
- `docs/SAFETY-TESTING-PLAN.md` - Comprehensive safety testing procedures
