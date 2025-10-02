# Workflow Modes: Test vs Deploy

The Liquibase CI/CD pipeline has two distinct modes: **Test Mode** and **Deploy Mode**. Understanding when each runs is crucial for proper pipeline usage.

## Quick Reference

| Trigger | Mode | Database Connection | User Passwords | AWS Credentials |
|---------|------|-------------------|----------------|-----------------|
| Feature branch push | Test | ❌ Offline only | ❌ Not set | ❌ Not required |
| Pull request | Test | ❌ Offline only | ❌ Not set | ❌ Not required |
| Main branch (after merge) | Deploy | ✅ Live databases | ✅ Set from AWS | ✅ Required |
| Manual: `action=test` | Test | ❌ Offline only | ❌ Not set | ❌ Not required |
| Manual: `action=deploy` | Deploy | ✅ Live databases | ✅ Set from AWS | ✅ Required |
| Manual: `action=auto` | Auto-detect | Depends on branch | Depends on branch | Depends on branch |

## Test Mode

### When It Runs

Test mode runs automatically when:
- Pushing to feature branches (any branch except `main`)
- Opening or updating pull requests
- Manually triggered with `action=test`

### What It Does

1. **SQL Syntax Validation**
   - Checks all SQL files for basic syntax errors
   - Validates Liquibase headers and changeset format
   - Checks for unterminated quotes and dollar quotes
   - Ensures required preconditions

2. **Liquibase Offline Validation**
   - Validates changelog XML structure
   - Checks changeset syntax
   - Verifies file references
   - Uses offline PostgreSQL driver (no actual connection)

3. **SQL Preview Generation**
   - Generates SQL that would be executed
   - Uploads as workflow artifact
   - Available for download and review
   - Shows exactly what would happen in deploy mode

4. **Changelog Structure Analysis**
   - Analyzes directory structure
   - Validates naming conventions
   - Checks for missing files

### What It Doesn't Do

- ❌ Does NOT connect to actual databases
- ❌ Does NOT execute any SQL
- ❌ Does NOT create databases
- ❌ Does NOT set user passwords
- ❌ Does NOT require AWS credentials
- ❌ Does NOT modify any data

### Why Use Test Mode

- **Fast feedback**: Catches errors before deployment
- **No credentials needed**: Works on any branch without AWS access
- **Safe**: Cannot accidentally modify databases
- **Code review**: Generated SQL can be reviewed in PR
- **CI/CD best practice**: Test before deploy

### Example Workflow

```bash
# Create feature branch
git checkout -b feature/add-new-table

# Make changes to SQL
vim db/changelog/postgres-prod-myappdb/005-add-products-table.sql

# Commit and push
git add .
git commit -m "Add products table"
git push origin feature/add-new-table

# Pipeline automatically runs in TEST mode
# - Validates SQL syntax
# - Generates SQL preview
# - No database connection required

# Create PR
gh pr create --title "Add products table" --body "New table for product catalog"

# Pipeline runs TEST mode again on PR
# Team reviews generated SQL in artifacts
# Get approval and merge
```

## Deploy Mode

### When It Runs

Deploy mode runs when:
- Pushing directly to `main` branch (after PR merge)
- Manually triggered with `action=deploy`

### What It Does

1. **All Test Mode Steps** (first)
   - Validates syntax
   - Runs offline validation
   - Ensures safety before deployment

2. **Database Discovery**
   - Fetches credentials from AWS Secrets Manager
   - Identifies all target databases
   - Determines which need changesets applied

3. **Database Creation** (if needed)
   - Checks if database exists
   - Uses master credentials to CREATE DATABASE
   - Skips if database already exists

4. **Liquibase Deployment**
   - Connects to live databases
   - Executes pending changesets
   - Updates DATABASECHANGELOG table
   - Applies schema changes

5. **User Password Management**
   - Runs `manage-users.sh` script
   - Fetches passwords from AWS Secrets Manager
   - Sets real passwords for all users
   - Updates passwords in live databases

### What It Requires

- ✅ AWS credentials (via OIDC)
- ✅ Database credentials in AWS Secrets Manager
- ✅ Network access to databases
- ✅ Valid changelog files

### Security Safeguards

Even in deploy mode, the pipeline is safe:

1. **PR required**: Only runs after code review and approval
2. **Preconditions**: Uses `IF NOT EXISTS` for idempotency
3. **Transactions**: Liquibase uses transactions where supported
4. **Rollback tracking**: DATABASECHANGELOG tracks what ran
5. **Password masking**: Secrets masked in logs

### Example Workflow

```bash
# After PR is approved and merged to main
git checkout main
git pull

# Pipeline automatically runs in DEPLOY mode
# 1. Validates changesets (test mode checks)
# 2. Connects to databases
# 3. Creates database if needed
# 4. Deploys changesets
# 5. Sets user passwords from AWS Secrets Manager

# Monitor the deployment
gh run watch

# Verify deployment
# Check DATABASECHANGELOG table in your database
```

## Manual Workflow Triggers

You can manually trigger the workflow with specific modes:

### Test Mode (Safe)

```bash
# Test all databases
gh workflow run liquibase-cicd.yml -f action=test -f database=all

# Test specific database
gh workflow run liquibase-cicd.yml -f action=test -f database=postgres-myappdb

# Test specific platform
gh workflow run liquibase-cicd.yml -f action=test -f database=postgresql
```

### Deploy Mode (Requires AWS Credentials)

```bash
# Deploy all databases
gh workflow run liquibase-cicd.yml -f action=deploy -f database=all

# Deploy specific database
gh workflow run liquibase-cicd.yml -f action=deploy -f database=sqlserver-inventory

# Deploy specific platform
gh workflow run liquibase-cicd.yml -f action=deploy -f database=mysql
```

### Auto Mode (Branch-aware)

```bash
# Auto-detect based on branch
gh workflow run liquibase-cicd.yml -f action=auto -f database=all

# If on main: runs deploy mode
# If on feature branch: runs test mode
```

## Mode Detection Logic

The workflow determines mode using this logic:

```yaml
# In .github/workflows/liquibase-cicd.yml

# User explicitly chose action
if action == "test":
    test-mode = true
elif action == "deploy":
    test-mode = false
elif action == "auto":
    # Auto-detect based on branch
    if branch == "main":
        test-mode = false  # Deploy on main
    else:
        test-mode = true   # Test on feature branches
```

## Common Scenarios

### Scenario 1: Feature Development

**Goal**: Add a new table safely

**Process**:
1. Create feature branch → **Test mode** runs automatically
2. Commit SQL changes → **Test mode** validates
3. Create PR → **Test mode** runs again
4. Team reviews generated SQL
5. Merge to main → **Deploy mode** runs
6. Table created in database

**Mode**: Test → Test → Deploy

### Scenario 2: Hotfix Deployment

**Goal**: Fix critical issue quickly

**Process**:
1. Create hotfix branch
2. Make minimal change
3. Push → **Test mode** validates
4. Merge to main → **Deploy mode** deploys

**Mode**: Test → Deploy

### Scenario 3: Password Rotation

**Goal**: Rotate user password without schema changes

**Process**:
1. Update AWS Secrets Manager password
2. Run manual deploy:
   ```bash
   gh workflow run liquibase-cicd.yml -f action=deploy -f database=postgres-myappdb
   ```
3. Pipeline updates password (no Liquibase changes needed)

**Mode**: Deploy only (no changeset required)

### Scenario 4: Testing New Database Setup

**Goal**: Validate changelog before creating database

**Process**:
1. Add new changelog file
2. Create feature branch
3. Push → **Test mode** validates offline
4. Review generated SQL
5. Merge to main → **Deploy mode** creates database and runs changesets

**Mode**: Test → Deploy

## Troubleshooting

### "Permission denied" in Deploy Mode

**Cause**: AWS OIDC authentication failed

**Solution**:
- Verify `AWS_ROLE_ARN` variable is set in GitHub
- Check IAM role trust policy includes your repository
- Ensure workflow has `id-token: write` permission

### Password Not Set (User Can't Login)

**Cause**: Workflow ran in Test mode instead of Deploy mode

**Solution**:
- Check which mode ran in workflow logs
- If test mode: trigger deploy mode manually:
  ```bash
  gh workflow run liquibase-cicd.yml -f action=deploy -f database=your-db
  ```

### Changes Not Applied to Database

**Cause**: Workflow ran in Test mode (no database connection)

**Solution**:
- Test mode only validates, doesn't deploy
- Merge PR to main for Deploy mode
- Or manually trigger deploy mode

### Deploy Mode Running on Feature Branch

**Cause**: Manual trigger with `action=deploy`

**Solution**:
- This is by design (manual override)
- Be careful deploying from feature branches
- Prefer deploying from main after PR approval

## Best Practices

### 1. Always Use Test Mode First

Never deploy directly without testing:

```bash
# ❌ Bad: Deploy without testing
gh workflow run liquibase-cicd.yml -f action=deploy

# ✅ Good: Test first, then deploy via PR
git checkout -b feature/changes
# make changes
git push  # Test mode runs
gh pr create  # Test mode runs on PR
# After approval, merge → Deploy mode runs
```

### 2. Review Generated SQL

Always review the SQL preview in Test mode:

1. Check GitHub Actions artifacts
2. Download `planned-changes-*.sql` files
3. Review what will be executed
4. Verify safety and correctness

### 3. Use Auto Mode for Branch Protection

Configure branch protection with auto mode:
- Feature branches → Test automatically
- Main branch → Deploy automatically
- No manual intervention needed

### 4. Separate User Management from Schema

When rotating passwords, don't create new changesets:
- Update AWS Secrets Manager
- Trigger deploy mode
- Script updates passwords (no schema change)

### 5. Monitor Deploy Mode Runs

Always monitor deployments:

```bash
# Watch the deployment in real-time
gh run watch

# Check logs if something fails
gh run view --log
```

## Workflow Configuration

The mode is controlled in the workflow file:

```yaml
# .github/workflows/liquibase-cicd.yml

workflow_dispatch:
  inputs:
    action:
      description: 'Action to perform'
      required: false
      default: 'auto'
      type: choice
      options:
        - auto    # Branch-aware
        - test    # Always test
        - deploy  # Always deploy
```

## Summary

**Test Mode**:
- Safe, fast validation
- No AWS credentials required
- No database connections
- Runs on feature branches and PRs

**Deploy Mode**:
- Actual deployment
- Requires AWS credentials
- Connects to live databases
- Runs on main branch or manual trigger

**Best Practice**: Test on branches → Review in PR → Deploy from main
