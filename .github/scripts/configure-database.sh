#!/bin/bash
set -e

DATABASE=$1
SECRET_NAME=${2:-"liquibase-databases"}
TEST_MODE=${3:-"false"}

if [ -z "$DATABASE" ]; then
    echo "❌ Usage: $0 <database> [secret_name] [test_mode]"
    exit 1
fi

echo "🔧 Configuring database: $DATABASE"

if [ "$TEST_MODE" = "true" ]; then
    # Test mode - offline configuration (no classpath needed for PostgreSQL)
    cat > "liquibase-$DATABASE.properties" << EOF
changelogFile=changelog-$DATABASE.xml
url=offline:postgresql
driver=org.postgresql.Driver
logLevel=INFO
logFile=liquibase-$DATABASE.log
outputFile=liquibase-$DATABASE-output.txt
EOF
    echo "✅ Test configuration created"
else
    # Production mode - get credentials from AWS
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text)

    # Extract database configuration
    DB_URL=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].url // empty')
    DB_USERNAME=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].username // empty')
    DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].password // empty')
    DB_TYPE=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].type // empty')

    if [ -z "$DB_URL" ] || [ "$DB_URL" = "null" ]; then
        echo "❌ Database configuration for '$DATABASE' not found in secret '$SECRET_NAME'"
        echo "Available databases:"
        echo "$SECRET_JSON" | jq -r 'keys[]'
        exit 1
    fi

    # Auto-detect database type from URL if not specified
    if [ -z "$DB_TYPE" ] || [ "$DB_TYPE" = "null" ]; then
        if [[ "$DB_URL" == *"postgresql"* ]]; then
            DB_TYPE="postgresql"
        elif [[ "$DB_URL" == *"mysql"* ]]; then
            DB_TYPE="mysql"
        elif [[ "$DB_URL" == *"sqlserver"* ]] || [[ "$DB_URL" == *"mssql"* ]]; then
            DB_TYPE="sqlserver"
        elif [[ "$DB_URL" == *"oracle"* ]]; then
            DB_TYPE="oracle"
        else
            echo "❌ Cannot auto-detect database type from URL"
            exit 1
        fi
        echo "🔍 Auto-detected database type: $DB_TYPE"
    fi

    # Set driver configuration
    case "$DB_TYPE" in
        "postgresql")
            DB_DRIVER="org.postgresql.Driver"
            DRIVER_PATH=""  # PostgreSQL driver included in Liquibase 4.33.0
            ;;
        "mysql")
            DB_DRIVER="com.mysql.cj.jdbc.Driver"
            DRIVER_PATH="drivers/mysql.jar"
            ;;
        "sqlserver")
            DB_DRIVER="com.microsoft.sqlserver.jdbc.SQLServerDriver"
            DRIVER_PATH="drivers/sqlserver.jar"
            ;;
        "oracle")
            DB_DRIVER="oracle.jdbc.OracleDriver"
            DRIVER_PATH="drivers/oracle.jar"
            ;;
        *)
            echo "❌ Unsupported database type: $DB_TYPE"
            exit 1
            ;;
    esac

    # Mask password for security
    echo "::add-mask::$DB_PASSWORD"

    # Modify URL for SQL Server SSL compatibility
    if [ "$DB_TYPE" = "sqlserver" ]; then
        # Add SSL parameters for compatibility with ODBC Driver 18
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

    # Handle Oracle URL format (preserve SID if specified, otherwise use service name)
    if [ "$DB_TYPE" = "oracle" ]; then
        if [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([0-9]+):([^/?]+) ]]; then
            HOST="${BASH_REMATCH[1]}"
            PORT="${BASH_REMATCH[2]}"
            SID_OR_SERVICE="${BASH_REMATCH[3]}"

            # If the URL already uses SID format (:finance), preserve it
            # Only convert to service name if using generic names like 'ORCL'
            if [[ "$SID_OR_SERVICE" == "ORCL" || "$SID_OR_SERVICE" == "XE" ]]; then
                # Convert to service name format for standard Oracle instances
                DB_URL="jdbc:oracle:thin:@${HOST}:${PORT}/${SID_OR_SERVICE}"
                echo "🔧 Using Oracle service name format: ${SID_OR_SERVICE}"
            else
                # Keep original SID format for custom database names
                echo "🔧 Preserving Oracle SID format: ${SID_OR_SERVICE}"
                echo "📝 Connecting to Oracle database SID: ${SID_OR_SERVICE}"
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
EOF

    # Add classpath only if driver path is specified
    if [ -n "$DRIVER_PATH" ]; then
        echo "classpath=$DRIVER_PATH" >> "liquibase-$DATABASE.properties"
    fi

    cat >> "liquibase-$DATABASE.properties" << EOF
logLevel=INFO
logFile=liquibase-$DATABASE.log
outputFile=liquibase-$DATABASE-output.txt
EOF

    echo "✅ Production configuration created for $DB_TYPE database"
fi