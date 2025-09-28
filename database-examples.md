# Database Connection Examples

This document provides JDBC URL examples for different database types supported by the Liquibase CI/CD pipeline.

## PostgreSQL

### Standard Connection
```json
{
  "postgres-prod": {
    "type": "postgresql",
    "url": "jdbc:postgresql://hostname:5432/database",
    "username": "username",
    "password": "password"
  }
}
```

### AWS RDS PostgreSQL
```json
{
  "postgres-rds": {
    "type": "postgresql",
    "url": "jdbc:postgresql://mydb.cluster-abc123.us-east-1.rds.amazonaws.com:5432/mydb?sslmode=require",
    "username": "postgres_user",
    "password": "secure_password"
  }
}
```

## MySQL

### Standard Connection
```json
{
  "mysql-prod": {
    "type": "mysql",
    "url": "jdbc:mysql://hostname:3306/database?useSSL=true&serverTimezone=UTC",
    "username": "username",
    "password": "password"
  }
}
```

### AWS RDS MySQL
```json
{
  "mysql-rds": {
    "type": "mysql",
    "url": "jdbc:mysql://mydb.cluster-def456.us-east-1.rds.amazonaws.com:3306/mydb?useSSL=true&serverTimezone=UTC&requireSSL=true",
    "username": "mysql_user",
    "password": "secure_password"
  }
}
```

## SQL Server

### Standard Connection
```json
{
  "sqlserver-prod": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://hostname:1433;databaseName=database;encrypt=true;trustServerCertificate=false",
    "username": "username",
    "password": "password"
  }
}
```

### Azure SQL Database
```json
{
  "azure-sql": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://myserver.database.windows.net:1433;databaseName=mydb;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30",
    "username": "sql_user@myserver",
    "password": "secure_password"
  }
}
```

### AWS RDS SQL Server
```json
{
  "sqlserver-rds": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://mydb.abc123.us-east-1.rds.amazonaws.com:1433;databaseName=mydb;encrypt=true;trustServerCertificate=true",
    "username": "sql_user",
    "password": "secure_password"
  }
}
```

## Oracle

### Standard Connection
```json
{
  "oracle-prod": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@hostname:1521:SID",
    "username": "username",
    "password": "password"
  }
}
```

### Oracle Service Name
```json
{
  "oracle-service": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@//hostname:1521/servicename",
    "username": "username",
    "password": "password"
  }
}
```

### AWS RDS Oracle
```json
{
  "oracle-rds": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@mydb.abc123.us-east-1.rds.amazonaws.com:1521:ORCL",
    "username": "oracle_user",
    "password": "secure_password"
  }
}
```

## Auto-Detection Examples

The pipeline can auto-detect database types from URLs. The `type` field is optional when URLs contain these keywords:

```json
{
  "auto-postgres": {
    "url": "jdbc:postgresql://db.example.com:5432/mydb",
    "username": "user",
    "password": "pass"
  },
  "auto-mysql": {
    "url": "jdbc:mysql://db.example.com:3306/mydb",
    "username": "user",
    "password": "pass"
  },
  "auto-sqlserver": {
    "url": "jdbc:sqlserver://db.example.com:1433;databaseName=mydb",
    "username": "user",
    "password": "pass"
  },
  "auto-oracle": {
    "url": "jdbc:oracle:thin:@db.example.com:1521:ORCL",
    "username": "user",
    "password": "pass"
  }
}
```

## Notes

1. **SSL/TLS**: Always use encrypted connections for production databases
2. **Timeouts**: Consider adding connection timeout parameters for reliability
3. **Timezone**: MySQL requires `serverTimezone` parameter
4. **Oracle**: Requires manual driver setup due to licensing restrictions
5. **Cloud Providers**: Each cloud provider may have specific connection requirements