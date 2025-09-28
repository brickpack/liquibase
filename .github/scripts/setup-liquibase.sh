#!/bin/bash
set -e

echo "📦 Setting up Liquibase and database drivers..."

# Download Liquibase (latest stable version)
wget -q https://github.com/liquibase/liquibase/releases/download/v4.33.0/liquibase-4.33.0.tar.gz
tar -xzf liquibase-4.33.0.tar.gz
chmod +x liquibase

# Create drivers directory
mkdir -p drivers

# Download database drivers
echo "📦 Downloading database drivers..."
wget -q https://jdbc.postgresql.org/download/postgresql-42.7.1.jar -O drivers/postgresql.jar
wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar -O drivers/mysql.jar
wget -q https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.4.2.jre8/mssql-jdbc-12.4.2.jre8.jar -O drivers/sqlserver.jar

echo "✅ Liquibase and drivers ready"
ls -la drivers/