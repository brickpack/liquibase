#!/bin/bash
set -e

DATABASE_TYPE=$1
DATABASE_NAME=$2
SECRET_NAME=${3:-"liquibase-databases"}

if [ -z "$DATABASE_TYPE" ] || [ -z "$DATABASE_NAME" ]; then
    echo "❌ Usage: $0 <database_type> <database_name> [secret_name]"
    echo "Database types: postgresql, mysql, sqlserver, oracle"
    exit 1
fi

echo "🏗️ Creating $DATABASE_TYPE database: $DATABASE_NAME"

case "$DATABASE_TYPE" in
    postgresql)
        ./.github/scripts/create-postgres-database.sh "$DATABASE_NAME" "$SECRET_NAME"
        ;;
    mysql)
        echo "❌ MySQL database creation not implemented yet"
        echo "💡 To implement: create .github/scripts/create-mysql-database.sh"
        exit 1
        ;;
    sqlserver)
        echo "❌ SQL Server database creation not implemented yet"
        echo "💡 To implement: create .github/scripts/create-sqlserver-database.sh"
        exit 1
        ;;
    oracle)
        echo "❌ Oracle database creation not implemented yet"
        echo "💡 To implement: create .github/scripts/create-oracle-database.sh"
        exit 1
        ;;
    *)
        echo "❌ Unsupported database type: $DATABASE_TYPE"
        echo "Supported types: postgresql, mysql, sqlserver, oracle"
        exit 1
        ;;
esac

echo "✅ Database creation completed successfully"