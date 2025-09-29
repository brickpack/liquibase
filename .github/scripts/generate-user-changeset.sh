#!/bin/bash
set -e

# Script to generate user management changesets from templates
# Usage: ./generate-user-changeset.sh <database_type> <config_file> <output_file>

DATABASE_TYPE=$1
CONFIG_FILE=$2
OUTPUT_FILE=$3

if [ -z "$DATABASE_TYPE" ] || [ -z "$CONFIG_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "❌ Usage: $0 <database_type> <config_file> <output_file>"
    echo "Database types: postgresql, mysql, sqlserver, oracle"
    echo "Example: $0 postgresql app-users.yaml db/changelog/oracle-finance/users/001-app-users.sql"
    exit 1
fi

TEMPLATE_FILE="db/templates/users/${DATABASE_TYPE}-user-template.sql"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "❌ Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "🔧 Generating user changeset for $DATABASE_TYPE using $CONFIG_FILE"

# Check if we have yq for YAML parsing
if ! command -v yq >/dev/null 2>&1; then
    echo "❌ yq is required for YAML processing. Please install yq."
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Start with the template
cp "$TEMPLATE_FILE" "$OUTPUT_FILE"

echo "📝 Processing configuration parameters..."

# Read configuration and replace placeholders
# This is a simplified processor - in production you might want more sophisticated YAML processing

# Replace basic parameters
USERNAME=$(yq eval '.username' "$CONFIG_FILE")
ROLE_DESCRIPTION=$(yq eval '.role_description // "Application user"' "$CONFIG_FILE")
DATABASE_NAME=$(yq eval '.database_name' "$CONFIG_FILE")

if [ "$USERNAME" = "null" ] || [ -z "$USERNAME" ]; then
    echo "❌ username is required in configuration file"
    exit 1
fi

# Replace common placeholders
sed -i "s/{{USERNAME}}/$USERNAME/g" "$OUTPUT_FILE"
sed -i "s/{{ROLE_DESCRIPTION}}/$ROLE_DESCRIPTION/g" "$OUTPUT_FILE"
sed -i "s/{{DATABASE_NAME}}/$DATABASE_NAME/g" "$OUTPUT_FILE"
sed -i "s/{{CREATION_DATE}}/$(date -u +%Y-%m-%d)/g" "$OUTPUT_FILE"

# Database-specific replacements
case "$DATABASE_TYPE" in
    "postgresql")
        SCHEMA_NAME=$(yq eval '.schema_name // "public"' "$CONFIG_FILE")
        TABLE_PRIVILEGES=$(yq eval '.table_privileges // "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{USERNAME}}\";"' "$CONFIG_FILE")
        SEQUENCE_PRIVILEGES=$(yq eval '.sequence_privileges // "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{USERNAME}}\";"' "$CONFIG_FILE")
        ADDITIONAL_OPTIONS=$(yq eval '.additional_options // ""' "$CONFIG_FILE")

        sed -i "s/{{SCHEMA_NAME}}/$SCHEMA_NAME/g" "$OUTPUT_FILE"
        sed -i "s/{{TABLE_PRIVILEGES}}/$TABLE_PRIVILEGES/g" "$OUTPUT_FILE"
        sed -i "s/{{SEQUENCE_PRIVILEGES}}/$SEQUENCE_PRIVILEGES/g" "$OUTPUT_FILE"
        sed -i "s/{{ADDITIONAL_OPTIONS}}/$ADDITIONAL_OPTIONS/g" "$OUTPUT_FILE"
        ;;

    "mysql")
        HOST_PATTERN=$(yq eval '.host_pattern // "%"' "$CONFIG_FILE")
        DATABASE_PRIVILEGES=$(yq eval '.database_privileges // "GRANT SELECT, INSERT, UPDATE, DELETE ON {{DATABASE_NAME}}.* TO \"{{USERNAME}}\"@\"{{HOST_PATTERN}}\";"' "$CONFIG_FILE")

        sed -i "s/{{HOST_PATTERN}}/$HOST_PATTERN/g" "$OUTPUT_FILE"
        sed -i "s/{{DATABASE_PRIVILEGES}}/$DATABASE_PRIVILEGES/g" "$OUTPUT_FILE"
        ;;

    "sqlserver")
        DEFAULT_SCHEMA=$(yq eval '.default_schema // "dbo"' "$CONFIG_FILE")
        ROLE_MEMBERSHIPS=$(yq eval '.role_memberships // "ALTER ROLE db_datareader ADD MEMBER [{{USERNAME}}];\nALTER ROLE db_datawriter ADD MEMBER [{{USERNAME}}];"' "$CONFIG_FILE")
        SPECIFIC_PERMISSIONS=$(yq eval '.specific_permissions // ""' "$CONFIG_FILE")

        sed -i "s/{{DEFAULT_SCHEMA}}/$DEFAULT_SCHEMA/g" "$OUTPUT_FILE"
        sed -i "s/{{ROLE_MEMBERSHIPS}}/$ROLE_MEMBERSHIPS/g" "$OUTPUT_FILE"
        sed -i "s/{{SPECIFIC_PERMISSIONS}}/$SPECIFIC_PERMISSIONS/g" "$OUTPUT_FILE"
        ;;

    "oracle")
        DEFAULT_TABLESPACE=$(yq eval '.default_tablespace // "USERS"' "$CONFIG_FILE")
        TEMP_TABLESPACE=$(yq eval '.temp_tablespace // "TEMP"' "$CONFIG_FILE")
        TABLESPACE_QUOTA=$(yq eval '.tablespace_quota // "100M"' "$CONFIG_FILE")
        USER_PROFILE=$(yq eval '.user_profile // "DEFAULT"' "$CONFIG_FILE")
        SYSTEM_PRIVILEGES=$(yq eval '.system_privileges // "GRANT CREATE SESSION TO {{USERNAME}};"' "$CONFIG_FILE")
        OBJECT_PRIVILEGES=$(yq eval '.object_privileges // ""' "$CONFIG_FILE")
        ROLE_GRANTS=$(yq eval '.role_grants // ""' "$CONFIG_FILE")

        sed -i "s/{{DEFAULT_TABLESPACE}}/$DEFAULT_TABLESPACE/g" "$OUTPUT_FILE"
        sed -i "s/{{TEMP_TABLESPACE}}/$TEMP_TABLESPACE/g" "$OUTPUT_FILE"
        sed -i "s/{{TABLESPACE_QUOTA}}/$TABLESPACE_QUOTA/g" "$OUTPUT_FILE"
        sed -i "s/{{USER_PROFILE}}/$USER_PROFILE/g" "$OUTPUT_FILE"
        sed -i "s/{{SYSTEM_PRIVILEGES}}/$SYSTEM_PRIVILEGES/g" "$OUTPUT_FILE"
        sed -i "s/{{OBJECT_PRIVILEGES}}/$OBJECT_PRIVILEGES/g" "$OUTPUT_FILE"
        sed -i "s/{{ROLE_GRANTS}}/$ROLE_GRANTS/g" "$OUTPUT_FILE"
        ;;

    *)
        echo "❌ Unsupported database type: $DATABASE_TYPE"
        exit 1
        ;;
esac

echo "✅ User changeset generated: $OUTPUT_FILE"
echo "📋 To use this changeset:"
echo "   1. Add the user password to AWS Secrets Manager"
echo "   2. Include this changeset in your main changelog"
echo "   3. Deploy using the standard Liquibase pipeline"