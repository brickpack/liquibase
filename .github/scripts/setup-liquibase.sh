#!/bin/bash
set -e

echo "📦 Setting up Liquibase and database drivers..."

# Install SQL Server command line tools (lightweight approach)
echo "📦 Installing SQL Server tools..."

# Try lightweight sqlcmd from snap first (much faster)
if command -v snap >/dev/null 2>&1; then
    echo "🔄 Trying snap-based sqlcmd (faster installation)..."
    if sudo snap install sqlcmd 2>/dev/null; then
        echo "✅ Installed sqlcmd via snap"
        export PATH="$PATH:/snap/bin"
    else
        echo "⚠️ Snap sqlcmd failed, falling back to Microsoft packages..."
        # Fallback to Microsoft packages but with minimal dependencies
        echo "📦 Installing minimal SQL Server tools..."

        # Only install if not already present (cache-friendly)
        if ! command -v sqlcmd >/dev/null 2>&1; then
            # Install only essential packages without full tool suite
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/microsoft-prod.gpg
            curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
            sudo apt-get update -qq

            # Install only the minimal required packages
            if sudo DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-tools18 2>/dev/null; then
                echo "✅ Installed minimal mssql-tools18"
                export PATH="$PATH:/opt/mssql-tools18/bin"
            else
                echo "⚠️ Could not install SQL Server tools"
                echo "ℹ️ SQL Server database creation will be skipped"
            fi
        else
            echo "✅ sqlcmd already available"
        fi
    fi
else
    echo "⚠️ Snap not available, using traditional installation..."
    # Fallback to Microsoft packages
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/microsoft-prod.gpg
    curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
    sudo apt-get update -qq

    if sudo DEBIAN_FRONTEND=noninteractive ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-tools18 2>/dev/null; then
        echo "✅ Installed minimal mssql-tools18"
        export PATH="$PATH:/opt/mssql-tools18/bin"
    else
        echo "⚠️ Could not install SQL Server tools"
        echo "ℹ️ SQL Server database creation will be skipped"
    fi
fi

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