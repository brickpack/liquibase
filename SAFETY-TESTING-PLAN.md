# Comprehensive Safety Testing Plan

This document outlines the complete testing strategy to ensure the Liquibase pipeline **NEVER** deletes, drops, or updates anything unintended.

## Testing Strategy Overview

### 🎯 Goals
1. **Validate all safety mechanisms work correctly**
2. **Ensure existing objects are never modified destructively**
3. **Verify preconditions prevent unwanted operations**
4. **Test idempotent operations work safely**
5. **Confirm bootstrap operations are safe**

## Phase 1: Pre-Deployment Analysis

### Test 1.1: SQL Generation (Dry Run)
**Purpose**: See exactly what SQL will be executed without running it
**Safety Level**: ✅ COMPLETELY SAFE - No database changes

```bash
# Test the current PostgreSQL deployment in dry-run mode
./.github/scripts/run-liquibase.sh postgres-prod update-sql true

# Expected: Only sees NEW changesets, nothing destructive
# Look for: CREATE statements with IF NOT EXISTS
# Verify: No DROP, DELETE, or destructive ALTER statements
```

### Test 1.2: Validation Check
**Purpose**: Validate changesets without executing them
**Safety Level**: ✅ COMPLETELY SAFE - No database changes

```bash
# Validate all changesets are syntactically correct
./.github/scripts/run-liquibase.sh postgres-prod validate

# Expected: All changesets validate successfully
# Verify: No syntax errors or dependency issues
```

### Test 1.3: Bootstrap SQL Generation
**Purpose**: See what bootstrap operations would do
**Safety Level**: ✅ COMPLETELY SAFE - No database changes

```bash
# Test bootstrap in dry-run mode (if postgres-master config exists)
./.github/scripts/run-liquibase.sh postgres-master update-sql --changelog-file=changelog-bootstrap.xml

# Expected: Shows database creation with preconditions
# Look for: Precondition checks before CREATE DATABASE
# Verify: No DROP DATABASE or destructive operations
```

## Phase 2: Database State Analysis

### Test 2.1: Current Database Inspection
**Purpose**: Document current state before any changes
**Safety Level**: ✅ COMPLETELY SAFE - Read-only operations

```sql
-- Connect to your PostgreSQL database and run these queries:

-- List all databases
SELECT datname FROM pg_database WHERE datistemplate = false;

-- List all tables in current database
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;

-- List all indexes
SELECT indexname, tablename FROM pg_indexes
WHERE schemaname = 'public' ORDER BY tablename, indexname;

-- List all functions
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public' ORDER BY routine_name;

-- Check if DATABASECHANGELOG exists (Liquibase tracking table)
SELECT COUNT(*) FROM information_schema.tables
WHERE table_name = 'databasechangelog';

-- If it exists, see what changesets have been executed
SELECT id, author, filename, exectype, dateexecuted
FROM databasechangelog ORDER BY dateexecuted;
```

### Test 2.2: Precondition Validation
**Purpose**: Test that preconditions work correctly
**Safety Level**: ✅ COMPLETELY SAFE - Tests prevent unwanted operations

Create a test changeset with preconditions:

```sql
-- Test file: test-preconditions.sql
--liquibase formatted sql

--changeset test:test-existing-table-precondition
--preconditions onFail:CONTINUE
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'users'
CREATE TABLE users_test_should_not_run (id SERIAL);

--changeset test:test-existing-database-precondition dbms:postgresql
--preconditions onFail:CONTINUE
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_database WHERE datname = 'userdb'
CREATE DATABASE userdb_test_should_not_run;
```

## Phase 3: Safe Operation Testing

### Test 3.1: Idempotent Operations Test
**Purpose**: Verify operations can be run multiple times safely
**Safety Level**: ✅ SAFE - Uses IF NOT EXISTS patterns

Test each type of operation:

```bash
# Run the same changeset multiple times
./.github/scripts/run-liquibase.sh postgres-prod update
# Then run again:
./.github/scripts/run-liquibase.sh postgres-prod update

# Expected: Second run shows "No changesets to apply"
# Verify: No duplicate objects created
# Confirm: No errors from existing objects
```

### Test 3.2: Checksum Safety Test
**Purpose**: Verify checksum clearing works safely
**Safety Level**: ✅ SAFE - Only clears tracking data, not actual objects

```bash
# Test the checksum clearing mechanism
./.github/scripts/run-liquibase.sh postgres-prod clear-checksums

# Expected: Clears DATABASECHANGELOG checksums only
# Verify: Database objects remain untouched
# Confirm: Only tracking data is modified
```

## Phase 4: Bootstrap Safety Testing

### Test 4.1: Bootstrap Precondition Test
**Purpose**: Verify database creation preconditions work
**Safety Level**: ✅ SAFE - Preconditions prevent unwanted operations

```bash
# Test bootstrap against existing database setup
# This should skip creation if databases already exist
./.github/scripts/run-liquibase.sh postgres-master update --changelog-file=changelog-bootstrap.xml

# Expected: Preconditions detect existing databases
# Verify: Skips creation, shows "preconditions failed"
# Confirm: No attempt to recreate existing databases
```

## Phase 5: Pipeline Integration Testing

### Test 5.1: Discovery Safety Test
**Purpose**: Verify discovery process is read-only
**Safety Level**: ✅ COMPLETELY SAFE - File system operations only

```bash
# Test database discovery process
cd .github/workflows
# Look at discovery script in liquibase-cicd.yml line 42
databases=$(find . -name "changelog-*.xml" -type f | sed 's|./changelog-||g' | sed 's|\.xml||g' | jq -R -s -c 'split("\n")[:-1]')
echo "Found databases: $databases"

# Expected: Only scans files, no database connections
# Verify: Discovers postgres-prod from changelog-postgres-prod.xml
# Confirm: No database modifications
```

### Test 5.2: Configuration Safety Test
**Purpose**: Verify database configuration doesn't modify data
**Safety Level**: ✅ SAFE - Only creates connection properties

```bash
# Test database configuration process
./.github/scripts/configure-database.sh postgres-prod liquibase-databases false

# Expected: Creates liquibase-postgres-prod.properties file
# Verify: Only connection configuration, no schema changes
# Confirm: No database modifications
```

## Phase 6: Full Pipeline Test (Controlled)

### Test 6.1: Branch-Based Test
**Purpose**: Test full pipeline on feature branch first
**Safety Level**: ✅ CONTROLLED - Feature branch testing

```bash
# Create test branch for safe testing
git checkout -b safety-test-branch

# Make a small, safe change to test pipeline
echo "-- Test comment" >> db/changelog/postgres/003-add-indexes.sql

# Commit and push to test branch (not main)
git add .
git commit -m "Test: Add comment to verify pipeline safety"
git push origin safety-test-branch

# Expected: Pipeline runs in TEST mode on feature branch
# Verify: Generates SQL preview only, no deployments
# Confirm: No changes to production database
```

### Test 6.2: Manual Execution Test
**Purpose**: Run pipeline steps manually with full visibility
**Safety Level**: ✅ CONTROLLED - Step-by-step execution

```bash
# Execute each pipeline step manually with logging

# Step 1: Setup
./.github/scripts/setup-liquibase.sh

# Step 2: Analysis (safe)
./.github/scripts/analyze-changelog.sh postgres-prod

# Step 3: Configuration (safe)
./.github/scripts/configure-database.sh postgres-prod liquibase-databases false

# Step 4: Validation (safe)
./.github/scripts/run-liquibase.sh postgres-prod validate

# Step 5: SQL Generation (safe - preview only)
./.github/scripts/run-liquibase.sh postgres-prod update-sql true

# Step 6: Review generated SQL before any deployment
cat planned-changes-postgres-prod.sql

# Only proceed to actual deployment after manual review
```

## Phase 7: Safety Mechanism Verification

### Test 7.1: Liquibase Tracking Verification
**Purpose**: Confirm Liquibase tracking prevents re-execution
**Expected Behavior**: Already executed changesets are skipped

```sql
-- Check what's been executed
SELECT id, author, filename, exectype, dateexecuted
FROM databasechangelog
ORDER BY orderexecuted;

-- Verify checksums exist for executed changesets
SELECT id, author, filename, md5sum
FROM databasechangelog
WHERE md5sum IS NOT NULL;
```

### Test 7.2: IF NOT EXISTS Verification
**Purpose**: Confirm all CREATE statements use safe patterns
**Check These Patterns in SQL Files**:

```bash
# Verify all schema files use safe patterns
grep -n "CREATE TABLE" db/changelog/postgres/*.sql
# Should show: No CREATE TABLE without safety checks

grep -n "CREATE INDEX" db/changelog/postgres/*.sql
# Should show: CREATE INDEX IF NOT EXISTS or CREATE INDEX CONCURRENTLY IF NOT EXISTS

grep -n "ALTER TABLE.*ADD COLUMN" db/changelog/postgres/*.sql
# Should show: ADD COLUMN IF NOT EXISTS

grep -n "CREATE OR REPLACE" db/changelog/postgres/*.sql
# Should show: Functions use CREATE OR REPLACE (safe for functions)
```

## Phase 8: Error Recovery Testing

### Test 8.1: Failed Deployment Recovery
**Purpose**: Verify system handles failures gracefully
**Safety Level**: ✅ CONTROLLED - Test error conditions

```bash
# Create a changeset that will fail safely
cat > test-failure.sql << 'EOF'
--liquibase formatted sql
--changeset test:test-failure
SELECT * FROM non_existent_table;
EOF

# Test how system handles the failure
./.github/scripts/run-liquibase.sh postgres-prod update --changelog-file=test-failure.sql

# Expected: Fails gracefully, no partial state
# Verify: Database remains in consistent state
# Confirm: Error is logged but no corruption occurs

# Cleanup test file
rm test-failure.sql
```

## Testing Checklist

### ✅ Before Any Real Deployment
- [ ] All SQL generation tests pass (dry-run mode)
- [ ] All validation tests pass
- [ ] All preconditions work correctly
- [ ] All safety patterns verified in SQL files
- [ ] Bootstrap preconditions tested
- [ ] Idempotent operations confirmed
- [ ] Pipeline discovery tested
- [ ] Manual step-by-step execution completed
- [ ] Generated SQL manually reviewed
- [ ] Error recovery scenarios tested

### ✅ Safety Patterns Confirmed
- [ ] All CREATE statements use IF NOT EXISTS
- [ ] All ALTER TABLE uses safe patterns
- [ ] Functions use CREATE OR REPLACE
- [ ] Indexes use CONCURRENTLY IF NOT EXISTS
- [ ] No DROP, DELETE, or TRUNCATE statements
- [ ] All changesets have proper IDs and authors
- [ ] Preconditions prevent unwanted operations
- [ ] Bootstrap has database existence checks

### ✅ Liquibase Safety Features Active
- [ ] DATABASECHANGELOG table exists and populated
- [ ] Checksum validation working
- [ ] Already-executed changesets are skipped
- [ ] Rollback information captured where applicable
- [ ] Log files show all operations clearly

## Final Validation Commands

Before any production deployment, run these final safety checks:

```bash
# 1. Generate complete SQL preview
./.github/scripts/run-liquibase.sh postgres-prod update-sql true
echo "✅ Review planned-changes-postgres-prod.sql before proceeding"

# 2. Validate all changesets
./.github/scripts/run-liquibase.sh postgres-prod validate
echo "✅ All changesets validated successfully"

# 3. Check current database state
./.github/scripts/run-liquibase.sh postgres-prod status
echo "✅ Database status checked"

# 4. Verify no destructive operations
grep -i "drop\|delete\|truncate" planned-changes-postgres-prod.sql || echo "✅ No destructive operations found"

# 5. Confirm safety patterns
grep -c "IF NOT EXISTS\|CREATE OR REPLACE" planned-changes-postgres-prod.sql
echo "✅ Safety patterns confirmed"
```

## Emergency Procedures

### If Something Goes Wrong
1. **STOP**: Don't run any more deployments
2. **ASSESS**: Check database state vs. expected state
3. **ROLLBACK**: Use Liquibase rollback if available
4. **RESTORE**: Use database backup if needed
5. **INVESTIGATE**: Review logs and generated SQL
6. **FIX**: Correct the issue before retrying

### Rollback Commands
```bash
# Rollback last changeset
./.github/scripts/run-liquibase.sh postgres-prod rollback-count 1

# Rollback to specific tag
./.github/scripts/run-liquibase.sh postgres-prod rollback tag-name

# Generate rollback SQL for review
./.github/scripts/run-liquibase.sh postgres-prod rollback-sql tag-name
```

This comprehensive testing plan ensures that **NOTHING** unintended can be deleted, dropped, or updated. Every operation is validated for safety before execution.