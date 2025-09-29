#!/bin/bash
set -e

echo "📦 Setting up Liquibase and database drivers (fast mode)..."

# Install lightweight SQL Server tools using Python (much faster)
echo "📦 Installing SQL Server tools (lightweight Python approach)..."

# Install Python ODBC dependencies (much faster than full mssql-tools)
echo "🔄 Installing minimal ODBC dependencies..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends python3-pip unixodbc unixodbc-dev 2>/dev/null

# Install Microsoft ODBC Driver (smaller than mssql-tools)
echo "🔄 Installing Microsoft ODBC Driver..."
if [ ! -f /usr/share/keyrings/microsoft-prod.gpg ]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/microsoft-prod.gpg
fi

if [ ! -f /etc/apt/sources.list.d/mssql-release.list ]; then
    curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
fi

sudo apt-get update -qq

# Install only the ODBC driver, not the full tools package
if sudo DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 2>/dev/null; then
    echo "✅ Installed Microsoft ODBC Driver 18"
else
    echo "⚠️ Could not install Microsoft ODBC Driver"
    echo "ℹ️ SQL Server database creation will be skipped"
fi

# Install Python pyodbc (lightweight)
echo "🔄 Installing Python pyodbc..."
pip3 install --user pyodbc 2>/dev/null || echo "⚠️ Could not install pyodbc"

# Make our Python script executable
chmod +x ./.github/scripts/create-database-python.py

echo "✅ Lightweight SQL Server tools ready"

# Download Liquibase (latest stable version)
echo "📦 Downloading Liquibase..."
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