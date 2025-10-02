#!/bin/bash
set -e

DATABASE_TYPE=$1
DATABASE_NAME=$2

if [ -z "$DATABASE_TYPE" ] || [ -z "$DATABASE_NAME" ]; then
    echo "Usage: $0 <database_type> <database_name>"
    echo "Database types: postgresql, mysql, sqlserver, oracle"
    echo "Example: $0 postgresql thedb"
    exit 1
fi

echo "Creating $DATABASE_TYPE database: $DATABASE_NAME"

# Determine secret name based on database type
# Format: liquibase-{server}-prod
case "$DATABASE_TYPE" in
    postgresql)
        SECRET_NAME="liquibase-postgres-prod"
        ;;
    mysql)
        SECRET_NAME="liquibase-mysql-prod"
        ;;
    sqlserver)
        SECRET_NAME="liquibase-sqlserver-prod"
        ;;
    oracle)
        SECRET_NAME="liquibase-oracle-prod"
        ;;
    *)
        echo "❌ Unsupported database type: $DATABASE_TYPE"
        exit 1
        ;;
esac

echo "Reading master connection from secret: $SECRET_NAME"

# Get credentials from per-server secret
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query SecretString --output text)

case "$DATABASE_TYPE" in
    postgresql)
        echo "📋 Setting up PostgreSQL database creation..."

        # Get master connection from .master path
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.master // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No PostgreSQL master configuration found in secret '$SECRET_NAME'"
            echo "   Expected: .master object with url, username, password"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=5432; fi

        echo "🔌 Connecting to PostgreSQL server: $HOST:$PORT"

        # Check if database already exists
        DB_EXISTS=$(PGPASSWORD="$MASTER_PASS" psql \
            -h "$HOST" \
            -p "$PORT" \
            -U "$MASTER_USER" \
            -d postgres \
            -t -c "SELECT COUNT(*) FROM pg_database WHERE datname='$DATABASE_NAME';" 2>/dev/null || echo "0")

        DATABASE_CREATED=false
        if [ "$(echo $DB_EXISTS | tr -d ' ')" = "1" ]; then
            echo "ℹ️  Database $DATABASE_NAME already exists, skipping creation"
        else
            echo "🔨 Creating database $DATABASE_NAME..."
            PGPASSWORD="$MASTER_PASS" psql \
                -h "$HOST" \
                -p "$PORT" \
                -U "$MASTER_USER" \
                -d postgres \
                -c "CREATE DATABASE $DATABASE_NAME;" \
                -c "COMMENT ON DATABASE $DATABASE_NAME IS 'Created by Liquibase pipeline on $(date)';"
            echo "✅ Database $DATABASE_NAME created successfully"
            DATABASE_CREATED=true
        fi

        # Update secrets manager with new database config
        NEW_URL="jdbc:postgresql://$HOST:$PORT/$DATABASE_NAME"

        # Check if database config already exists
        EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE_NAME" '.databases[$db] // empty')

        if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
            echo "📝 Updating secrets manager configuration..."

            # Add/update database entry in .databases.{dbname}
            NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                --arg db "$DATABASE_NAME" \
                --arg url "$NEW_URL" \
                --arg user "$MASTER_USER" \
                --arg pass "$MASTER_PASS" \
                '.databases[$db] = {
                    connection: {
                        url: $url,
                        username: $user,
                        password: $pass
                    },
                    users: (.databases[$db].users // {})
                }')

            if aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "$NEW_CONFIG" 2>/dev/null; then
                echo "✅ Secrets Manager updated: $SECRET_NAME -> databases.$DATABASE_NAME"
            else
                echo "⚠️  Could not update Secrets Manager (insufficient permissions)"
                echo "   Database creation completed successfully, continuing without secrets update"
            fi
        else
            echo "ℹ️  Database configuration already exists in secrets, skipping update"
        fi

        echo "🔗 Database URL: $NEW_URL"
        ;;

    mysql)
        echo "📋 Setting up MySQL database creation..."

        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.master // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No MySQL master configuration found in secret '$SECRET_NAME'"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=3306; fi

        echo "🔌 Connecting to MySQL server: $HOST:$PORT"

        DB_EXISTS=$(mysql \
            -h "$HOST" \
            -P "$PORT" \
            -u "$MASTER_USER" \
            -p"$MASTER_PASS" \
            -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DATABASE_NAME';" \
            -s -N 2>/dev/null || echo "0")

        DATABASE_CREATED=false
        if [ "$DB_EXISTS" = "1" ]; then
            echo "ℹ️  Database $DATABASE_NAME already exists, skipping creation"
        else
            echo "🔨 Creating database $DATABASE_NAME..."
            mysql \
                -h "$HOST" \
                -P "$PORT" \
                -u "$MASTER_USER" \
                -p"$MASTER_PASS" \
                -e "CREATE DATABASE $DATABASE_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            echo "✅ Database $DATABASE_NAME created successfully"
            DATABASE_CREATED=true
        fi

        NEW_URL="jdbc:mysql://$HOST:$PORT/$DATABASE_NAME?useSSL=true&serverTimezone=UTC"
        EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE_NAME" '.databases[$db] // empty')

        if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
            echo "📝 Updating secrets manager configuration..."
            NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                --arg db "$DATABASE_NAME" \
                --arg url "$NEW_URL" \
                --arg user "$MASTER_USER" \
                --arg pass "$MASTER_PASS" \
                '.databases[$db] = {
                    connection: {
                        url: $url,
                        username: $user,
                        password: $pass
                    },
                    users: (.databases[$db].users // {})
                }')

            if aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "$NEW_CONFIG" 2>/dev/null; then
                echo "✅ Secrets Manager updated: $SECRET_NAME -> databases.$DATABASE_NAME"
            else
                echo "⚠️  Could not update Secrets Manager"
            fi
        else
            echo "ℹ️  Database configuration already exists in secrets"
        fi

        echo "🔗 Database URL: $NEW_URL"
        ;;

    sqlserver)
        echo "📋 Setting up SQL Server database creation..."

        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.master // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No SQL Server master configuration found in secret '$SECRET_NAME'"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/;]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=1433; fi

        echo "🔌 Connecting to SQL Server: $HOST:$PORT"

        SQLCMD_CMD=""
        if command -v sqlcmd >/dev/null 2>&1; then
            SQLCMD_CMD="sqlcmd"
        elif command -v /opt/mssql-tools/bin/sqlcmd >/dev/null 2>&1; then
            SQLCMD_CMD="/opt/mssql-tools/bin/sqlcmd"
        elif command -v /opt/mssql-tools18/bin/sqlcmd >/dev/null 2>&1; then
            SQLCMD_CMD="/opt/mssql-tools18/bin/sqlcmd"
        else
            echo "❌ sqlcmd not found"
            exit 1
        fi

        DB_EXISTS=$($SQLCMD_CMD \
            -S "$HOST,$PORT" \
            -U "$MASTER_USER" \
            -P "$MASTER_PASS" \
            -C -No \
            -Q "SELECT COUNT(*) FROM sys.databases WHERE name='$DATABASE_NAME'" \
            -h -1 -W 2>/dev/null | tr -d ' ' || echo "0")

        DATABASE_CREATED=false
        if [ "$DB_EXISTS" = "1" ]; then
            echo "ℹ️  Database $DATABASE_NAME already exists, skipping creation"
        else
            echo "🔨 Creating database $DATABASE_NAME..."
            $SQLCMD_CMD \
                -S "$HOST,$PORT" \
                -U "$MASTER_USER" \
                -P "$MASTER_PASS" \
                -C -No \
                -Q "CREATE DATABASE [$DATABASE_NAME] COLLATE SQL_Latin1_General_CP1_CI_AS;"
            echo "✅ Database $DATABASE_NAME created successfully"
            DATABASE_CREATED=true
        fi

        NEW_URL="jdbc:sqlserver://$HOST:$PORT;databaseName=$DATABASE_NAME;encrypt=false;trustServerCertificate=true"
        EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE_NAME" '.databases[$db] // empty')

        if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
            echo "📝 Updating secrets manager configuration..."
            NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                --arg db "$DATABASE_NAME" \
                --arg url "$NEW_URL" \
                --arg user "$MASTER_USER" \
                --arg pass "$MASTER_PASS" \
                '.databases[$db] = {
                    connection: {
                        url: $url,
                        username: $user,
                        password: $pass
                    },
                    users: (.databases[$db].users // {})
                }')

            if aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "$NEW_CONFIG" 2>/dev/null; then
                echo "✅ Secrets Manager updated: $SECRET_NAME -> databases.$DATABASE_NAME"
            else
                echo "⚠️  Could not update Secrets Manager"
            fi
        else
            echo "ℹ️  Database configuration already exists in secrets"
        fi

        echo "🔗 Database URL: $NEW_URL"
        ;;

    oracle)
        echo "📋 Setting up Oracle database creation..."

        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.master // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "⚠️  No Oracle master configuration found in secret '$SECRET_NAME'"
            echo "   Skipping Oracle database creation - assuming database exists"
            echo "   If database doesn't exist, Liquibase will show connection errors"
            exit 0
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=1521; fi

        echo "🔌 Connecting to Oracle server: $HOST:$PORT"

        # Note: Oracle creates user/schema, not databases
        # Simplified for now - assume schema exists or will be created manually

        echo "ℹ️  Oracle schema management not fully automated"
        echo "   Please ensure schema '$DATABASE_NAME' exists on Oracle server"
        ;;

    *)
        echo "❌ Unsupported database type: $DATABASE_TYPE"
        exit 1
        ;;
esac

echo "✅ Database creation completed successfully"
