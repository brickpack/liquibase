#!/bin/bash
set -e

# Script to process user changesets with password substitution during deployment
# This integrates with the existing run-liquibase.sh script

DATABASE=$1
SECRET_NAME=${2:-"liquibase-users"}

if [ -z "$DATABASE" ]; then
    echo "Usage: $0 <database> [secret_name]"
    exit 1
fi

echo "Processing user changesets for $DATABASE..."

# Find all SQL files that contain user management for this database
# Look in multiple locations based on database type

USER_FILES=""

# Check for Oracle users directory
ORACLE_USERS_DIR="db/changelog/database-1/users"
if [[ "$DATABASE" == oracle-* ]] && [ -d "$ORACLE_USERS_DIR" ]; then
    ORACLE_FILES=$(find "$ORACLE_USERS_DIR" -name "*.sql" -type f | sort)
    USER_FILES="$USER_FILES $ORACLE_FILES"
fi

# Check for user management files in database-specific directories
DB_CHANGELOG_DIRS=$(find db/changelog -name "*user*" -type f | grep -E "\.(sql)$" | sort)
for file in $DB_CHANGELOG_DIRS; do
    # Check if file contains password templates
    if grep -q "{{PASSWORD:" "$file" 2>/dev/null; then
        USER_FILES="$USER_FILES $file"
    fi
done

# Remove duplicates and sort
USER_FILES=$(echo "$USER_FILES" | tr ' ' '\n' | sort | uniq | grep -v "^$" || true)

if [ -z "$USER_FILES" ]; then
    echo "No user changeset files found in $USERS_DIR"
    exit 0
fi

echo "Found user changeset files:"
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

    echo "Processing $BASENAME..."

    # Copy original file
    cp "$USER_FILE" "$TEMP_FILE"

    # Find password placeholders
    PLACEHOLDERS=$(grep -o '{{PASSWORD:[^}]*}}' "$USER_FILE" | sort | uniq || true)

    if [ -n "$PLACEHOLDERS" ]; then
        echo "   Found password placeholders, retrieving from AWS..."

        for PLACEHOLDER in $PLACEHOLDERS; do
            # Extract username from {{PASSWORD:username}}
            USERNAME=$(echo "$PLACEHOLDER" | sed 's/{{PASSWORD:\([^}]*\)}}/\1/')

            echo "      Retrieving password for: $USERNAME"

            # Get password from secrets manager
            PASSWORD=$(./.github/scripts/get-user-password.sh "$SECRET_NAME" "$USERNAME")

            if [ $? -ne 0 ] || [ -z "$PASSWORD" ]; then
                echo "Failed to retrieve password for user: $USERNAME"
                rm -rf "$TEMP_DIR"
                exit 1
            fi

            # Mask password in logs
            echo "::add-mask::$PASSWORD"

            # Replace placeholder with actual password
            # Use sed with proper escaping to handle special characters
            # Escape special characters in password for sed
            ESCAPED_PASSWORD=$(printf '%s\n' "$PASSWORD" | sed -e 's/[\/&]/\\&/g')
            ESCAPED_PLACEHOLDER=$(printf '%s\n' "$PLACEHOLDER" | sed -e 's/[\/&]/\\&/g')

            sed -i.bak "s/${ESCAPED_PLACEHOLDER}/${ESCAPED_PASSWORD}/g" "$TEMP_FILE"
            rm -f "${TEMP_FILE}.bak"

            echo "      Password substituted for: $USERNAME"

            # Verify substitution worked
            if grep -q "$PLACEHOLDER" "$TEMP_FILE"; then
                echo "      ⚠️  WARNING: Placeholder still present after substitution!"
                echo "      This may indicate special characters in password need additional escaping"
            fi
        done
    else
        echo "   No password placeholders found"
    fi
done

# Instead of executing individual files, we need to replace the original files
# so the main changelog execution will use the processed versions

echo "Updating original files with processed versions..."

for USER_FILE in $USER_FILES; do
    BASENAME=$(basename "$USER_FILE")
    TEMP_FILE="$TEMP_DIR/$BASENAME"

    if [ -f "$TEMP_FILE" ]; then
        echo "   Updating $USER_FILE with processed passwords"
        # Back up original and replace with processed version
        cp "$USER_FILE" "$USER_FILE.backup"
        cp "$TEMP_FILE" "$USER_FILE"
    fi
done

echo "User changeset processing completed - files updated with real passwords"
echo "Note: Original files backed up with .backup extension"

# Note: Don't clean up temp dir yet, keep it for debugging if needed