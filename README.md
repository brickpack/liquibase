# Dynamic Liquibase CI/CD Pipeline

A branch-aware, multi-database Liquibase CI/CD pipeline with AWS integration and dynamic database discovery. Supports PostgreSQL, MySQL, SQL Server, and Oracle.

## Quick Start

### 1. Add a New Database
```bash
# Create a new changelog file (choose appropriate template)
cp changelog-postgres-prod.xml changelog-myapp-postgres.xml
cp changelog-mysql-prod.xml changelog-myapp-mysql.xml

# Edit the new file to include your changesets
# Add database config to AWS secret: liquibase-databases
```

### 2. Create a Feature Branch
```bash
git checkout -b feature/add-user-table
# Make your changes to SQL files
git push origin feature/add-user-table
```

**Result**: Pipeline runs in test mode, validates your changes, generates SQL previews.

### 3. Merge to Main
```bash
git checkout main
git merge feature/add-user-table
git push origin main
```

**Result**: Pipeline deploys to all databases automatically.

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

Use GitHub Actions UI to:
- Target specific databases
- Force test/deploy modes
- Override branch behavior

## Current Database Setup

This repository includes ready-to-use examples for:

- **PostgreSQL**: User management system (`changelog-postgres-prod.xml`)
- **MySQL**: E-commerce analytics (`changelog-mysql-prod.xml`)
- **SQL Server**: Business intelligence reporting (`changelog-sqlserver-prod.xml`)
- **Oracle**: Legacy system integration (`changelog-oracle-prod.xml`)

Each database includes realistic schemas with tables, indexes, procedures, and platform-specific features.

## Documentation

- `CLAUDE.md` - Detailed technical documentation
- `database-examples.md` - JDBC connection examples
- `aws-setup.md` - AWS configuration guide

See `CLAUDE.md` for detailed documentation.