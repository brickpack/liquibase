#!/bin/bash
set -e

echo "Setting up Liquibase and database drivers (minimal mode)..."

# Skip SQL Server tools installation entirely - assume database exists
echo "Minimal setup mode: Skipping SQL Server tools installation"
echo "SQL Server databases must be created manually or via other means"
echo "This speeds up CI/CD pipeline by avoiding heavy Microsoft package installation"

# Download Liquibase (latest stable version)
echo "Downloading Liquibase..."
wget -q https://github.com/liquibase/liquibase/releases/download/v4.33.0/liquibase-4.33.0.tar.gz
tar -xzf liquibase-4.33.0.tar.gz
chmod +x liquibase

# Create drivers directory
mkdir -p drivers

# Download database drivers (PostgreSQL included in Liquibase 4.33.0)
echo "Downloading database drivers..."
wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar -O drivers/mysql.jar &
wget -q https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.4.2.jre8/mssql-jdbc-12.4.2.jre8.jar -O drivers/sqlserver.jar &
wget -q https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/23.3.0.23.09/ojdbc8-23.3.0.23.09.jar -O drivers/oracle.jar &

# Wait for parallel downloads
wait

echo "PostgreSQL driver included in Liquibase 4.33.0"
echo "Liquibase and drivers ready (minimal setup completed)"
ls -la drivers/