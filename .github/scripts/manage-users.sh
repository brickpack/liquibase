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
DB_INFO=$(echo "$DB_CONFIG" | jq -r ".\"$DATABASE_NAME\"")

if [ "$DB_INFO" = "null" ] || [ -z "$DB_INFO" ]; then
    echo "Database $DATABASE_NAME not found in secrets"
    exit 1
fi

DB_TYPE=$(echo "$DB_INFO" | jq -r '.type')
DB_URL=$(echo "$DB_INFO" | jq -r '.url')
ADMIN_USER=$(echo "$DB_INFO" | jq -r '.username')
ADMIN_PASS=$(echo "$DB_INFO" | jq -r '.password')

# Parse JDBC URL to extract host, port, and database name
# PostgreSQL/MySQL format: jdbc:postgresql://host:port/database
# Oracle format: jdbc:oracle:thin:@host:port:sid or jdbc:oracle:thin:@//host:port/service
# SQL Server format: jdbc:sqlserver://host:port;databaseName=database
if [[ "$DB_URL" =~ jdbc:sqlserver://([^:]+):([^\;]+)\;databaseName=(.+) ]]; then
    # SQL Server format: jdbc:sqlserver://host:port;databaseName=database
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@//([^:]+):([^/]+)/(.+) ]]; then
    # Oracle service name format: jdbc:oracle:thin:@//host:port/service
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([^:]+):(.+) ]]; then
    # Oracle SID format: jdbc:oracle:thin:@host:port:sid
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:([^:]+)://([^:]+):([^/]+)/(.+) ]]; then
    # PostgreSQL/MySQL format: jdbc:postgresql://host:port/database
    DB_HOST="${BASH_REMATCH[2]}"
    DB_PORT="${BASH_REMATCH[3]}"
    DB_NAME="${BASH_REMATCH[4]}"
else
    echo "Failed to parse JDBC URL: $DB_URL"
    exit 1
fi

# Get user passwords
USER_SECRETS=$(aws secretsmanager get-secret-value --secret-id "$USER_SECRET_NAME" --query SecretString --output text)

echo "Managing users for $DATABASE_NAME ($DB_TYPE)..."

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

# MySQL
elif [ "$DB_TYPE" = "mysql" ]; then
    for username in $(echo "$USER_SECRETS" | jq -r 'keys[]'); do
        password=$(echo "$USER_SECRETS" | jq -r ".$username")
        echo "  Setting password for: $username"

        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -D "$DB_NAME" <<EOF
-- Create user if doesn't exist, or just alter password if exists
CREATE USER IF NOT EXISTS '${username}'@'%' IDENTIFIED BY '${password}';
ALTER USER '${username}'@'%' IDENTIFIED BY '${password}';
FLUSH PRIVILEGES;
EOF
        echo "    ✓ $username"
    done

# SQL Server
elif [ "$DB_TYPE" = "sqlserver" ]; then
    echo "  ⚠️  SQL Server password management not yet implemented"
    echo "  SQL Server users must be created by Liquibase with temporary passwords"
    echo "  Then manually update passwords using: ALTER LOGIN [username] WITH PASSWORD = 'newpassword';"
    echo "  Or install SQL Server tools in GitHub Actions and update this script"
fi

echo "✅ User management completed for $DATABASE_NAME"
