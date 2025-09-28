#!/bin/bash
set -e

DATABASE_NAME=$1
SECRET_NAME=${2:-"liquibase-databases"}

if [ -z "$DATABASE_NAME" ]; then
    echo "❌ Usage: $0 <database_name> [secret_name]"
    exit 1
fi

echo "🐘 Creating PostgreSQL database: $DATABASE_NAME"

# Get credentials from secrets
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query SecretString --output text)

# Look for system/master connection
MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["postgres-system"] // .["postgres-master"] // .["postgres-prod"]')

if [ "$MASTER_CONFIG" = "null" ]; then
    echo "❌ No PostgreSQL master/system configuration found in secrets"
    exit 1
fi

MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

# Extract host and port from JDBC URL
HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
if [ "$PORT" = "$MASTER_URL" ]; then PORT=5432; fi

echo "🔗 Connecting to PostgreSQL server: $HOST:$PORT"

# Create database using psql
PGPASSWORD="$MASTER_PASS" psql \
    -h "$HOST" \
    -p "$PORT" \
    -U "$MASTER_USER" \
    -d postgres \
    -c "CREATE DATABASE $DATABASE_NAME;" \
    -c "COMMENT ON DATABASE $DATABASE_NAME IS 'Created by Liquibase pipeline on $(date)';"

echo "✅ Database $DATABASE_NAME created successfully"

# Update secrets manager with new database config
NEW_URL="jdbc:postgresql://$HOST:$PORT/$DATABASE_NAME"
NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
    --arg name "postgres-$DATABASE_NAME" \
    --arg url "$NEW_URL" \
    --arg user "$MASTER_USER" \
    --arg pass "$MASTER_PASS" \
    '. + {($name): {type: "postgresql", url: $url, username: $user, password: $pass}}')

aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --secret-string "$NEW_CONFIG"

echo "✅ Secrets Manager updated: postgres-$DATABASE_NAME"
echo "📝 Database URL: $NEW_URL"