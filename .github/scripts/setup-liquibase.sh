#!/bin/bash
set -e

echo "📦 Setting up Liquibase and database drivers..."

# Install SQL Server command line tools
echo "📦 Installing SQL Server tools..."
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
export PATH="$PATH:/opt/mssql-tools/bin"

# Download Liquibase (latest stable version)
wget -q https://github.com/liquibase/liquibase/releases/download/v4.33.0/liquibase-4.33.0.tar.gz
tar -xzf liquibase-4.33.0.tar.gz
chmod +x liquibase

# Create drivers directory
mkdir -p drivers

# Download database drivers (PostgreSQL included in Liquibase 4.33.0)
echo "📦 Downloading database drivers..."
wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar -O drivers/mysql.jar
wget -q https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.4.2.jre8/mssql-jdbc-12.4.2.jre8.jar -O drivers/sqlserver.jar
echo "ℹ️ PostgreSQL driver included in Liquibase 4.33.0"

echo "✅ Liquibase and drivers ready"
ls -la drivers/