#!/bin/bash
set -e

# Unified script to create or update database server secrets
# Supports: PostgreSQL, MySQL, SQL Server, Oracle
# Usage: ./create-secret.sh [postgres|mysql|sqlserver|oracle]

# Determine database type
if [ -z "$1" ]; then
    echo "=== Database Type Selection ==="
    echo "1) PostgreSQL"
    echo "2) MySQL"
    echo "3) SQL Server"
    echo "4) Oracle"
    echo ""
    read -p "Select database type (1-4): " DB_TYPE_CHOICE

    case "$DB_TYPE_CHOICE" in
        1) DB_TYPE="postgres" ;;
        2) DB_TYPE="mysql" ;;
        3) DB_TYPE="sqlserver" ;;
        4) DB_TYPE="oracle" ;;
        *) echo "❌ Invalid choice"; exit 1 ;;
    esac
else
    DB_TYPE=$1
fi

# Validate and normalize database type
case "$DB_TYPE" in
    postgres|postgresql)
        DB_TYPE="postgres"
        DB_TYPE_DISPLAY="PostgreSQL"
        DB_TYPE_JSON="postgresql"
        ;;
    mysql)
        DB_TYPE="mysql"
        DB_TYPE_DISPLAY="MySQL"
        DB_TYPE_JSON="mysql"
        ;;
    sqlserver|mssql)
        DB_TYPE="sqlserver"
        DB_TYPE_DISPLAY="SQL Server"
        DB_TYPE_JSON="sqlserver"
        ;;
    oracle|ora)
        DB_TYPE="oracle"
        DB_TYPE_DISPLAY="Oracle"
        DB_TYPE_JSON="oracle"
        ;;
    *)
        echo "❌ Invalid database type: $DB_TYPE"
        echo "Valid types: postgres, mysql, sqlserver, oracle"
        exit 1
        ;;
esac

echo ""
echo "=== $DB_TYPE_DISPLAY Server Configuration ==="
echo "Enter the server name (e.g., prod, staging, dev-west, etc.)"
echo "This will create a secret named: liquibase-${DB_TYPE}-{server-name}"
echo ""
read -p "$DB_TYPE_DISPLAY server name: " SERVER_NAME

if [ -z "$SERVER_NAME" ]; then
    echo "❌ Server name is required!"
    exit 1
fi

# Validate server name (alphanumeric and hyphens only)
if [[ ! "$SERVER_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "❌ Server name can only contain letters, numbers, and hyphens!"
    exit 1
fi

SECRET_NAME="liquibase-${DB_TYPE}-${SERVER_NAME}"

echo ""
echo "=== AWS Region Selection ==="
echo "Current AWS_REGION environment variable: ${AWS_REGION:-not set}"
echo ""
read -p "Enter AWS region [us-west-2]: " INPUT_REGION
REGION="${INPUT_REGION:-${AWS_REGION:-us-west-2}}"

echo ""
echo "Creating/updating secret: $SECRET_NAME"
echo "Server: $SERVER_NAME"
echo "Region: $REGION"
echo ""

# Check if secret already exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" 2>/dev/null; then
    echo "Secret '$SECRET_NAME' already exists. This script will UPDATE it."
    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    UPDATE_MODE=true
else
    echo "Secret '$SECRET_NAME' does not exist. This script will CREATE it."
    UPDATE_MODE=false
fi

echo ""
echo "=== $DB_TYPE_DISPLAY Master Connection ==="
echo "This is the superuser connection used to create databases and users."
echo ""

# Get connection details based on database type
case "$DB_TYPE" in
    postgres)
        read -p "Master host (e.g., my-postgres.aws.com): " MASTER_HOST
        read -p "Master port [5432]: " MASTER_PORT
        MASTER_PORT=${MASTER_PORT:-5432}
        read -p "Master username [postgres]: " MASTER_USER
        MASTER_USER=${MASTER_USER:-postgres}
        read -sp "Master password: " MASTER_PASS
        echo ""
        MASTER_URL="jdbc:postgresql://${MASTER_HOST}:${MASTER_PORT}/postgres"
        ;;

    mysql)
        read -p "Master host (e.g., my-mysql.aws.com): " MASTER_HOST
        read -p "Master port [3306]: " MASTER_PORT
        MASTER_PORT=${MASTER_PORT:-3306}
        read -p "Master username [root]: " MASTER_USER
        MASTER_USER=${MASTER_USER:-root}
        read -sp "Master password: " MASTER_PASS
        echo ""
        MASTER_URL="jdbc:mysql://${MASTER_HOST}:${MASTER_PORT}/mysql?useSSL=true&serverTimezone=UTC"
        ;;

    sqlserver)
        read -p "Master host (e.g., my-sqlserver.aws.com): " MASTER_HOST
        read -p "Master port [1433]: " MASTER_PORT
        MASTER_PORT=${MASTER_PORT:-1433}
        read -p "Master username [sa]: " MASTER_USER
        MASTER_USER=${MASTER_USER:-sa}
        read -sp "Master password: " MASTER_PASS
        echo ""
        MASTER_URL="jdbc:sqlserver://${MASTER_HOST}:${MASTER_PORT};databaseName=master;encrypt=true;trustServerCertificate=true"
        ;;

    oracle)
        read -p "Master host (e.g., my-oracle.aws.com): " MASTER_HOST
        read -p "Master port [1521]: " MASTER_PORT
        MASTER_PORT=${MASTER_PORT:-1521}
        read -p "Master username [admin]: " MASTER_USER
        MASTER_USER=${MASTER_USER:-admin}
        read -sp "Master password: " MASTER_PASS
        echo ""
        read -p "Service name [ORCL]: " SERVICE_NAME
        SERVICE_NAME=${SERVICE_NAME:-ORCL}
        MASTER_URL="jdbc:oracle:thin:@${MASTER_HOST}:${MASTER_PORT}:${SERVICE_NAME}"
        ;;
esac

echo ""
echo "Master connection configured:"
echo "  URL: $MASTER_URL"
echo "  Username: $MASTER_USER"
echo ""

# Initialize JSON structure
SECRET_JSON=$(cat <<EOF
{
  "master": {
    "type": "$DB_TYPE_JSON",
    "url": "$MASTER_URL",
    "username": "$MASTER_USER",
    "password": "$MASTER_PASS"
  },
  "databases": {}
}
EOF
)

echo ""
echo "=== $DB_TYPE_DISPLAY Databases ==="
echo "Add databases that exist on this $DB_TYPE_DISPLAY server."
echo "Leave database name empty when done."
echo ""

while true; do
    read -p "Database name (or press Enter to finish): " DB_NAME
    if [ -z "$DB_NAME" ]; then
        break
    fi

    echo ""
    echo "Configuring database: $DB_NAME"

    read -p "Admin username for $DB_NAME [$MASTER_USER]: " DB_USER
    DB_USER=${DB_USER:-$MASTER_USER}

    read -sp "Admin password for $DB_NAME [use master password]: " DB_PASS
    echo ""
    if [ -z "$DB_PASS" ]; then
        DB_PASS="$MASTER_PASS"
    fi

    # Build database URL based on type
    case "$DB_TYPE" in
        postgres)
            DB_URL="jdbc:postgresql://${MASTER_HOST}:${MASTER_PORT}/${DB_NAME}"
            ;;
        mysql)
            DB_URL="jdbc:mysql://${MASTER_HOST}:${MASTER_PORT}/${DB_NAME}?useSSL=true&serverTimezone=UTC"
            ;;
        sqlserver)
            DB_URL="jdbc:sqlserver://${MASTER_HOST}:${MASTER_PORT};databaseName=${DB_NAME};encrypt=true;trustServerCertificate=true"
            ;;
        oracle)
            DB_URL="jdbc:oracle:thin:@${MASTER_HOST}:${MASTER_PORT}:${SERVICE_NAME}"
            ;;
    esac

    echo ""
    echo "=== Application Users for $DB_NAME ==="
    echo "Add application users (like app_readwrite, app_readonly)."
    echo "Leave username empty when done."
    echo ""

    # Start users object
    USERS_JSON="{}"

    while true; do
        read -p "  User name (or press Enter to finish): " USER_NAME
        if [ -z "$USER_NAME" ]; then
            break
        fi

        read -sp "  Password for $USER_NAME: " USER_PASS
        echo ""

        # Add user to users object
        USERS_JSON=$(echo "$USERS_JSON" | jq --arg name "$USER_NAME" --arg pass "$USER_PASS" '. + {($name): $pass}')

        echo "  ✓ Added user: $USER_NAME"
    done

    # Add database to secret
    SECRET_JSON=$(echo "$SECRET_JSON" | jq \
        --arg db "$DB_NAME" \
        --arg url "$DB_URL" \
        --arg user "$DB_USER" \
        --arg pass "$DB_PASS" \
        --argjson users "$USERS_JSON" \
        '.databases[$db] = {
            connection: {
                url: $url,
                username: $user,
                password: $pass
            },
            users: $users
        }')

    echo ""
    echo "✓ Database '$DB_NAME' configured"
    echo ""
done

echo ""
echo "=== Secret Summary ==="
echo "$SECRET_JSON" | jq '{
    master: .master | {type, url, username},
    databases: .databases | to_entries | map({
        name: .key,
        url: .value.connection.url,
        username: .value.connection.username,
        users: .value.users | keys
    })
}'

echo ""
read -p "Create/update this secret? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Create or update the secret
if [ "$UPDATE_MODE" = true ]; then
    echo "Updating secret: $SECRET_NAME"
    aws secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_JSON" \
        --region "$REGION"
else
    echo "Creating secret: $SECRET_NAME"
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Liquibase $DB_TYPE_DISPLAY server configuration with master connection and all databases" \
        --secret-string "$SECRET_JSON" \
        --region "$REGION"
fi

echo ""
echo "✅ Secret '$SECRET_NAME' created/updated successfully!"
echo ""
echo "You can now use this with database identifier: ${DB_TYPE}-{dbname}"
echo "Example: ${DB_TYPE}-thedb"
echo ""
echo "Server: $SERVER_NAME"
echo "Secret: $SECRET_NAME"
echo "Databases configured: $(echo "$SECRET_JSON" | jq '.databases | keys | length')"
