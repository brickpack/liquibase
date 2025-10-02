#!/bin/bash
set -e

# Script to completely reset all databases and remove all changesets
# WARNING: This is DESTRUCTIVE and cannot be undone!

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script will:"
echo "  1. DROP all databases (PostgreSQL, MySQL, SQL Server, Oracle)"
echo "  2. DROP all database users"
echo "  3. DELETE all changeset files from db/changelog/"
echo "  4. DELETE all changelog XML files"
echo ""
echo "This CANNOT be undone!"
echo ""
read -p "Are you ABSOLUTELY SURE you want to continue? (type 'YES' to confirm): " -r
echo

if [ "$REPLY" != "YES" ]; then
    echo "Reset cancelled"
    exit 0
fi

echo ""
echo "Fetching database credentials from AWS Secrets Manager..."
DB_SECRETS=$(aws secretsmanager get-secret-value --secret-id liquibase-databases --query SecretString --output text)

# PostgreSQL
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dropping PostgreSQL databases..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PG_HOST=$(echo "$DB_SECRETS" | jq -r '."postgres-prod-myappdb".url' | sed -E 's|jdbc:postgresql://([^:]+):.*|\1|')
PG_USER=$(echo "$DB_SECRETS" | jq -r '."postgres-prod-myappdb".username')
PG_PASS=$(echo "$DB_SECRETS" | jq -r '."postgres-prod-myappdb".password')

echo "Host: $PG_HOST"
echo "Dropping databases: myappdb, userdb"

PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -U "$PG_USER" -d postgres <<EOF
-- Terminate existing connections
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname IN ('myappdb', 'userdb')
  AND pid <> pg_backend_pid();

-- Drop databases
DROP DATABASE IF EXISTS myappdb;
DROP DATABASE IF EXISTS userdb;

-- Drop users
DROP USER IF EXISTS myapp_readwrite;

\echo '✅ PostgreSQL databases dropped'
EOF

# MySQL
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dropping MySQL databases..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MYSQL_HOST=$(echo "$DB_SECRETS" | jq -r '."mysql-ecommerce".url' | sed -E 's|jdbc:mysql://([^:]+):.*|\1|')
MYSQL_USER=$(echo "$DB_SECRETS" | jq -r '."mysql-ecommerce".username')
MYSQL_PASS=$(echo "$DB_SECRETS" | jq -r '."mysql-ecommerce".password')

echo "Host: $MYSQL_HOST"
echo "Dropping database: ecommerce"

mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" <<EOF
DROP DATABASE IF EXISTS ecommerce;
DROP USER IF EXISTS 'ecommerce_app'@'%';
FLUSH PRIVILEGES;
SELECT '✅ MySQL database dropped' AS result;
EOF

# SQL Server
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dropping SQL Server databases..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

MSSQL_HOST=$(echo "$DB_SECRETS" | jq -r '."sqlserver-inventory".url' | sed -E 's|jdbc:sqlserver://([^:]+):.*|\1|')
MSSQL_USER=$(echo "$DB_SECRETS" | jq -r '."sqlserver-inventory".username')
MSSQL_PASS=$(echo "$DB_SECRETS" | jq -r '."sqlserver-inventory".password')

echo "Host: $MSSQL_HOST"
echo "Dropping database: inventory"

sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_USER" -P "$MSSQL_PASS" -C -Q "
-- Set database to single user mode to kick out connections
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'inventory')
BEGIN
    ALTER DATABASE inventory SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE inventory;
    PRINT '✅ SQL Server database dropped';
END
ELSE
BEGIN
    PRINT 'Database inventory does not exist';
END

-- Drop login and user
IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'inventory_app')
BEGIN
    DROP LOGIN inventory_app;
    PRINT '✅ SQL Server login dropped';
END
"

# Oracle
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dropping Oracle users and tablespaces..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ORACLE_HOST=$(echo "$DB_SECRETS" | jq -r '."oracle-finance".url' | sed -E 's|jdbc:oracle:thin:@([^:]+):.*|\1|')
ORACLE_USER=$(echo "$DB_SECRETS" | jq -r '."oracle-finance".username')
ORACLE_PASS=$(echo "$DB_SECRETS" | jq -r '."oracle-finance".password')
ORACLE_SID=$(echo "$DB_SECRETS" | jq -r '."oracle-finance".url' | sed -E 's|.*:([^:]+)$|\1|')

echo "Host: $ORACLE_HOST"
echo "SID: $ORACLE_SID"
echo "Dropping users: finance_app, finance_readonly"

sqlplus -S "$ORACLE_USER/$ORACLE_PASS@$ORACLE_HOST:1521/$ORACLE_SID" <<EOF
SET SERVEROUTPUT ON;

DECLARE
    user_not_exist EXCEPTION;
    PRAGMA EXCEPTION_INIT(user_not_exist, -01918);
BEGIN
    BEGIN
        EXECUTE IMMEDIATE 'DROP USER finance_app CASCADE';
        DBMS_OUTPUT.PUT_LINE('✅ Dropped user finance_app');
    EXCEPTION
        WHEN user_not_exist THEN
            DBMS_OUTPUT.PUT_LINE('User finance_app does not exist');
    END;

    BEGIN
        EXECUTE IMMEDIATE 'DROP USER finance_readonly CASCADE';
        DBMS_OUTPUT.PUT_LINE('✅ Dropped user finance_readonly');
    EXCEPTION
        WHEN user_not_exist THEN
            DBMS_OUTPUT.PUT_LINE('User finance_readonly does not exist');
    END;

    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLESPACE FINANCE_DATA INCLUDING CONTENTS AND DATAFILES';
        DBMS_OUTPUT.PUT_LINE('✅ Dropped tablespace FINANCE_DATA');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -959 THEN
                DBMS_OUTPUT.PUT_LINE('Tablespace FINANCE_DATA does not exist');
            ELSE
                RAISE;
            END IF;
    END;
END;
/

EXIT;
EOF

# Remove changeset files
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Removing changeset files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d "db/changelog" ]; then
    echo "Removing db/changelog/ directory..."
    rm -rf db/changelog/
    echo "✅ Removed db/changelog/"
else
    echo "Directory db/changelog/ does not exist"
fi

# Remove changelog XML files
echo ""
echo "Removing changelog XML files..."
CHANGELOG_FILES=$(find . -maxdepth 1 -name "changelog-*.xml" -type f)
if [ -n "$CHANGELOG_FILES" ]; then
    echo "$CHANGELOG_FILES" | while read file; do
        echo "  Removing: $file"
        rm -f "$file"
    done
    echo "✅ Removed all changelog-*.xml files"
else
    echo "No changelog-*.xml files found"
fi

# Remove test rollback file
if [ -f "db/changelog/postgres-prod-server/myappdb/006-test-rollback.sql" ]; then
    rm -f db/changelog/postgres-prod-server/myappdb/006-test-rollback.sql
    echo "✅ Removed test rollback file"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ RESET COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "  ✅ All PostgreSQL databases dropped (myappdb, userdb)"
echo "  ✅ All MySQL databases dropped (ecommerce)"
echo "  ✅ All SQL Server databases dropped (inventory)"
echo "  ✅ All Oracle users dropped (finance_app, finance_readonly)"
echo "  ✅ All changeset files removed"
echo "  ✅ All changelog XML files removed"
echo ""
echo "Next steps:"
echo "  1. Stage changes: git add -A"
echo "  2. Commit: git commit -m 'Reset: Remove all databases and changesets'"
echo "  3. Push: git push"
echo ""
