#!/bin/bash
set -e

# Script to process user changesets with password substitution during deployment
# This integrates with the existing run-liquibase.sh script

DATABASE=$1
SECRET_NAME=${2:-"liquibase-users"}

if [ -z "$DATABASE" ]; then
    echo "❌ Usage: $0 <database> [secret_name]"
    exit 1
fi

echo "🔐 Processing user changesets for $DATABASE..."

# Find all SQL files in the users directory for this database
USERS_DIR="db/changelog/database-1/users"
if [ ! -d "$USERS_DIR" ]; then
    echo "ℹ️ No users directory found at $USERS_DIR, skipping user changeset processing"
    exit 0
fi

USER_FILES=$(find "$USERS_DIR" -name "*.sql" -type f | sort)

if [ -z "$USER_FILES" ]; then
    echo "ℹ️ No user changeset files found in $USERS_DIR"
    exit 0
fi

echo "📋 Found user changeset files:"
for file in $USER_FILES; do
    echo "   - $file"
done

# Create a temporary directory for processed files
TEMP_DIR="/tmp/liquibase-users-$$"
mkdir -p "$TEMP_DIR"

# Process each user file
for USER_FILE in $USER_FILES; do
    BASENAME=$(basename "$USER_FILE")
    TEMP_FILE="$TEMP_DIR/$BASENAME"

    echo "🔧 Processing $BASENAME..."

    # Copy original file
    cp "$USER_FILE" "$TEMP_FILE"

    # Find password placeholders
    PLACEHOLDERS=$(grep -o '{{PASSWORD:[^}]*}}' "$USER_FILE" | sort | uniq || true)

    if [ -n "$PLACEHOLDERS" ]; then
        echo "   🔑 Found password placeholders, retrieving from AWS..."

        for PLACEHOLDER in $PLACEHOLDERS; do
            # Extract username from {{PASSWORD:username}}
            USERNAME=$(echo "$PLACEHOLDER" | sed 's/{{PASSWORD:\([^}]*\)}}/\1/')

            echo "      Retrieving password for: $USERNAME"

            # Get password from secrets manager
            PASSWORD=$(./.github/scripts/get-user-password.sh "$SECRET_NAME" "$USERNAME")

            if [ $? -ne 0 ] || [ -z "$PASSWORD" ]; then
                echo "❌ Failed to retrieve password for user: $USERNAME"
                rm -rf "$TEMP_DIR"
                exit 1
            fi

            # Mask password in logs
            echo "::add-mask::$PASSWORD"

            # Replace placeholder with actual password
            # Use a more robust replacement that handles special characters
            python3 -c "
import sys
import re
content = open('$TEMP_FILE').read()
content = content.replace('$PLACEHOLDER', '$PASSWORD')
open('$TEMP_FILE', 'w').write(content)
"

            echo "      ✅ Password substituted for: $USERNAME"
        done
    else
        echo "   ℹ️ No password placeholders found"
    fi
done

echo "🚀 Executing user changesets with Liquibase..."

# Execute each processed file
for USER_FILE in $USER_FILES; do
    BASENAME=$(basename "$USER_FILE")
    TEMP_FILE="$TEMP_DIR/$BASENAME"

    echo "📋 Executing $BASENAME..."

    # Run with Liquibase
    if ./liquibase --defaults-file="liquibase-$DATABASE.properties" \
        update \
        --changelog-file="$TEMP_FILE"; then
        echo "   ✅ Successfully executed $BASENAME"
    else
        echo "   ❌ Failed to execute $BASENAME"
        # Don't exit immediately, try other files
    fi
done

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "✅ User changeset processing completed"