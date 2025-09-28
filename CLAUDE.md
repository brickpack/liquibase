# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a multi-database Liquibase CI/CD pipeline project with GitHub Actions integration for AWS deployment. The repository manages database changes across four databases using SQL scripts for changesets and XML for master changelog organization.

## Development Commands

### Liquibase Commands (Dynamic Multi-Database)
- `./liquibase --defaults-file=liquibase-<database>.properties validate` - Validate specific database
- `./liquibase --defaults-file=liquibase-<database>.properties update` - Apply changes to specific database
- `./liquibase --defaults-file=liquibase-<database>.properties update-sql` - Generate SQL preview
- `./liquibase --defaults-file=liquibase-<database>.properties rollback-count 1` - Rollback last changeset
- `./liquibase --defaults-file=liquibase-<database>.properties status` - Show pending changes

### CI/CD Pipeline (Branch-Aware)
- **Feature branches**: Runs tests only (validates changelog, generates SQL preview)
- **Main branch**: Full deployment pipeline (validates and deploys to all databases)
- **Pull requests**: Test mode with SQL previews for review
- **Manual trigger**: Choose test/deploy mode and specific database
- **Dynamic discovery**: Automatically finds databases by scanning `changelog-*.xml` files

## Architecture

### File Structure
- `changelog-postgres-prod.xml` - PostgreSQL user management database
- `changelog-mysql-prod.xml` - MySQL e-commerce analytics database
- `changelog-sqlserver-prod.xml` - SQL Server reporting database
- `changelog-oracle-prod.xml` - Oracle legacy integration database
- `db/changelog/postgres/` - PostgreSQL-specific changesets
- `db/changelog/mysql/` - MySQL-specific changesets
- `db/changelog/sqlserver/` - SQL Server-specific changesets
- `db/changelog/oracle/` - Oracle-specific changesets
- `liquibase.properties` - Local configuration template
- `.github/workflows/liquibase-cicd.yml` - Clean, modular CI/CD pipeline
- `.github/scripts/` - Reusable shell scripts for pipeline operations
- `aws-setup.md` - AWS and Secrets Manager configuration
- `database-examples.md` - JDBC connection examples for all database types

### Dynamic Database Discovery
- Pipeline automatically discovers databases by scanning for `changelog-*.xml` files
- No hard-coded database names in workflow
- Add new databases by creating `changelog-<newdb>.xml` files
- Add corresponding entry to consolidated AWS Secrets Manager secret

### Consolidated Secret Structure
Single AWS secret (default: `liquibase-databases`) containing all database configurations:
```json
{
  "postgres-prod": {"type": "postgresql", "url": "...", "username": "...", "password": "..."},
  "mysql-analytics": {"type": "mysql", "url": "...", "username": "...", "password": "..."},
  "sqlserver-reports": {"type": "sqlserver", "url": "...", "username": "...", "password": "..."},
  "oracle-legacy": {"type": "oracle", "url": "...", "username": "...", "password": "..."}
}
```

### Multi-Database Support
- **PostgreSQL**: Auto-configured with PostgreSQL JDBC driver
- **MySQL**: Auto-configured with MySQL Connector/J
- **SQL Server**: Auto-configured with Microsoft JDBC driver
- **Oracle**: Requires manual Oracle JDBC driver setup (license required)
- **Auto-detection**: Database type detected from JDBC URL if not specified

### Security Features
- Uses GitHub OIDC for AWS authentication (no long-lived keys)
- Database credentials stored in AWS Secrets Manager
- Automatic password masking in logs
- Credential file cleanup after use
- Log sanitization to remove password leaks
- IAM role with minimal required permissions

## Setup Requirements

1. **AWS Setup**: Follow instructions in `aws-setup.md`
2. **GitHub Variables**: Configure AWS_ROLE_ARN, AWS_REGION, SECRET_NAME
3. **AWS Secrets Manager**: Create single consolidated secret with all database credentials
4. **Database Access**: Ensure databases are accessible from GitHub Actions

## Workflow Behavior

### Automatic Triggers
- **Feature Branches**: Test mode - validates changelogs and generates SQL previews (no AWS credentials needed)
- **Main Branch Push**: Deploy mode - validates and applies changes to all discovered databases
- **Pull Requests**: Test mode - validates and shows SQL previews for review
- **Any Branch**: Triggers run on all branches for immediate feedback

### Manual Triggers
- **Database Selection**: Target specific database or "all"
- **Action Selection**:
  - `auto` - Test on feature branches, deploy on main
  - `test` - Force test mode (offline validation)
  - `deploy` - Force deploy mode (requires main branch or override)

### Pipeline Features
- **Dynamic Discovery**: Automatically finds databases, no hard-coded names
- **Branch-Aware**: Different behavior based on branch and trigger type
- **Secure Testing**: Feature branches run without AWS credentials
- **Matrix Strategy**: All discovered databases run in parallel
- **Fail-Safe**: Continue processing other databases if one fails

## Changeset Format

All changesets use SQL format with Liquibase formatting:

```sql
--liquibase formatted sql

--changeset author:changeset-id
--comment: Description of changes
SQL STATEMENTS HERE;
```
