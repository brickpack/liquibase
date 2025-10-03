#!/bin/bash
set -e

# Script to create or update the liquibase-mysql-prod secret
# This secret contains master connection and all MySQL databases

SECRET_NAME="liquibase-mysql-prod"
echo "=== AWS Region Selection ==="
echo "Current AWS_REGION environment variable: ${AWS_REGION:-not set}"
echo ""
read -p "Enter AWS region [us-west-2]: " INPUT_REGION
REGION="${INPUT_REGION:-${AWS_REGION:-us-east-1}}"

echo "Creating/updating secret: $SECRET_NAME"
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
echo "=== MySQL Master Connection ==="
echo "This is the superuser connection used to create databases and users."
echo ""

read -p "Master MySQL host (e.g., my-mysql.aws.com): " MASTER_HOST
read -p "Master MySQL port [3306]: " MASTER_PORT
MASTER_PORT=${MASTER_PORT:-3306}
read -p "Master MySQL username [root]: " MASTER_USER
MASTER_USER=${MASTER_USER:-root}
read -sp "Master MySQL password: " MASTER_PASS
echo ""

MASTER_URL="jdbc:mysql://${MASTER_HOST}:${MASTER_PORT}/mysql?useSSL=true&serverTimezone=UTC"

echo ""
echo "Master connection configured:"
echo "  URL: $MASTER_URL"
echo "  Username: $MASTER_USER"
echo ""

# Initialize JSON structure
SECRET_JSON=$(cat <<EOF
{
  "master": {
    "type": "mysql",
    "url": "$MASTER_URL",
    "username": "$MASTER_USER",
    "password": "$MASTER_PASS"
  },
  "databases": {}
}
EOF
)

echo ""
echo "=== MySQL Databases ==="
echo "Add databases that exist on this MySQL server."
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

    DB_URL="jdbc:mysql://${MASTER_HOST}:${MASTER_PORT}/${DB_NAME}?useSSL=true&serverTimezone=UTC"

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
        --description "Liquibase MySQL server configuration with master connection and all databases" \
        --secret-string "$SECRET_JSON" \
        --region "$REGION"
fi

echo ""
echo "✅ Secret '$SECRET_NAME' created/updated successfully!"
echo ""
echo "You can now use this with database identifier: mysql-{dbname}"
echo "Example: mysql-thedb"
