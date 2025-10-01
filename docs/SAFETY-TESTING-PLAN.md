# Safety Testing Guide

This guide outlines how to safely test Liquibase changes before deploying to production.

## Quick Safety Tests

### 1. Offline Validation
Test changesets without connecting to any database:

```bash
# Validate changelog syntax
./.github/scripts/run-liquibase.sh your-database validate

# Generate SQL preview to see what will be executed
./.github/scripts/run-liquibase.sh your-database update-sql true
```

**Safety Level**: COMPLETELY SAFE - No database connections

### 2. Check Current Database State
Before making changes, document what exists:

```sql
-- PostgreSQL
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
SELECT indexname FROM pg_indexes WHERE schemaname = 'public';

-- MySQL
SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE();
SELECT index_name FROM information_schema.statistics WHERE table_schema = DATABASE();

-- SQL Server
SELECT name FROM sys.tables;
SELECT name FROM sys.indexes WHERE object_id IN (SELECT object_id FROM sys.tables);

-- Oracle
SELECT table_name FROM user_tables;
SELECT index_name FROM user_indexes;
```

### 3. Feature Branch Testing
Always test on feature branches first:

```bash
git checkout -b my-changes
# Make your changes
git push origin my-changes
# Pipeline runs in TEST mode (offline validation only)
```

## Safety Patterns

The pipeline uses these safety patterns:

- **IF NOT EXISTS**: Tables and schemas only created if they don't exist
- **Preconditions**: Changesets skip if conditions aren't met
- **Idempotent operations**: Can be run multiple times safely
- **No destructive operations**: No DROP, DELETE, or TRUNCATE statements

## Deployment Flow

1. **Feature Branch**: Test mode only (no database connections)
2. **Pull Request**: Test mode + code review
3. **Main Branch**: Deploy mode (after PR approval)

## Emergency Commands

If something goes wrong:

```bash
# Check database status
./.github/scripts/run-liquibase.sh your-database status

# Clear checksums if needed (safe operation)
./.github/scripts/run-liquibase.sh your-database clear-checksums
```

## Key Safety Rules

1. Never commit destructive SQL (DROP, DELETE, TRUNCATE)
2. Always use IF NOT EXISTS for new objects
3. Test on feature branches first
4. Get code review before merging to main
5. Monitor deployment logs carefully

This system has been tested and deployed successfully across PostgreSQL, MySQL, SQL Server, and Oracle databases.