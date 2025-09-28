# Pipeline Scripts

This directory contains modular shell scripts used by the Liquibase CI/CD pipeline.

## Scripts Overview

### `setup-liquibase.sh`
Downloads and configures Liquibase with all database drivers.
- Downloads Liquibase v4.25.1
- Downloads PostgreSQL, MySQL, and SQL Server JDBC drivers
- Creates driver directory structure

### `configure-database.sh`
Configures database connections for deployment or testing.
```bash
./configure-database.sh <database> [secret_name] [test_mode]
```
- Retrieves credentials from AWS Secrets Manager (production mode)
- Auto-detects database type from JDBC URL
- Creates offline configuration for testing
- Handles credential masking for security

### `analyze-changelog.sh`
Analyzes changelog structure and validates file references.
```bash
./analyze-changelog.sh <database>
```
- Validates changelog file existence
- Scans for included SQL files
- Counts changesets in each file

### `run-liquibase.sh`
Executes Liquibase commands with consistent logging and error handling.
```bash
./run-liquibase.sh <database> <command> [test_mode]
```
Commands: `validate`, `update`, `update-sql`, `status`
- Provides detailed SQL analysis for update-sql
- Handles error reporting and logging
- Formats output consistently

### `cleanup.sh`
Cleans up sensitive files and sanitizes logs.
```bash
./cleanup.sh <database>
```
- Removes credential files
- Sanitizes passwords from log files
- Maintains security compliance

## Usage in Workflow

These scripts are designed to be modular and reusable:
```yaml
- name: Setup Liquibase and drivers
  run: ./.github/scripts/setup-liquibase.sh

- name: Configure database connection
  run: |
    ./.github/scripts/configure-database.sh \
      ${{ matrix.database }} \
      ${{ vars.SECRET_NAME }} \
      ${{ needs.discover-databases.outputs.test-mode }}
```

All scripts include error handling and follow security best practices.