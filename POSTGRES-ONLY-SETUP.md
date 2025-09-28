# PostgreSQL-Only Configuration

This repository is currently configured to deploy only to PostgreSQL databases.

## Current State

- **Active**: `changelog-postgres-prod.xml`
- **Disabled**: Other database changelog files have been renamed to `.disabled`
- **AWS Secret**: Only contains PostgreSQL configuration

## Re-enabling Other Databases

### 1. Re-enable Changelog Files

```bash
# Re-enable MySQL
mv changelog-mysql-prod.xml.disabled changelog-mysql-prod.xml

# Re-enable SQL Server
mv changelog-sqlserver-prod.xml.disabled changelog-sqlserver-prod.xml

# Re-enable Oracle
mv changelog-oracle-prod.xml.disabled changelog-oracle-prod.xml
```

### 2. Update AWS Secrets Manager

Add the other database configurations back to your `liquibase-databases` secret:

```json
{
  "postgres-prod": {
    "type": "postgresql",
    "url": "jdbc:postgresql://postgres-prod.company.com:5432/userdb",
    "username": "postgres_user",
    "password": "secure_postgres_password"
  },
  "mysql-prod": {
    "type": "mysql",
    "url": "jdbc:mysql://mysql-prod.company.com:3306/ecommerce?useSSL=true&serverTimezone=UTC",
    "username": "mysql_user",
    "password": "secure_mysql_password"
  },
  "sqlserver-prod": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://sqlserver-prod.company.com:1433;databaseName=reporting;encrypt=true",
    "username": "sqlserver_user",
    "password": "secure_sqlserver_password"
  },
  "oracle-prod": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@oracle-prod.company.com:1521:LEGACY",
    "username": "oracle_user",
    "password": "secure_oracle_password"
  }
}
```

### 3. Test Multi-Database Setup

After re-enabling:
- Push to a feature branch to test all databases in offline mode
- Check the workflow discovers all 4 databases
- Verify SQL previews are generated for all platforms

## Quick Enable/Disable Commands

```bash
# Disable all except PostgreSQL
mv changelog-mysql-prod.xml changelog-mysql-prod.xml.disabled
mv changelog-sqlserver-prod.xml changelog-sqlserver-prod.xml.disabled
mv changelog-oracle-prod.xml changelog-oracle-prod.xml.disabled

# Enable all databases
mv changelog-mysql-prod.xml.disabled changelog-mysql-prod.xml
mv changelog-sqlserver-prod.xml.disabled changelog-sqlserver-prod.xml
mv changelog-oracle-prod.xml.disabled changelog-oracle-prod.xml
```