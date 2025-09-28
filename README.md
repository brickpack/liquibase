# Liquibase CI/CD Pipeline

A secure, branch-aware Liquibase CI/CD pipeline with AWS integration. Currently configured for PostgreSQL with multi-platform support ready to implement.

## Quick Start

### 1. Create Your Changesets

Write SQL changes as Liquibase-formatted files organized by RDS server and database:

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

# Example structure for additional servers:
# ├── postgres-dev-server/      # Different RDS instance
# │   └── testdb/
# │       └── 001-test-schema.sql
# └── mysql-prod-server/        # MySQL RDS instance
#     └── ecommerce/
#         └── 001-products.sql
```

Example changeset file (`db/changelog/postgres-prod-server/myappdb/001-initial-schema.sql`):

```sql
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
```

**Directory naming:** `{server-name}/{database-name}/` - mirrors your actual RDS and database structure.

### 2. Set Up Your Database

The pipeline automatically discovers databases from AWS Secrets Manager, but the RDS instance must exist first.

**Understanding Database Creation:**

Think of your RDS instance like an apartment building:

- **RDS Instance** = The building
- **Master Database** = Building manager's office (`/postgres` system database)
- **Application Databases** = Individual apartments (`/userdb`, `/myappdb`, etc.)

To create new "apartments" (databases), you need access to the "building manager" (master config).

**Prerequisites:** Master configuration in AWS Secrets Manager (examples for each platform):

```json
{
  "postgres-master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/postgres",
    "username": "postgres_user",
    "password": "your-master-password"
  },
  "mysql-master": {
    "type": "mysql",
    "url": "jdbc:mysql://your-rds-endpoint:3306/mysql",
    "username": "root",
    "password": "your-master-password"
  },
  "sqlserver-master": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://your-rds-endpoint:1433;databaseName=master",
    "username": "sa",
    "password": "your-master-password"
  },
  "oracle-master": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@your-rds-endpoint:1521:XE",
    "username": "system",
    "password": "your-master-password"
  }
}
```

**Requirements:**

- Points to the **system database** (`/postgres`, `/mysql`, `/master`, etc.) not an application database
- User must have **CREATE DATABASE privileges**
- Used to create **all new databases** on this RDS server
- **One master config per RDS instance** - creates unlimited application databases

### Step A: Add Database Config to Secrets

Add your new database configuration to the existing AWS Secrets Manager secret (examples for each platform):

```json
{
  "postgres-master": { ... existing ... },
  "postgres-myappdb": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/myappdb",
    "username": "postgres_user",
    "password": "your-password"
  },
  "mysql-ecommerce": {
    "type": "mysql",
    "url": "jdbc:mysql://your-rds-endpoint:3306/ecommerce",
    "username": "mysql_user",
    "password": "your-password"
  },
  "sqlserver-inventory": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://your-rds-endpoint:1433;databaseName=inventory",
    "username": "sql_user",
    "password": "your-password"
  },
  "oracle-finance": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@your-rds-endpoint:1521:finance",
    "username": "oracle_user",
    "password": "your-password"
  }
}
```

### Step B: Set Up Changelog

```bash
# Copy the changelog template
cp changelog-postgres-prod.xml changelog-postgres-prod-myappdb.xml

# Edit to include your SQL files:
# <include file="db/changelog/postgres-prod-server/myappdb/001-schema.sql"/>
```

### Step C: Deploy Changes

```bash
# Feature branch: Test & validate (no database creation)
git checkout -b feature/add-myappdb
git add changelog-postgres-prod-myappdb.xml
git add db/changelog/postgres-prod-server/myappdb/
git push origin feature/add-myappdb
# → Pipeline validates changesets in offline mode

# Main branch: Automatically creates database + deploys changes
git checkout main && git merge feature/add-myappdb
git push origin main
# → Pipeline automatically creates myappdb database if it doesn't exist
# → Then deploys your changesets to the new database
```

### Alternative: Manual Database Creation

If you prefer to create the database manually (using AWS Console, CLI, or other tools), you still need to add the database configuration to AWS Secrets Manager:

```json
{
  "postgres-myapp": {
    "type": "postgresql",
    "url": "jdbc:postgresql://your-rds-endpoint:5432/myapp",
    "username": "postgres_user",
    "password": "your-password"
  }
}
```

**Manual Operation (Optional):**

```bash
# Only needed if you want to create the database ahead of time
./.github/scripts/create-database.sh postgresql myappdb
```

## Pipeline Behavior

| Branch Type | Action | AWS Credentials | Database Connection |
|-------------|--------|----------------|-------------------|
| Feature branches | Test & validate | ❌ Not needed | Offline mode |
| Main branch | Deploy changes | ✅ Required | Live databases |
| Pull requests | Test & preview | ❌ Not needed | Offline mode |

## Features

- 🔍 **Dynamic Discovery**: Automatically finds databases
- 🌿 **Branch-Aware**: Different behavior per branch type
- 🔒 **Secure**: No credentials needed for testing
- 🚀 **Parallel**: All databases deploy simultaneously
- 📋 **Previews**: SQL previews for all changes
- 🛡️ **Safe**: Continue on individual database failures

## Adding Databases

1. Create `changelog-<name>.xml` file
2. Add database entry to consolidated AWS secret `liquibase-databases`
3. Push changes - pipeline automatically discovers the new database

No workflow modifications needed!

## Manual Operations

**Database Creation:**

- Use `.github/scripts/create-database.sh` for new databases
- Use AWS Console for RDS instance creation

**Deployment Control:**

- Use GitHub Actions UI to target specific databases
- Force test/deploy modes via workflow dispatch
- Override branch behavior as needed

## Current Database Setup

This repository includes a ready-to-use PostgreSQL configuration:

- **PostgreSQL**: User management system (`changelog-postgres-prod.xml`)
- **Database Creation**: Multi-platform script (`.github/scripts/create-database.sh`)

The PostgreSQL setup includes realistic schemas with tables, indexes, functions, and PostgreSQL-specific features.

## Documentation

- `aws-setup.md` - Complete AWS setup guide
- `DATABASE-MANAGEMENT.md` - Database creation and management
- `SAFETY-TESTING-PLAN.md` - Comprehensive safety testing procedures

For technical details, see the documentation files above.
