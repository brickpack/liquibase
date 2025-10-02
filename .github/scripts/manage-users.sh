#!/bin/bash
set -e

# Simple user management script that runs independently of Liquibase
# Usage: ./manage-users.sh <database-name> <secret-name>

DATABASE_NAME=$1
USER_SECRET_NAME=$2

if [ -z "$DATABASE_NAME" ] || [ -z "$USER_SECRET_NAME" ]; then
    echo "Usage: $0 <database-name> <user-secret-name>"
    exit 1
fi

# Get database connection info
DB_CONFIG=$(aws secretsmanager get-secret-value --secret-id liquibase-databases --query SecretString --output text)
DB_INFO=$(echo "$DB_CONFIG" | jq -r ".databases[] | select(.name==\"$DATABASE_NAME\")")

if [ -z "$DB_INFO" ]; then
    echo "Database $DATABASE_NAME not found in secrets"
    exit 1
fi

DB_TYPE=$(echo "$DB_INFO" | jq -r '.type')
DB_HOST=$(echo "$DB_INFO" | jq -r '.host')
DB_PORT=$(echo "$DB_INFO" | jq -r '.port')
DB_NAME=$(echo "$DB_INFO" | jq -r '.database')
ADMIN_USER=$(echo "$DB_INFO" | jq -r '.username')
ADMIN_PASS=$(echo "$DB_INFO" | jq -r '.password')

# Get user passwords
USER_SECRETS=$(aws secretsmanager get-secret-value --secret-id "$USER_SECRET_NAME" --query SecretString --output text)

echo "Managing users for $DATABASE_NAME ($DB_TYPE)..."

# Oracle
if [ "$DB_TYPE" = "oracle" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        sqlplus -s "$ADMIN_USER/$ADMIN_PASS@//$DB_HOST:$DB_PORT/$DB_NAME" <<EOF
SET HEADING OFF
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- Create user if doesn't exist, or just alter password if exists
DECLARE
    user_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO user_exists FROM dba_users WHERE username = UPPER('$username');

    IF user_exists = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER $username IDENTIFIED BY "$password" DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP ACCOUNT UNLOCK';
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO $username';
        DBMS_OUTPUT.PUT_LINE('Created user: $username');
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER $username IDENTIFIED BY "$password"';
        DBMS_OUTPUT.PUT_LINE('Updated password for: $username');
    END IF;
END;
/
EXIT;
EOF
        echo "    ✓ $username"
    done

# PostgreSQL
elif [ "$DB_TYPE" = "postgresql" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        PGPASSWORD="$ADMIN_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$ADMIN_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$username') THEN
        CREATE USER $username WITH PASSWORD '$password';
        RAISE NOTICE 'Created user: $username';
    ELSE
        ALTER USER $username WITH PASSWORD '$password';
        RAISE NOTICE 'Updated password for: $username';
    END IF;
END
\$\$;
EOF
        echo "    ✓ $username"
    done

# SQL Server
elif [ "$DB_TYPE" = "sqlserver" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        /opt/mssql-tools/bin/sqlcmd -S "$DB_HOST,$DB_PORT" -U "$ADMIN_USER" -P "$ADMIN_PASS" -d "$DB_NAME" <<EOF
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$username')
BEGIN
    CREATE LOGIN [$username] WITH PASSWORD = '$password';
    CREATE USER [$username] FOR LOGIN [$username];
    PRINT 'Created user: $username';
END
ELSE
BEGIN
    ALTER LOGIN [$username] WITH PASSWORD = '$password';
    PRINT 'Updated password for: $username';
END
GO
EOF
        echo "    ✓ $username"
    done
fi

echo "✅ User management completed for $DATABASE_NAME"
