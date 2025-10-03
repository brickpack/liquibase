#!/bin/bash
set -e

# Script to update existing per-server secrets via command line
# Usage examples:
#   Add database:    ./update-secret.sh postgres add-database mydb "jdbc:postgresql://host:5432/mydb" admin adminpass
#   Add user:        ./update-secret.sh postgres add-user mydb app_readwrite rwpassword
#   Remove user:     ./update-secret.sh postgres remove-user mydb app_readwrite
#   Remove database: ./update-secret.sh postgres remove-database mydb
#   Show secret:     ./update-secret.sh postgres show

echo "=== AWS Region Selection ==="
echo "Current AWS_REGION environment variable: ${AWS_REGION:-not set}"
echo ""
read -p "Enter AWS region [us-west-2]: " INPUT_REGION
REGION="${INPUT_REGION:-${AWS_REGION:-us-west-2}}"

# Parse arguments
SERVER_TYPE=$1
ACTION=$2

if [ -z "$SERVER_TYPE" ] || [ -z "$ACTION" ]; then
    echo "Usage: $0 <server-type> <action> [args...]"
    echo ""
    echo "Server types: postgres, mysql, sqlserver, oracle"
    echo ""
    echo "Actions:"
    echo "  show"
    echo "  add-database <dbname> <url> <username> <password>"
    echo "  remove-database <dbname>"
    echo "  add-user <dbname> <username> <password>"
    echo "  remove-user <dbname> <username>"
    echo ""
    echo "Examples:"
    echo "  $0 postgres show"
    echo "  $0 postgres add-database thedb 'jdbc:postgresql://host:5432/thedb' admin adminpass"
    echo "  $0 postgres add-user thedb app_readwrite rwpass123"
    echo "  $0 postgres remove-user thedb old_user"
    echo "  $0 postgres remove-database olddb"
    exit 1
fi

# Determine secret name
case "$SERVER_TYPE" in
    postgres|postgresql)
        SECRET_NAME="liquibase-postgres-prod"
        ;;
    mysql)
        SECRET_NAME="liquibase-mysql-prod"
        ;;
    sqlserver|mssql)
        SECRET_NAME="liquibase-sqlserver-prod"
        ;;
    oracle|ora)
        SECRET_NAME="liquibase-oracle-prod"
        ;;
    *)
        echo "❌ Unknown server type: $SERVER_TYPE"
        echo "Valid types: postgres, mysql, sqlserver, oracle"
        exit 1
        ;;
esac

echo "Working with secret: $SECRET_NAME"

# Get current secret
echo "Fetching secret from AWS..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString \
    --output text)

if [ -z "$SECRET_JSON" ]; then
    echo "❌ Failed to fetch secret: $SECRET_NAME"
    exit 1
fi

# Perform action
case "$ACTION" in
    show)
        echo ""
        echo "=== Secret: $SECRET_NAME ==="
        echo "$SECRET_JSON" | jq '{
            master: .master | {type, url, username},
            databases: .databases | to_entries | map({
                name: .key,
                url: .value.connection.url,
                username: .value.connection.username,
                users: .value.users | keys
            })
        }'
        ;;

    add-database)
        DB_NAME=$3
        DB_URL=$4
        DB_USER=$5
        DB_PASS=$6

        if [ -z "$DB_NAME" ] || [ -z "$DB_URL" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
            echo "❌ Usage: $0 $SERVER_TYPE add-database <dbname> <url> <username> <password>"
            exit 1
        fi

        echo "Adding database: $DB_NAME"

        NEW_SECRET=$(echo "$SECRET_JSON" | jq \
            --arg db "$DB_NAME" \
            --arg url "$DB_URL" \
            --arg user "$DB_USER" \
            --arg pass "$DB_PASS" \
            '.databases[$db] = {
                connection: {
                    url: $url,
                    username: $user,
                    password: $pass
                },
                users: {}
            }')

        echo "Updating secret in AWS..."
        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_SECRET" \
            --region "$REGION" \
            --output text > /dev/null

        echo "✅ Database '$DB_NAME' added to $SECRET_NAME"
        ;;

    remove-database)
        DB_NAME=$3

        if [ -z "$DB_NAME" ]; then
            echo "❌ Usage: $0 $SERVER_TYPE remove-database <dbname>"
            exit 1
        fi

        # Check if database exists
        if ! echo "$SECRET_JSON" | jq -e --arg db "$DB_NAME" '.databases[$db]' > /dev/null; then
            echo "❌ Database '$DB_NAME' not found in secret"
            exit 1
        fi

        echo "Removing database: $DB_NAME"

        NEW_SECRET=$(echo "$SECRET_JSON" | jq --arg db "$DB_NAME" 'del(.databases[$db])')

        echo "Updating secret in AWS..."
        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_SECRET" \
            --region "$REGION" \
            --output text > /dev/null

        echo "✅ Database '$DB_NAME' removed from $SECRET_NAME"
        ;;

    add-user)
        DB_NAME=$3
        USER_NAME=$4
        USER_PASS=$5

        if [ -z "$DB_NAME" ] || [ -z "$USER_NAME" ] || [ -z "$USER_PASS" ]; then
            echo "❌ Usage: $0 $SERVER_TYPE add-user <dbname> <username> <password>"
            exit 1
        fi

        # Check if database exists
        if ! echo "$SECRET_JSON" | jq -e --arg db "$DB_NAME" '.databases[$db]' > /dev/null; then
            echo "❌ Database '$DB_NAME' not found in secret"
            echo "Available databases:"
            echo "$SECRET_JSON" | jq -r '.databases | keys[]'
            exit 1
        fi

        echo "Adding user '$USER_NAME' to database '$DB_NAME'"

        NEW_SECRET=$(echo "$SECRET_JSON" | jq \
            --arg db "$DB_NAME" \
            --arg user "$USER_NAME" \
            --arg pass "$USER_PASS" \
            '.databases[$db].users[$user] = $pass')

        echo "Updating secret in AWS..."
        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_SECRET" \
            --region "$REGION" \
            --output text > /dev/null

        echo "✅ User '$USER_NAME' added to database '$DB_NAME'"
        ;;

    remove-user)
        DB_NAME=$3
        USER_NAME=$4

        if [ -z "$DB_NAME" ] || [ -z "$USER_NAME" ]; then
            echo "❌ Usage: $0 $SERVER_TYPE remove-user <dbname> <username>"
            exit 1
        fi

        # Check if user exists
        if ! echo "$SECRET_JSON" | jq -e --arg db "$DB_NAME" --arg user "$USER_NAME" '.databases[$db].users[$user]' > /dev/null; then
            echo "❌ User '$USER_NAME' not found in database '$DB_NAME'"
            exit 1
        fi

        echo "Removing user '$USER_NAME' from database '$DB_NAME'"

        NEW_SECRET=$(echo "$SECRET_JSON" | jq \
            --arg db "$DB_NAME" \
            --arg user "$USER_NAME" \
            'del(.databases[$db].users[$user])')

        echo "Updating secret in AWS..."
        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_SECRET" \
            --region "$REGION" \
            --output text > /dev/null

        echo "✅ User '$USER_NAME' removed from database '$DB_NAME'"
        ;;

    *)
        echo "❌ Unknown action: $ACTION"
        echo "Valid actions: show, add-database, remove-database, add-user, remove-user"
        exit 1
        ;;
esac
