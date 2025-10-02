#!/bin/bash
set -e

# Simple user management script that runs independently of Liquibase
# Usage: ./manage-users.sh <database>
# Example: ./manage-users.sh postgres-thedb

DATABASE=$1

if [ -z "$DATABASE" ]; then
    echo "Usage: $0 <database>"
    echo "Example: $0 postgres-thedb"
    exit 1
fi

echo "Managing users for database: $DATABASE"

# Parse database identifier (e.g., "postgres-thedb" -> server="postgres", dbname="thedb")
DB_SERVER=$(echo "$DATABASE" | cut -d'-' -f1)
DB_NAME=$(echo "$DATABASE" | cut -d'-' -f2-)

echo "Parsed: Server Type=$DB_SERVER, Database Name=$DB_NAME"

# Get credentials from per-server secret
SECRET_NAME="liquibase-${DB_SERVER}-prod"

echo "Reading secret: $SECRET_NAME"
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text)

# Extract database configuration from: secret.databases.{dbname}
DB_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg db "$DB_NAME" '.databases[$db] // empty')

if [ -z "$DB_CONFIG" ] || [ "$DB_CONFIG" = "null" ]; then
    echo "❌ Database '$DB_NAME' not found in secret '$SECRET_NAME'"
    echo ""
    echo "Available databases in this secret:"
    echo "$SECRET_JSON" | jq -r '.databases | keys[]' 2>/dev/null || echo "  (none found)"
    exit 1
fi

DB_URL=$(echo "$DB_CONFIG" | jq -r '.connection.url')
ADMIN_USER=$(echo "$DB_CONFIG" | jq -r '.connection.username')
ADMIN_PASS=$(echo "$DB_CONFIG" | jq -r '.connection.password')

# Get user passwords from same database config
USER_SECRETS=$(echo "$DB_CONFIG" | jq -r '.users // {}')

# Auto-detect database type from server name or URL
case "$DB_SERVER" in
    "postgres"|"postgresql")
        DB_TYPE="postgresql"
        ;;
    "mysql")
        DB_TYPE="mysql"
        ;;
    "sqlserver"|"mssql")
        DB_TYPE="sqlserver"
        ;;
    "oracle"|"ora")
        DB_TYPE="oracle"
        ;;
    *)
        # Fallback: try to detect from URL
        if [[ "$DB_URL" == *"postgresql"* ]]; then
            DB_TYPE="postgresql"
        elif [[ "$DB_URL" == *"mysql"* ]]; then
            DB_TYPE="mysql"
        elif [[ "$DB_URL" == *"sqlserver"* ]]; then
            DB_TYPE="sqlserver"
        elif [[ "$DB_URL" == *"oracle"* ]]; then
            DB_TYPE="oracle"
        else
            echo "❌ Cannot determine database type from server name '$DB_SERVER' or URL"
            exit 1
        fi
        ;;
esac

echo "Database type: $DB_TYPE"

# Parse JDBC URL to extract host, port, and database name
# PostgreSQL/MySQL format: jdbc:postgresql://host:port/database
# Oracle format: jdbc:oracle:thin:@host:port:sid or jdbc:oracle:thin:@//host:port/service
# SQL Server format: jdbc:sqlserver://host:port;databaseName=database
if [[ "$DB_URL" =~ jdbc:sqlserver://([^:]+):([^\;]+)\;databaseName=(.+) ]]; then
    # SQL Server format: jdbc:sqlserver://host:port;databaseName=database
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@//([^:]+):([^/]+)/(.+) ]]; then
    # Oracle service name format: jdbc:oracle:thin:@//host:port/service
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([^:]+):(.+) ]]; then
    # Oracle SID format: jdbc:oracle:thin:@host:port:sid
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:([^:]+)://([^:]+):([^/]+)/(.+) ]]; then
    # PostgreSQL/MySQL format: jdbc:postgresql://host:port/database
    DB_HOST="${BASH_REMATCH[2]}"
    DB_PORT="${BASH_REMATCH[3]}"
    JDBC_DB_NAME="${BASH_REMATCH[4]}"
else
    echo "Failed to parse JDBC URL: $DB_URL"
    exit 1
fi

# Check if there are any users to manage
if [ -z "$USER_SECRETS" ] || [ "$USER_SECRETS" = "{}" ] || [ "$USER_SECRETS" = "null" ]; then
    echo "ℹ️  No users configured for database '$DB_NAME' in secret '$SECRET_NAME'"
    echo "   Users are managed at: .databases.$DB_NAME.users"
    exit 0
fi

echo "Managing users for $DB_NAME ($DB_TYPE)..."

# Oracle
if [ "$DB_TYPE" = "oracle" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        # Create temporary SQL file for Liquibase execution
        TEMP_SQL="/tmp/set-password-${username}-$$.sql"
        cat > "$TEMP_SQL" <<EOF
DECLARE
    user_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO user_exists FROM dba_users WHERE username = UPPER('${username}');

    IF user_exists = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER ${username} IDENTIFIED BY "${password}" DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP ACCOUNT UNLOCK';
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO ${username}';
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER ${username} IDENTIFIED BY "${password}"';
    END IF;
END;
/
EOF

        # Execute using Liquibase's execute-sql command
        echo "    Executing SQL for $username..."
        if liquibase --url="$DB_URL" \
                  --username="$ADMIN_USER" \
                  --password="$ADMIN_PASS" \
                  --changeLogFile="$TEMP_SQL" \
                  execute-sql \
                  --sql-file="$TEMP_SQL" 2>&1 | grep -v "Liquibase Version" | grep -v "Liquibase Open Source"; then
            echo "    ✓ $username password set"
        else
            echo "    ⚠️  Failed to set password for $username - check logs above"
        fi

        rm -f "$TEMP_SQL"
    done

# PostgreSQL
elif [ "$DB_TYPE" = "postgresql" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        PGPASSWORD="$ADMIN_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$ADMIN_USER" -d "$JDBC_DB_NAME" -v ON_ERROR_STOP=1 <<EOF
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

# MySQL
elif [ "$DB_TYPE" = "mysql" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -D "$JDBC_DB_NAME" <<EOF
-- Create user if doesn't exist, or just alter password if exists
CREATE USER IF NOT EXISTS '${username}'@'%' IDENTIFIED BY '${password}';
ALTER USER '${username}'@'%' IDENTIFIED BY '${password}';
FLUSH PRIVILEGES;
EOF
        echo "    ✓ $username"
    done

# SQL Server
elif [ "$DB_TYPE" = "sqlserver" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        # Use sqlcmd from mssql-tools18 (available in Docker image)
        sqlcmd -S "$DB_HOST,$DB_PORT" -U "$ADMIN_USER" -P "$ADMIN_PASS" -d "$JDBC_DB_NAME" -C <<EOF
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = '$username')
BEGIN
    CREATE LOGIN [$username] WITH PASSWORD = '$password';
    PRINT 'Created login: $username';
END
ELSE
BEGIN
    ALTER LOGIN [$username] WITH PASSWORD = '$password';
    PRINT 'Updated password for: $username';
END

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$username')
BEGIN
    CREATE USER [$username] FOR LOGIN [$username];
    PRINT 'Created user: $username';
END
GO
EOF
        echo "    ✓ $username"
    done
fi

echo "✅ User management completed for $DB_NAME"
