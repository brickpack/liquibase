#!/bin/bash
set -e

# Script to run user management changesets with AWS Secrets Manager integration
# Usage: ./run-user-changeset.sh <database> <sql_template> <secret_name>

DATABASE=$1
SQL_TEMPLATE=$2
SECRET_NAME=${3:-"liquibase-users"}

if [ -z "$DATABASE" ] || [ -z "$SQL_TEMPLATE" ]; then
    echo "❌ Usage: $0 <database> <sql_template> [secret_name]"
    echo "Example: $0 oracle-finance create-app-user.sql liquibase-users"
    exit 1
fi

if [ ! -f "$SQL_TEMPLATE" ]; then
    echo "❌ SQL template file not found: $SQL_TEMPLATE"
    exit 1
fi

echo "🔧 Processing user changeset: $SQL_TEMPLATE for database: $DATABASE"

# Create a temporary file for the processed SQL
TEMP_SQL="/tmp/processed-users-$(basename $SQL_TEMPLATE)-$$"
cp "$SQL_TEMPLATE" "$TEMP_SQL"

# Find all password placeholders in the format {{PASSWORD:username}}
PLACEHOLDERS=$(grep -o '{{PASSWORD:[^}]*}}' "$SQL_TEMPLATE" | sort | uniq || true)

if [ -n "$PLACEHOLDERS" ]; then
    echo "🔐 Found password placeholders, retrieving from AWS Secrets Manager..."

    for PLACEHOLDER in $PLACEHOLDERS; do
        # Extract username from {{PASSWORD:username}}
        USERNAME=$(echo "$PLACEHOLDER" | sed 's/{{PASSWORD:\([^}]*\)}}/\1/')

        echo "   🔑 Retrieving password for user: $USERNAME"

        # Get password from secrets manager
        PASSWORD=$(./github/scripts/get-user-password.sh "$SECRET_NAME" "$USERNAME")

        if [ $? -ne 0 ] || [ -z "$PASSWORD" ]; then
            echo "❌ Failed to retrieve password for user: $USERNAME"
            rm -f "$TEMP_SQL"
            exit 1
        fi

        # Replace placeholder with actual password (escape special characters for sed)
        ESCAPED_PASSWORD=$(printf '%s\n' "$PASSWORD" | sed 's/[[\.*^$()+?{|]/\\&/g')
        sed -i "s|$PLACEHOLDER|$ESCAPED_PASSWORD|g" "$TEMP_SQL"

        echo "   ✅ Password placeholder replaced for user: $USERNAME"
    done
else
    echo "ℹ️ No password placeholders found, using template as-is"
fi

# Mask any passwords in the output for security
if [ -n "$PLACEHOLDERS" ]; then
    echo "::add-mask::$PASSWORD"
fi

echo "🚀 Executing processed changeset..."

# Run the processed SQL with Liquibase
./liquibase --defaults-file="liquibase-$DATABASE.properties" \
    update-sql \
    --changelog-file="$TEMP_SQL"

# Clean up temporary file
rm -f "$TEMP_SQL"

echo "✅ User changeset completed successfully"