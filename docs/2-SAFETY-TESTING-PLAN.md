# Safety Testing Guide

This guide outlines how to safely test Liquibase changes using GitHub Actions before deploying to production.

## Testing Strategy

All safety testing is done through GitHub Actions, which provides:
- Consistent environment matching production
- Proper Liquibase setup and drivers
- AWS credentials for testing
- Parallel testing across all databases

## Safe Testing Workflow

### 1. Create Feature Branch
Always test changes on a feature branch first:

```bash
git checkout -b test-my-changes
# Make your database changes
git add .
git commit -m "Add new database features"
git push origin test-my-changes
```

**Result**: GitHub Action runs in **TEST MODE** - validates changesets without connecting to production databases.

### 2. Review GitHub Action Results
The workflow will show you:
- **Changelog validation**: Syntax and structure checks
- **SQL preview**: Exact SQL that would be executed
- **Safety analysis**: Detects destructive operations
- **Database discovery**: Shows which databases were found

### 3. Create Pull Request
Once tests pass, create a PR for code review:

```bash
gh pr create --title "Add new features" --body "Description of changes"
```

**Result**:
- GitHub Action runs tests again on PR
- Team can review both code and generated SQL
- No production database connections made

### 4. Deploy After Approval
When PR is approved and merged to main:

**Result**: GitHub Action runs in **DEPLOY MODE** - actually executes changes on production databases.

## What the GitHub Actions Test

### Offline Validation
- **Changelog syntax**: Validates XML structure and SQL syntax
- **Changeset format**: Ensures proper Liquibase headers
- **Dependencies**: Checks changeset ordering and dependencies

### SQL Generation
- **Preview SQL**: Shows exactly what will be executed
- **Safety patterns**: Confirms IF NOT EXISTS usage
- **Destructive operations**: Warns about DROP/DELETE/TRUNCATE

### Database Discovery
- **Auto-detection**: Finds databases from changelog filenames
- **Configuration**: Validates AWS Secrets Manager setup
- **Dependencies**: Checks for required master configurations

## Safety Features Built-In

The pipeline automatically enforces safety:

1. **No production access on branches**: Feature branches never connect to real databases
2. **IF NOT EXISTS patterns**: Tables and objects only created if they don't exist
3. **Preconditions**: Changesets skip execution if conditions aren't met
4. **Rollback support**: Liquibase tracks all changes for potential rollback
5. **Error isolation**: Failed databases don't stop other deployments

## Viewing Test Results

After pushing a branch, check the GitHub Actions tab to see:
- **SQL Preview Files**: Download generated SQL to review offline
- **Validation Results**: See which changesets will execute
- **Safety Analysis**: Review detected patterns and warnings
- **Database Status**: Check connection and configuration issues

## Emergency Procedures

If something goes wrong after deployment:

1. **Check database status**: Use GitHub Actions workflow_dispatch to run status check
2. **Review Liquibase logs**: Check the action logs for detailed error information
3. **Clear checksums if needed**: Use workflow_dispatch with appropriate parameters

## Key Safety Rules

1. **Never merge without tests passing**: GitHub Actions must show green checkmarks
2. **Always review generated SQL**: Download and inspect the SQL preview files
3. **Use code review**: Have team members review both code and SQL changes
4. **Monitor deployments**: Watch the action logs during production deployment
5. **Test incrementally**: Make small, focused changes rather than large migrations

This approach ensures all testing happens in a controlled environment that exactly matches your production setup.