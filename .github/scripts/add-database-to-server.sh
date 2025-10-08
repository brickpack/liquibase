#!/bin/bash
set -e

# Script to add a database to an existing server
# Usage: add-database-to-server.sh <db-type> <server-name> <database-name> [region]

if [ $# -lt 3 ]; then
    echo "Usage: $0 <db-type> <server-name> <database-name> [region]"
    echo ""
    echo "Examples:"
    echo "  $0 postgres prod myapp"
    echo "  $0 mysql staging analytics us-east-1"
    echo "  $0 sqlserver analytics reporting"
    echo ""
    echo "Database types: postgres, mysql, sqlserver, oracle"
    exit 1
fi

DB_TYPE="$1"
SERVER_NAME="$2"
DATABASE_NAME="$3"
REGION="${4:-${AWS_REGION:-us-west-2}}"
SECRET_NAME="liquibase-${DB_TYPE}-${SERVER_NAME}"

echo "=== Add Database to Server ==="
echo "Database Type: $DB_TYPE"
echo "Server Name: $SERVER_NAME"
echo "Database Name: $DATABASE_NAME"
echo "Secret: $SECRET_NAME"
echo "Region: $REGION"
echo ""

# Validate database type
case "$DB_TYPE" in
    postgres|mysql|sqlserver|oracle) ;;
    *) echo "❌ Invalid database type: $DB_TYPE"; exit 1 ;;
esac

# Check if secret exists
if ! aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" 2>/dev/null; then
    echo "❌ Secret '$SECRET_NAME' does not exist!"
    echo ""
    echo "Create it first with:"
    echo "  .github/scripts/setup-multiple-servers.sh"
    echo "  or"
    echo "  .github/scripts/create-secret-${DB_TYPE}.sh"
    exit 1
fi

# Get current secret
secret_json=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$REGION" --query SecretString --output text)

# Check if database already exists
if echo "$secret_json" | jq -e ".databases.$DATABASE_NAME" >/dev/null 2>&1; then
    echo "⚠️  Database '$DATABASE_NAME' already exists in this server"
    read -p "Update existing database? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Get master connection details
master_url=$(echo "$secret_json" | jq -r '.master.url // "TBD"')
master_username=$(echo "$secret_json" | jq -r '.master.username // "TBD"')
master_password=$(echo "$secret_json" | jq -r '.master.password // "TBD"')

if [ "$master_url" = "TBD" ]; then
    echo "❌ Master connection not configured for this server"
    echo ""
    echo "Configure it first with:"
    echo "  .github/scripts/configure-server.sh $DB_TYPE $SERVER_NAME"
    exit 1
fi

echo "=== Database Connection Details ==="
echo "Using master connection from server configuration"
echo "Master URL: $master_url"
echo "Master Username: $master_username"
echo ""

# Get database-specific connection details
echo "Enter database-specific connection details:"
read -p "Admin username for $DATABASE_NAME [$master_username]: " db_username
db_username=${db_username:-$master_username}

read -sp "Admin password for $DATABASE_NAME [use master password]: " db_password
echo ""
if [ -z "$db_password" ]; then
    db_password="$master_password"
fi

# Construct database URL based on type
case "$DB_TYPE" in
    "postgres")
        # Extract host and port from master URL
        if [[ $master_url =~ jdbc:postgresql://([^:]+):([0-9]+)/postgres ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            db_url="jdbc:postgresql://${host}:${port}/${DATABASE_NAME}"
        else
            echo "❌ Could not parse master URL"
            exit 1
        fi
        ;;
    "mysql")
        # Extract host and port from master URL
        if [[ $master_url =~ jdbc:mysql://([^:]+):([0-9]+)/mysql ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            db_url="jdbc:mysql://${host}:${port}/${DATABASE_NAME}?useSSL=true&serverTimezone=UTC"
        else
            echo "❌ Could not parse master URL"
            exit 1
        fi
        ;;
    "sqlserver")
        # Extract host and port from master URL
        if [[ $master_url =~ jdbc:sqlserver://([^:]+):([0-9]+);databaseName=master ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            db_url="jdbc:sqlserver://${host}:${port};databaseName=${DATABASE_NAME};encrypt=true;trustServerCertificate=true"
        else
            echo "❌ Could not parse master URL"
            exit 1
        fi
        ;;
    "oracle")
        # Extract host, port, and service from master URL
        if [[ $master_url =~ jdbc:oracle:thin:@([^:]+):([0-9]+):(.+) ]]; then
            host="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
            service="${BASH_REMATCH[3]}"
            db_url="jdbc:oracle:thin:@${host}:${port}:${service}"
        else
            echo "❌ Could not parse master URL"
            exit 1
        fi
        ;;
esac

echo ""
echo "=== Application Users ==="
echo "Add application users for $DATABASE_NAME"
echo "Leave username empty when done"
echo ""

users_json="{}"
while true; do
    read -p "  User name (or press Enter to finish): " user_name
    if [ -z "$user_name" ]; then
        break
    fi
    
    read -sp "  Password for $user_name: " user_password
    echo ""
    
    # Add user to users object
    users_json=$(echo "$users_json" | jq --arg name "$user_name" --arg pass "$user_password" '. + {($name): $pass}')
    
    echo "  ✅ Added user: $user_name"
done

echo ""
echo "=== Summary ==="
echo "Database: $DATABASE_NAME"
echo "URL: $db_url"
echo "Username: $db_username"
echo "Users: $(echo "$users_json" | jq 'keys | length')"
echo ""

read -p "Add this database to server '$SERVER_NAME'? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Update secret with new database
secret_json=$(echo "$secret_json" | jq \
    --arg db "$DATABASE_NAME" \
    --arg url "$db_url" \
    --arg user "$db_username" \
    --arg pass "$db_password" \
    --argjson users "$users_json" \
    '.databases[$db] = {
        connection: {
            url: $url,
            username: $user,
            password: $pass
        },
        users: $users
    }')

aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --secret-string "$secret_json" \
    --region "$REGION" >/dev/null

echo ""
echo "✅ Database '$DATABASE_NAME' added to server '$SERVER_NAME' successfully!"
echo ""
echo "You can now use this with database identifier: ${DB_TYPE}-${DATABASE_NAME}"
echo "Example: ${DB_TYPE}-${DATABASE_NAME}"
echo ""
echo "Next steps:"
echo "1. Create changelog file: changelog-${DB_TYPE}-${DATABASE_NAME}.xml"
echo "2. Test with workflow dispatch in test mode"
echo "3. Deploy to this database"




