#!/bin/bash
set -e

# Script to create or update the liquibase-oracle-prod secret
# This secret contains master connection and all Oracle databases

SECRET_NAME="liquibase-oracle-prod"
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
echo "=== Oracle Master Connection ==="
echo "This is the superuser connection used to create databases and users."
echo ""

read -p "Master Oracle host (e.g., my-oracle.aws.com): " MASTER_HOST
read -p "Master Oracle port [1521]: " MASTER_PORT
MASTER_PORT=${MASTER_PORT:-1521}

echo "Oracle connection format:"
echo "  1) Service Name (recommended for modern Oracle)"
echo "  2) SID (legacy format)"
read -p "Select format (1 or 2) [1]: " ORACLE_FORMAT
ORACLE_FORMAT=${ORACLE_FORMAT:-1}

if [ "$ORACLE_FORMAT" = "1" ]; then
    read -p "Oracle service name [ORCL]: " ORACLE_SERVICE
    ORACLE_SERVICE=${ORACLE_SERVICE:-ORCL}
    MASTER_URL="jdbc:oracle:thin:@//${MASTER_HOST}:${MASTER_PORT}/${ORACLE_SERVICE}"
else
    read -p "Oracle SID [ORCL]: " ORACLE_SID
    ORACLE_SID=${ORACLE_SID:-ORCL}
    MASTER_URL="jdbc:oracle:thin:@${MASTER_HOST}:${MASTER_PORT}:${ORACLE_SID}"
fi

read -p "Master Oracle username [system]: " MASTER_USER
MASTER_USER=${MASTER_USER:-system}
read -sp "Master Oracle password: " MASTER_PASS
echo ""

echo ""
echo "Master connection configured:"
echo "  URL: $MASTER_URL"
echo "  Username: $MASTER_USER"
echo ""

# Initialize JSON structure
SECRET_JSON=$(cat <<EOF
{
  "master": {
    "type": "oracle",
    "url": "$MASTER_URL",
    "username": "$MASTER_USER",
    "password": "$MASTER_PASS"
  },
  "databases": {}
}
EOF
)

echo ""
echo "=== Oracle Schemas/Pluggable Databases ==="
echo "Add schemas or pluggable databases on this Oracle instance."
echo "Leave name empty when done."
echo ""

while true; do
    read -p "Schema/PDB name (or press Enter to finish): " DB_NAME
    if [ -z "$DB_NAME" ]; then
        break
    fi

    echo ""
    echo "Configuring: $DB_NAME"

    read -p "Is this a Pluggable Database (PDB)? (y/n) [n]: " IS_PDB
    IS_PDB=${IS_PDB:-n}

    if [[ "$IS_PDB" =~ ^[Yy]$ ]]; then
        # PDB format
        if [ "$ORACLE_FORMAT" = "1" ]; then
            DB_URL="jdbc:oracle:thin:@//${MASTER_HOST}:${MASTER_PORT}/${DB_NAME}"
        else
            DB_URL="jdbc:oracle:thin:@${MASTER_HOST}:${MASTER_PORT}:${DB_NAME}"
        fi
    else
        # Schema in main database - use master URL
        DB_URL="$MASTER_URL"
    fi

    read -p "Admin username for $DB_NAME [$MASTER_USER]: " DB_USER
    DB_USER=${DB_USER:-$MASTER_USER}

    read -sp "Admin password for $DB_NAME [use master password]: " DB_PASS
    echo ""
    if [ -z "$DB_PASS" ]; then
        DB_PASS="$MASTER_PASS"
    fi

    echo ""
    echo "=== Application Users for $DB_NAME ==="
    echo "Add application users/schemas."
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
    echo "✓ '$DB_NAME' configured"
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
        --description "Liquibase Oracle server configuration with master connection and all databases/schemas" \
        --secret-string "$SECRET_JSON" \
        --region "$REGION"
fi

echo ""
echo "✅ Secret '$SECRET_NAME' created/updated successfully!"
echo ""
echo "You can now use this with database identifier: oracle-{dbname}"
echo "Example: oracle-thedb"
