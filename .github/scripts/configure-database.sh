#!/bin/bash
set -e

DATABASE=$1
TEST_MODE=${2:-"false"}

if [ -z "$DATABASE" ]; then
    echo "Usage: $0 <database> [test_mode]"
    echo "Example: $0 postgres-thedb false"
    exit 1
fi

echo "Configuring database: $DATABASE"

# Parse database identifier (e.g., "prod-postgres-thedb" -> env="prod", server="postgres", dbname="thedb")
# New format: {environment}-{server-type}-{database-name}
DB_ENVIRONMENT=$(echo "$DATABASE" | cut -d'-' -f1)
DB_SERVER=$(echo "$DATABASE" | cut -d'-' -f2)
DB_NAME=$(echo "$DATABASE" | cut -d'-' -f3-)

echo "Parsed: Environment=$DB_ENVIRONMENT, Server Type=$DB_SERVER, Database Name=$DB_NAME"

if [ "$TEST_MODE" = "true" ]; then
    # Test mode - offline configuration
    cat > "liquibase-$DATABASE.properties" << EOF
changelogFile=changelog-$DATABASE.xml
url=offline:$DB_SERVER
driver=org.postgresql.Driver
logLevel=INFO
logFile=liquibase-$DATABASE.log
outputFile=liquibase-$DATABASE-output.txt
EOF
    echo "Test configuration created"
else
    # Production mode - get credentials from AWS per-server secret
    # Secret name format: liquibase/{environment}/{server-type}/{server-name}
    # Default server name is "main"
    SERVER_NAME="${SERVER_NAME:-main}"
    SECRET_NAME="liquibase/${DB_ENVIRONMENT}/${DB_SERVER}/${SERVER_NAME}"

    echo "Reading secret: $SECRET_NAME"
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text 2>/dev/null || true)

    # If secret not found, try without server name (backward compatibility)
    if [ -z "$SECRET_JSON" ]; then
        echo "Secret not found at: $SECRET_NAME"
        echo "Trying alternate path: liquibase/${DB_ENVIRONMENT}/${DB_SERVER}"
        SECRET_NAME="liquibase/${DB_ENVIRONMENT}/${DB_SERVER}"
        SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text)
    fi

    # Extract database configuration from: secret.databases.{dbname}.connection
    DB_URL=$(echo "$SECRET_JSON" | jq -r --arg db "$DB_NAME" '.databases[$db].connection.url // empty')
    DB_USERNAME=$(echo "$SECRET_JSON" | jq -r --arg db "$DB_NAME" '.databases[$db].connection.username // empty')
    DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r --arg db "$DB_NAME" '.databases[$db].connection.password // empty')

    if [ -z "$DB_URL" ] || [ "$DB_URL" = "null" ]; then
        echo "❌ Database '$DB_NAME' not found in secret '$SECRET_NAME'"
        echo ""
        echo "Available databases in this secret:"
        echo "$SECRET_JSON" | jq -r '.databases | keys[]' 2>/dev/null || echo "  (none found)"
        echo ""
        echo "Expected secret structure:"
        echo "{"
        echo "  \"master\": { ... },"
        echo "  \"databases\": {"
        echo "    \"$DB_NAME\": {"
        echo "      \"connection\": {"
        echo "        \"url\": \"jdbc:...\","
        echo "        \"username\": \"...\","
        echo "        \"password\": \"...\""
        echo "      },"
        echo "      \"users\": { ... }"
        echo "    }"
        echo "  }"
        echo "}"
        exit 1
    fi

    # Auto-detect database type from server name or URL
    case "$DB_SERVER" in
        "postgres"|"postgresql")
            DB_TYPE="postgresql"
            DB_DRIVER="org.postgresql.Driver"
            ;;
        "mysql")
            DB_TYPE="mysql"
            DB_DRIVER="com.mysql.cj.jdbc.Driver"
            ;;
        "sqlserver"|"mssql")
            DB_TYPE="sqlserver"
            DB_DRIVER="com.microsoft.sqlserver.jdbc.SQLServerDriver"
            ;;
        "oracle"|"ora")
            DB_TYPE="oracle"
            DB_DRIVER="oracle.jdbc.OracleDriver"
            ;;
        *)
            # Fallback: try to detect from URL
            if [[ "$DB_URL" == *"postgresql"* ]]; then
                DB_TYPE="postgresql"
                DB_DRIVER="org.postgresql.Driver"
            elif [[ "$DB_URL" == *"mysql"* ]]; then
                DB_TYPE="mysql"
                DB_DRIVER="com.mysql.cj.jdbc.Driver"
            elif [[ "$DB_URL" == *"sqlserver"* ]]; then
                DB_TYPE="sqlserver"
                DB_DRIVER="com.microsoft.sqlserver.jdbc.SQLServerDriver"
            elif [[ "$DB_URL" == *"oracle"* ]]; then
                DB_TYPE="oracle"
                DB_DRIVER="oracle.jdbc.OracleDriver"
            else
                echo "❌ Cannot determine database type from server name '$DB_SERVER' or URL"
                exit 1
            fi
            ;;
    esac

    echo "Database type: $DB_TYPE"

    # Mask password for security
    echo "::add-mask::$DB_PASSWORD"

    # Modify URL for SQL Server SSL compatibility
    if [ "$DB_TYPE" = "sqlserver" ]; then
        if [[ "$DB_URL" != *"encrypt="* ]]; then
            if [[ "$DB_URL" == *"?"* ]]; then
                DB_URL="${DB_URL}&encrypt=false&trustServerCertificate=true"
            else
                DB_URL="${DB_URL};encrypt=false;trustServerCertificate=true"
            fi
        elif [[ "$DB_URL" != *"trustServerCertificate"* ]]; then
            if [[ "$DB_URL" == *"?"* ]]; then
                DB_URL="${DB_URL}&trustServerCertificate=true"
            else
                DB_URL="${DB_URL};trustServerCertificate=true"
            fi
        fi
    fi

    # Handle Oracle URL format
    if [ "$DB_TYPE" = "oracle" ]; then
        if [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([0-9]+):([^/?]+) ]]; then
            HOST="${BASH_REMATCH[1]}"
            PORT="${BASH_REMATCH[2]}"
            SID_OR_SERVICE="${BASH_REMATCH[3]}"

            if [[ "$SID_OR_SERVICE" == "ORCL" || "$SID_OR_SERVICE" == "XE" ]]; then
                DB_URL="jdbc:oracle:thin:@${HOST}:${PORT}/${SID_OR_SERVICE}"
                echo "Using Oracle service name format: ${SID_OR_SERVICE}"
            else
                echo "Preserving Oracle SID format: ${SID_OR_SERVICE}"
            fi
        fi
    fi

    # Create configuration file
    cat > "liquibase-$DATABASE.properties" << EOF
changelogFile=changelog-$DATABASE.xml
url=$DB_URL
username=$DB_USERNAME
password=$DB_PASSWORD
driver=$DB_DRIVER
logLevel=INFO
logFile=liquibase-$DATABASE.log
outputFile=liquibase-$DATABASE-output.txt
EOF

    echo "✅ Production configuration created for $DB_TYPE database: $DB_NAME"
fi
