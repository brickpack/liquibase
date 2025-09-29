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
        # Add trustServerCertificate=true if not already present
        if [[ "$DB_URL" != *"trustServerCertificate"* ]]; then
            if [[ "$DB_URL" == *"?"* ]]; then
                DB_URL="${DB_URL}&trustServerCertificate=true"
            else
                DB_URL="${DB_URL};trustServerCertificate=true"
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