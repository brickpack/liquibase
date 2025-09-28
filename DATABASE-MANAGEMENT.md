# Database Management Guide

This guide explains how to create and manage databases across multiple platforms using the automated pipeline.

**Current Implementation Status:**
- ✅ **PostgreSQL**: Fully implemented (bootstrap + scripts)
- 🚧 **MySQL**: Pipeline ready, implementation pending
- 🚧 **SQL Server**: Pipeline ready, implementation pending
- 🚧 **Oracle**: Pipeline ready, implementation pending

## Quick Start

### 1. Create a Database (Existing Instance)
```bash
# Via GitHub Actions UI:
# Go to Actions → Database Management → Run workflow
# Select: create-database
# Database type: postgresql (others available but not implemented yet)
# Database name: analytics

# Via CLI scripts (PostgreSQL only implemented):
./.github/scripts/create-database.sh postgresql analytics
./.github/scripts/create-database.sh postgresql reporting
./.github/scripts/create-database.sh postgresql warehouse

# Other platforms will show helpful error messages:
./.github/scripts/create-database.sh mysql ecommerce
# ❌ MySQL database creation not implemented yet
# 💡 To implement: create .github/scripts/create-mysql-database.sh
```

### 2. Create RDS Instance
```bash
# Via GitHub Actions UI:
# Go to Actions → Database Management → Run workflow
# Select: create-rds-instance
# Database type: postgresql
# Database name: analytics-prod
# Instance class: db.t3.micro
```

### 3. Bootstrap Databases
```bash
# Via GitHub Actions UI:
# Go to Actions → Database Management → Run workflow
# Select: run-bootstrap
# (Optional) Database type: postgresql (or leave blank for all)
```

## Database Creation Methods

### Method 1: Bootstrap Changesets (Recommended)
Uses Liquibase changesets to create databases automatically:

**Files:**
- `changelog-bootstrap.xml` - Main bootstrap changelog
- `db/bootstrap/postgres/001-create-databases.sql` - PostgreSQL databases
- `db/bootstrap/mysql/001-create-databases.sql` - MySQL databases
- `db/bootstrap/sqlserver/001-create-databases.sql` - SQL Server databases
- `db/bootstrap/oracle/001-create-databases.sql` - Oracle schemas

**How it works:**
1. Push to main branch triggers bootstrap job
2. Connects to master/system database
3. Runs bootstrap changesets to create databases
4. Updates AWS Secrets Manager with new configurations

### Method 2: Management Scripts
Direct database creation via platform-specific scripts:

**Scripts:**
- `.github/scripts/create-database.sh` - Main entry point
- `.github/scripts/create-postgres-database.sh` - PostgreSQL
- `.github/scripts/create-mysql-database.sh` - MySQL
- `.github/scripts/create-sqlserver-database.sh` - SQL Server
- `.github/scripts/create-oracle-database.sh` - Oracle

## Platform-Specific Details

### PostgreSQL
**Creates:** Databases with UTF8 encoding
**Requires:** Connection to `postgres` system database
**Secret Key Pattern:** `postgres-{database_name}`

```sql
-- Example bootstrap changeset
CREATE DATABASE analytics;
COMMENT ON DATABASE analytics IS 'Analytics database';
```

### MySQL
**Creates:** Databases with UTF8MB4 charset
**Requires:** Connection to MySQL root/admin user
**Secret Key Pattern:** `mysql-{database_name}`

```sql
-- Example bootstrap changeset
CREATE DATABASE ecommerce CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### SQL Server
**Creates:** Databases with Latin1 collation
**Requires:** Connection to master database
**Secret Key Pattern:** `sqlserver-{database_name}`

```sql
-- Example bootstrap changeset
CREATE DATABASE reporting COLLATE SQL_Latin1_General_CP1_CI_AS;
```

### Oracle
**Creates:** Users/schemas with dedicated tablespaces
**Requires:** Connection with DBA privileges
**Secret Key Pattern:** `oracle-{schema_name}`

```sql
-- Example bootstrap changeset
CREATE TABLESPACE analytics_data DATAFILE 'analytics01.dbf' SIZE 100M;
CREATE USER analytics_app IDENTIFIED BY password DEFAULT TABLESPACE analytics_data;
GRANT CONNECT, RESOURCE TO analytics_app;
```

## AWS Secrets Manager Integration

### Secret Structure
```json
{
  "postgres-analytics": {
    "type": "postgresql",
    "url": "jdbc:postgresql://host:5432/analytics",
    "username": "postgres_user",
    "password": "secure_password"
  },
  "mysql-ecommerce": {
    "type": "mysql",
    "url": "jdbc:mysql://host:3306/ecommerce?useSSL=true",
    "username": "mysql_user",
    "password": "secure_password"
  }
}
```

### Master Database Configurations
Each platform needs a master/system database configuration:

- `postgres-master` or `postgres-system` - For PostgreSQL
- `mysql-master` or `mysql-system` - For MySQL
- `sqlserver-master` or `sqlserver-system` - For SQL Server
- `oracle-master` or `oracle-system` - For Oracle

## Workflow Integration

### Automatic Discovery
The main CI/CD workflow automatically:
1. Scans for `changelog-*.xml` files
2. Discovers new databases in secrets
3. Deploys to all discovered databases in parallel

### Bootstrap Integration
The bootstrap job runs:
- **When:** Push to main branch
- **Condition:** `changelog-bootstrap.xml` exists
- **Action:** Creates databases before main deployment

## Usage Examples

### Example 1: Add Analytics Database
```bash
# 1. Create the database
./.github/scripts/create-database.sh postgresql analytics

# 2. Create changelog file
cat > changelog-postgres-analytics.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog">
    <include file="db/changelog/analytics/001-schema.sql"/>
</databaseChangeLog>
EOF

# 3. Create schema files
mkdir -p db/changelog/analytics
cat > db/changelog/analytics/001-schema.sql << 'EOF'
--liquibase formatted sql
--changeset analytics-team:001-create-events-table
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# 4. Commit and deploy
git add .
git commit -m "Add analytics database"
git push  # Triggers automatic deployment
```

### Example 2: Multi-Platform Setup
```bash
# Create databases across all platforms
./.github/scripts/create-database.sh postgresql userdb
./.github/scripts/create-database.sh mysql ecommerce
./.github/scripts/create-database.sh sqlserver reporting
./.github/scripts/create-database.sh oracle legacy

# All will be automatically discovered and deployed in parallel
```

## Troubleshooting

### Common Issues

1. **Master database not found**
   - Ensure master database config exists in secrets
   - Use keys like `postgres-master`, `mysql-master`, etc.

2. **Permission denied**
   - Master user needs CREATE DATABASE privileges
   - Oracle user needs DBA role for user/tablespace creation

3. **Connection failures**
   - Verify security groups allow connections
   - Check VPC/subnet configurations

### Debugging Commands
```bash
# List current configurations
aws secretsmanager get-secret-value \
    --secret-id liquibase-databases \
    --query SecretString | jq

# Test database connection
./.github/scripts/configure-database.sh postgres-master liquibase-databases false
./.github/scripts/run-liquibase.sh postgres-master status
```

## Best Practices

1. **Use Bootstrap Method** - Version controlled, auditable
2. **Master Connections** - Keep separate master configs for database creation
3. **Naming Convention** - Use `{platform}-{purpose}` pattern
4. **Security** - Rotate passwords regularly, use least privilege
5. **Testing** - Test database creation in non-production first

## Next Steps

After database creation:
1. Database appears in workflow discovery
2. Liquibase deploys schema automatically
3. Monitor deployment logs for success
4. Verify database contents via AWS Console or direct connection