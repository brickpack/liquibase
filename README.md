# Liquibase CI/CD Pipeline

A secure, branch-aware Liquibase CI/CD pipeline with AWS integration. Currently configured for PostgreSQL with multi-platform support ready to implement.

## Quick Start

### 1. Add a New Database
```bash
# Create a new changelog file
cp changelog-postgres-prod.xml changelog-myapp-postgres.xml

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

This repository includes a ready-to-use PostgreSQL configuration:

- **PostgreSQL**: User management system (`changelog-postgres-prod.xml`)
- **Bootstrap**: Database creation system (`changelog-bootstrap.xml`)

The PostgreSQL setup includes realistic schemas with tables, indexes, functions, and PostgreSQL-specific features.

## Documentation

- `aws-setup.md` - Complete AWS setup guide
- `DATABASE-MANAGEMENT.md` - Database creation and management
- `SAFETY-TESTING-PLAN.md` - Comprehensive safety testing procedures

For technical details, see the documentation files above.