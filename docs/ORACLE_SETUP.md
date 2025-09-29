# Oracle Database Setup for Liquibase CI/CD

## Quick Setup Guide

When using **minimal setup mode**, Oracle databases must be configured manually. Here's what you need:

### 1. Oracle RDS Instance Requirements

Your Oracle RDS instance should be:

- ✅ **Running** and accessible
- ✅ **Service Name**: `ORCL` (default)
- ✅ **Port**: `1521` (default)
- ✅ **Network**: Accessible from GitHub Actions

### 2. AWS Secrets Manager Configuration

Add Oracle credentials to your `liquibase-databases` secret in AWS Secrets Manager:

```json
{
  "oracle-finance": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@your-oracle-host:1521:finance",
    "username": "your_oracle_user",
    "password": "your_oracle_password"
  }
}
```

**Note**: The pipeline will automatically convert the URL from SID format (`:finance`) to Service Name format (`/ORCL`).

### 3. Oracle User Requirements

The Oracle user needs these privileges:

```sql
-- Connect to Oracle database
GRANT CONNECT TO your_oracle_user;

-- Create objects (tables, indexes, sequences, etc.)
GRANT RESOURCE TO your_oracle_user;

-- Create views
GRANT CREATE VIEW TO your_oracle_user;

-- Create sequences
GRANT CREATE SEQUENCE TO your_oracle_user;

-- For Liquibase tracking tables
GRANT CREATE TABLE TO your_oracle_user;
```

### 4. Common Issues

| Error | Solution |
|-------|----------|
| `ORA-12505` (SID not known) | ✅ Fixed automatically - URL converted to service name |
| `ORA-12514` (Service not known) | ✅ Fixed automatically - uses `ORCL` service name |
| `ORA-01017` (Invalid credentials) | ❌ **Update AWS Secrets Manager** with correct Oracle credentials |
| `ORA-00942` (Table not found) | ✅ Normal - Liquibase will create tracking tables |

### 5. Testing Connection

You can test the connection manually:

```bash
# Using SQL*Plus or similar Oracle client
sqlplus your_oracle_user/your_oracle_password@your-oracle-host:1521/ORCL
```

### 6. Pipeline Behavior

The minimal setup pipeline will:

1. ⚡ **Skip** Oracle database creation (fast)
2. 🔧 **Auto-convert** URL format (SID → Service Name)
3. 📝 **Use** `ORCL` as the service name
4. 🔗 **Connect** using your AWS Secrets Manager credentials
5. 🚀 **Deploy** Liquibase changesets

## Current Status

Based on the latest pipeline run:

- ✅ Oracle JDBC driver downloaded successfully
- ✅ Oracle URL format converted successfully
- ✅ Oracle service `ORCL` found successfully
- ❌ **Oracle credentials need to be updated in AWS Secrets Manager**

## Next Steps

1. **Update AWS Secrets Manager** with correct Oracle credentials
2. **Verify Oracle user privileges** for creating tables/sequences
3. **Re-run the pipeline** - should connect successfully
