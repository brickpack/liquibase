# Liquibase Reference Guide

Technical reference for Docker container, secrets management, and advanced configuration.

---

## Table of Contents

- [Docker Container](#docker-container)
- [Secrets Management](#secrets-management)
- [Helper Scripts](#helper-scripts)

---

## Docker Container

The pipeline uses a custom Docker container with all database tools pre-installed, eliminating the need to install database clients during each workflow run.

### Container Details

**Image Location**: `ghcr.io/{your-org}/{your-repo}/liquibase-tools:latest`

**Base Image**: `ubuntu:24.04`

### What's Included

#### Database Tools

- **PostgreSQL Client**: `psql` (postgresql-client package)
- **MySQL Client**: `mysql` (mysql-client package)
- **Oracle Instant Client**: `sqlplus` (basiclite 23.4.0.24.05)
- **SQL Server Tools**: `sqlcmd` (mssql-tools18)

#### Development Tools

- **Java**: OpenJDK 17 JRE Headless
- **Liquibase**: Version 4.33.0
- **AWS CLI**: Version 2
- **Utilities**: curl, wget, jq, git, unzip

#### JDBC Drivers

All drivers are pre-installed in `/opt/liquibase/lib/`:

- **PostgreSQL**: postgresql-42.7.4.jar
- **MySQL**: mysql-connector-j-9.1.0.jar
- **Oracle**: ojdbc11-23.6.0.24.10.jar
- **SQL Server**: mssql-jdbc-12.8.1.jre11.jar

### Environment Configuration

The container sets up the following environment:

```dockerfile
# Oracle environment
PATH="/opt/oracle/instantclient_23_4:${PATH}"
LD_LIBRARY_PATH="/opt/oracle/instantclient_23_4"

# SQL Server tools
PATH="/opt/mssql-tools18/bin:${PATH}"

# Liquibase
PATH="/opt/liquibase:${PATH}"

# Working directory
WORKDIR /workspace
```

### Building the Container

The container is automatically built when the `Dockerfile` is modified:

```yaml
# Triggers:
on:
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - '.github/workflows/build-docker-image.yml'
  workflow_dispatch:
```

#### Manual Build

To manually trigger a container build:

```bash
gh workflow run build-docker-image.yml
```

#### Build Workflow

Located at `.github/workflows/build-docker-image.yml`, the build:

1. Checks out the repository
2. Sets up Docker Buildx
3. Logs in to GitHub Container Registry
4. Builds and tags the image
5. Pushes to GHCR

**Build time**: ~5-7 minutes

**Image size**: Optimized (~800MB compressed)

### Size Optimizations

The Dockerfile uses several techniques to minimize image size:

1. **Single-layer package installation**: All apt packages installed in one RUN command
2. **Minimal packages**: Uses `--no-install-recommends` flag
3. **Headless JRE**: Uses `openjdk-17-jre-headless` instead of full JDK
4. **Oracle basiclite**: Uses smaller basiclite package instead of full basic client
5. **Aggressive cleanup**: Removes unnecessary files after installation
6. **No development files**: Removes .sym files and other debug symbols

### Using the Container in GitHub Actions

The workflow uses the container via the `container` directive:

```yaml
jobs:
  liquibase:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/${{ github.repository }}/liquibase-tools:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
```

**Benefits:**
- All tools available immediately (no setup time)
- Consistent environment across all runs
- No need to download/install database clients
- Faster workflow execution (~2 minutes saved per run)

### Local Development

To use the same environment locally:

```bash
# Build the image locally
docker build -t liquibase-tools .

# Run with mounted workspace
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  liquibase-tools /bin/bash

# Now you have access to all tools
liquibase --version
psql --version
mysql --version
sqlcmd -?
sqlplus -V
```

### Troubleshooting

#### Container build fails with package errors

**Cause**: Ubuntu package repository changes or network issues.

**Solution**:
- Check Dockerfile for correct package names
- Ensure package repositories are accessible
- Try rebuilding after a few minutes

#### Driver not found errors

**Cause**: Liquibase looking for drivers in wrong location.

**Solution**: Drivers are automatically loaded from `/opt/liquibase/lib/` - no configuration needed.

#### Image pull fails with authentication error

**Cause**: GitHub token doesn't have package read permissions.

**Solution**: Ensure GITHUB_TOKEN has `packages: read` permission:
```yaml
permissions:
  contents: read
  packages: read
```

---

## Secrets Management

This system uses **per-server secrets** in AWS Secrets Manager to organize database credentials. Each database server has its own secret containing master connection, individual databases, and application users.

### Secret Naming Convention

- `liquibase-postgres-prod` - PostgreSQL server
- `liquibase-mysql-prod` - MySQL server
- `liquibase-sqlserver-prod` - SQL Server instance
- `liquibase-oracle-prod` - Oracle instance

**Format**: `liquibase-{server-type}-{server-name}`

### Secret Structure

```json
{
  "master": {
    "type": "postgresql",
    "url": "jdbc:postgresql://host:5432/postgres",
    "username": "postgres",
    "password": "master_password"
  },
  "databases": {
    "thedb": {
      "connection": {
        "url": "jdbc:postgresql://host:5432/thedb",
        "username": "admin_user",
        "password": "admin_password"
      },
      "users": {
        "app_readwrite": "rw_password",
        "app_readonly": "ro_password"
      }
    },
    "another_db": {
      "connection": {
        "url": "jdbc:postgresql://host:5432/another_db",
        "username": "admin_user",
        "password": "admin_password"
      },
      "users": {
        "api_user": "api_password"
      }
    }
  }
}
```

### Database Identifier Format

In changelogs and workflows, use this format: `{server}-{dbname}`

Examples:
- `postgres-thedb` - PostgreSQL database named "thedb"
- `sqlserver-ecommerce` - SQL Server database named "ecommerce"
- `mysql-analytics` - MySQL database named "analytics"
- `oracle-erp` - Oracle database/schema named "erp"

### Changelog File Naming

Changelog XML files must match the database identifier:
- `changelog-postgres-thedb.xml`
- `changelog-sqlserver-ecommerce.xml`
- `changelog-mysql-analytics.xml`

### Viewing Secret Contents

```bash
# PostgreSQL
aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text | jq .

# SQL Server
aws secretsmanager get-secret-value \
  --secret-id liquibase-sqlserver-prod \
  --query SecretString --output text | jq .

# MySQL
aws secretsmanager get-secret-value \
  --secret-id liquibase-mysql-prod \
  --query SecretString --output text | jq .

# Oracle
aws secretsmanager get-secret-value \
  --secret-id liquibase-oracle-prod \
  --query SecretString --output text | jq .
```

### How Scripts Use Secrets

#### configure-database.sh
Parses `postgres-thedb` → reads `liquibase-postgres-prod` → extracts `.databases.thedb.connection`

#### create-database.sh
Uses `.master` connection to create database, then updates `.databases.{dbname}` entry

#### manage-users.sh
Reads `.databases.{dbname}.users` to set passwords for application users

### Benefits of This Structure

✅ **Scalability**: Supports 100+ databases per server
✅ **Organization**: All databases for a server in one secret
✅ **No Conflicts**: Users are scoped to specific databases
✅ **Clear Hierarchy**: master → databases → users
✅ **Easy to Navigate**: Use database name to find all related info
✅ **Version Controlled**: Secret structure is documented and consistent

### Common Secret Operations

#### Add a New Database

**Option 1: Use interactive script**
```bash
.github/scripts/add-database-to-server.sh
```

**Option 2: Manual update via AWS CLI**
```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Add new database using jq
NEW_SECRET=$(echo "$SECRET" | jq \
  '.databases.newdb = {
    connection: {
      url: "jdbc:postgresql://host:5432/newdb",
      username: "admin",
      password: "admin_pass"
    },
    users: {
      "app_user": "app_pass"
    }
  }')

# Update secret
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$NEW_SECRET"
```

#### Add User to Existing Database

```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Add user to existing database
NEW_SECRET=$(echo "$SECRET" | jq \
  '.databases.thedb.users.new_user = "new_password"')

# Update secret
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$NEW_SECRET"
```

#### Remove User

```bash
# Get current secret
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text)

# Remove user
NEW_SECRET=$(echo "$SECRET" | jq \
  'del(.databases.thedb.users.old_user)')

# Update secret
aws secretsmanager put-secret-value \
  --secret-id liquibase-postgres-prod \
  --secret-string "$NEW_SECRET"
```

### Troubleshooting Secrets

#### Database not found error

```
❌ Database 'thedb' not found in secret 'liquibase-postgres-prod'
```

**Solution**: Add the database using the creation script or manual update

#### User passwords not set

```
ℹ️  No users configured for database 'thedb'
```

**Solution**: Add users to `.databases.thedb.users` in the secret

#### Wrong server type

```
❌ Cannot determine database type from server name 'pg'
```

**Solution**: Use standard server names: `postgres`, `mysql`, `sqlserver`, `oracle`

---

## Helper Scripts

The `.github/scripts/` directory contains helper scripts for managing secrets and databases.

### Interactive Scripts

#### create-secret.sh

Create or update a per-server secret for any database type.

**Usage:**
```bash
# Interactive mode
.github/scripts/create-secret.sh

# Direct mode
.github/scripts/create-secret.sh postgres
.github/scripts/create-secret.sh mysql
.github/scripts/create-secret.sh sqlserver
.github/scripts/create-secret.sh oracle
```

**Features:**
- Checks if secret already exists
- Prompts for master connection details
- Allows adding multiple databases
- For each database, allows adding multiple users
- Shows summary before creating/updating
- Creates or updates the secret in AWS Secrets Manager

---

#### add-database-to-server.sh

Add a database to an existing per-server secret.

**Usage:**
```bash
.github/scripts/add-database-to-server.sh
```

**Features:**
- Lists existing server secrets
- Prompts for database details
- Adds application users
- Updates the existing secret

---

#### setup-multiple-servers.sh

Bulk create secrets for multiple servers efficiently.

**Usage:**
```bash
.github/scripts/setup-multiple-servers.sh
```

**Features:**
- Select database type(s)
- Enter multiple server names
- Creates all secrets at once
- Optional configuration phase

**Use case**: Setting up dozens of servers quickly

---

### CLI Utilities

#### update-secret.sh

Command-line tool for quick secret updates without interactive prompts.

**Usage:**
```bash
# Show secret contents
.github/scripts/update-secret.sh postgres show

# Add database
.github/scripts/update-secret.sh postgres add-database thedb \
  "jdbc:postgresql://host:5432/thedb" admin adminpass

# Add user to database
.github/scripts/update-secret.sh postgres add-user thedb app_readwrite rwpass123

# Remove user
.github/scripts/update-secret.sh postgres remove-user thedb old_user

# Remove database
.github/scripts/update-secret.sh postgres remove-database olddb
```

**Use case**: Scripting and automation

---

#### rollback-changeset.sh

Rollback the most recent changeset in a database.

**Usage:**
```bash
.github/scripts/rollback-changeset.sh postgres-thedb
```

**Features:**
- Connects to the database
- Shows most recent changeset
- Prompts for confirmation
- Executes Liquibase rollback

**Warning**: Use with caution in production!

---

## Advanced Topics

### Custom Changelog Locations

By default, changelogs are at the repository root: `changelog-{server}-{dbname}.xml`

To use a different location, update the workflow's discovery step or specify the path manually.

### Multiple Environments

Use different server names for different environments:

- `liquibase-postgres-prod` - Production PostgreSQL
- `liquibase-postgres-staging` - Staging PostgreSQL
- `liquibase-postgres-dev` - Development PostgreSQL

Database identifiers:
- `postgres-prod-thedb`
- `postgres-staging-thedb`
- `postgres-dev-thedb`

### AWS Regions

Secrets can be in different AWS regions. Set the region in:
- GitHub repository variable `AWS_REGION`
- Or when running creation scripts

### IAM Permissions

The GitHub Actions IAM role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:liquibase-*"
    }
  ]
}
```

---

## Quick Reference

### Common Commands

```bash
# Create new server secret
.github/scripts/create-secret.sh postgres

# Add database to existing secret
.github/scripts/add-database-to-server.sh

# View secret
aws secretsmanager get-secret-value \
  --secret-id liquibase-postgres-prod \
  --query SecretString --output text | jq .

# Update user password
.github/scripts/update-secret.sh postgres add-user thedb app_user new_password

# Bulk setup servers
.github/scripts/setup-multiple-servers.sh
```

### File Locations

- **Dockerfile**: `/Dockerfile`
- **Scripts**: `/.github/scripts/`
- **Workflows**: `/.github/workflows/`
- **Changelogs**: `/changelog-{server}-{dbname}.xml`
- **Changesets**: `/db/changelog/{server}/{dbname}/`

### Environment Variables

**In Container:**
- `PATH` - Includes all database tools
- `LD_LIBRARY_PATH` - Oracle libraries
- `LIQUIBASE_VERSION` - Liquibase version (informational)

**In Workflow:**
- `AWS_ROLE_ARN` - IAM role for OIDC authentication
- `AWS_REGION` - AWS region for secrets

---

## Performance Comparison

### Before Docker Container
- Setup time: ~2-3 minutes
- Multiple downloads and installations
- Variable based on network speed

### After Docker Container
- Pull time: ~30 seconds (cached after first pull)
- No installation needed
- Consistent performance
- **Net improvement**: ~2 minutes saved per workflow run

---

## Security Considerations

- ✅ Image built from official Ubuntu base
- ✅ Packages from official repositories
- ✅ Image stored in GitHub Container Registry (private)
- ✅ Automatic security updates when Dockerfile rebuilt
- ✅ Minimal attack surface (only required tools)
- ✅ Secrets never stored in container
- ✅ Passwords masked in logs
- ✅ OIDC authentication (no long-lived keys)
