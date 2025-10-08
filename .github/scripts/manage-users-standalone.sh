#!/bin/bash
set -e

# Standalone user management script for manual operations
# Called by manage-users.yml workflow
# Usage: ./manage-users-standalone.sh <database> <action> [username]

DATABASE=$1
ACTION=$2
USERNAME=$3

if [ -z "$DATABASE" ] || [ -z "$ACTION" ]; then
    echo "Usage: $0 <database> <action> [username]"
    echo "Example: $0 postgres-thedb sync-passwords"
    echo "Example: $0 postgres-thedb rotate-password app_readwrite"
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
if [[ "$DB_URL" =~ jdbc:sqlserver://([^:]+):([^\;]+)\;databaseName=(.+) ]]; then
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    JDBC_DB_NAME=$(echo "$DB_URL" | sed -n 's/.*databaseName=\([^;]*\).*/\1/p')
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@//([^:]+):([^/]+)/(.+) ]]; then
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([^:]+):(.+) ]]; then
    DB_HOST="${BASH_REMATCH[1]}"
    DB_PORT="${BASH_REMATCH[2]}"
    JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:([^:]+)://([^:]+):([^/]+)/([^?]+) ]]; then
    DB_HOST="${BASH_REMATCH[2]}"
    DB_PORT="${BASH_REMATCH[3]}"
    JDBC_DB_NAME="${BASH_REMATCH[4]}"
else
    echo "Failed to parse JDBC URL: $DB_URL"
    exit 1
fi

# Mask password for security
echo "::add-mask::$ADMIN_PASS"

echo "Connection: $DB_HOST:$DB_PORT/$JDBC_DB_NAME"
echo ""

# Execute action
case "$ACTION" in
    sync-passwords)
        echo "=== Syncing All User Passwords from AWS Secrets Manager ==="
        echo ""

        # Check if there are any users to manage
        if [ -z "$USER_SECRETS" ] || [ "$USER_SECRETS" = "{}" ] || [ "$USER_SECRETS" = "null" ]; then
            echo "ℹ️  No users configured for database '$DB_NAME' in secret '$SECRET_NAME'"
            echo "   Users are managed at: .databases.$DB_NAME.users"
            exit 0
        fi

        echo "Users to sync:"
        echo "$USER_SECRETS" | jq -r 'keys[]' | sed 's/^/  - /'
        echo ""

        # Use the existing manage-users.sh script
        chmod +x ./.github/scripts/manage-users.sh
        ./.github/scripts/manage-users.sh "$DATABASE"
        ;;

    rotate-password)
        if [ -z "$USERNAME" ]; then
            echo "❌ Username is required for rotate-password action"
            exit 1
        fi

        echo "=== Rotating Password for User: $USERNAME ==="
        echo ""

        # Get password from secret
        USER_PASSWORD=$(echo "$USER_SECRETS" | jq -r --arg user "$USERNAME" '.[$user] // empty')

        if [ -z "$USER_PASSWORD" ] || [ "$USER_PASSWORD" = "null" ]; then
            echo "❌ User '$USERNAME' not found in secret '$SECRET_NAME'"
            echo ""
            echo "Available users:"
            echo "$USER_SECRETS" | jq -r 'keys[]' | sed 's/^/  - /'
            echo ""
            echo "To add this user to the secret, use:"
            echo "  .github/scripts/update-secret.sh $DB_SERVER add-user $DB_NAME $USERNAME <password>"
            exit 1
        fi

        echo "Updating password for: $USERNAME"
        echo "::add-mask::$USER_PASSWORD"

        # Update password based on database type
        case "$DB_TYPE" in
            postgresql)
                PGPASSWORD="$ADMIN_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$ADMIN_USER" -d "$JDBC_DB_NAME" -v ON_ERROR_STOP=1 <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$USERNAME') THEN
        CREATE USER $USERNAME WITH PASSWORD '$USER_PASSWORD';
        RAISE NOTICE 'Created user: $USERNAME';
    ELSE
        ALTER USER $USERNAME WITH PASSWORD '$USER_PASSWORD';
        RAISE NOTICE 'Updated password for: $USERNAME';
    END IF;
END
\$\$;
EOF
                ;;

            mysql)
                mysql -h "$DB_HOST" -P "$DB_PORT" -u "$ADMIN_USER" -p"$ADMIN_PASS" -D "$JDBC_DB_NAME" <<EOF
CREATE USER IF NOT EXISTS '${USERNAME}'@'%' IDENTIFIED BY '${USER_PASSWORD}';
ALTER USER '${USERNAME}'@'%' IDENTIFIED BY '${USER_PASSWORD}';
FLUSH PRIVILEGES;
SELECT 'Password updated for: ${USERNAME}' AS result;
EOF
                ;;

            sqlserver)
                sqlcmd -S "$DB_HOST,$DB_PORT" -U "$ADMIN_USER" -P "$ADMIN_PASS" -d "$JDBC_DB_NAME" -C <<EOF
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = '$USERNAME')
BEGIN
    CREATE LOGIN [$USERNAME] WITH PASSWORD = '$USER_PASSWORD';
    PRINT 'Created login: $USERNAME';
END
ELSE
BEGIN
    ALTER LOGIN [$USERNAME] WITH PASSWORD = '$USER_PASSWORD';
    PRINT 'Updated password for: $USERNAME';
END

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$USERNAME')
BEGIN
    CREATE USER [$USERNAME] FOR LOGIN [$USERNAME];
    PRINT 'Created user: $USERNAME';
END
GO
EOF
                ;;

            oracle)
                TEMP_SQL="/tmp/rotate-password-${USERNAME}-$$.sql"
                cat > "$TEMP_SQL" <<EOF
DECLARE
    user_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO user_exists FROM dba_users WHERE username = UPPER('${USERNAME}');

    IF user_exists = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER ${USERNAME} IDENTIFIED BY "${USER_PASSWORD}" DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP ACCOUNT UNLOCK';
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO ${USERNAME}';
        DBMS_OUTPUT.PUT_LINE('Created user: ${USERNAME}');
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER ${USERNAME} IDENTIFIED BY "${USER_PASSWORD}"';
        DBMS_OUTPUT.PUT_LINE('Updated password for: ${USERNAME}');
    END IF;
END;
/
EOF
                echo "Executing SQL for $USERNAME..."
                liquibase --url="$DB_URL" \
                      --username="$ADMIN_USER" \
                      --password="$ADMIN_PASS" \
                      --changeLogFile="$TEMP_SQL" \
                      execute-sql \
                      --sql-file="$TEMP_SQL" 2>&1 | grep -v "Liquibase Version" | grep -v "Liquibase Open Source"

                rm -f "$TEMP_SQL"
                ;;
        esac

        echo "✅ Password rotated for user: $USERNAME"
        ;;

    list-users)
        echo "=== Users Configured for Database: $DB_NAME ==="
        echo ""

        if [ -z "$USER_SECRETS" ] || [ "$USER_SECRETS" = "{}" ] || [ "$USER_SECRETS" = "null" ]; then
            echo "ℹ️  No users configured for database '$DB_NAME'"
            echo ""
            echo "To add users, update the secret at:"
            echo "  .databases.$DB_NAME.users"
            echo ""
            echo "Example:"
            echo "  .github/scripts/update-secret.sh $DB_SERVER add-user $DB_NAME app_readwrite <password>"
            exit 0
        fi

        echo "Users configured in AWS Secrets Manager:"
        echo "$USER_SECRETS" | jq -r 'keys[]' | while read -r user; do
            echo "  - $user"
        done

        echo ""
        echo "Secret location: $SECRET_NAME"
        echo "Path: .databases.$DB_NAME.users"
        ;;

    *)
        echo "❌ Unknown action: $ACTION"
        echo "Valid actions: sync-passwords, rotate-password, list-users"
        exit 1
        ;;
esac

echo ""
echo "✅ User management completed for $DB_NAME"
