#!/bin/bash
set -e

DATABASE_TYPE=$1
DATABASE_NAME=$2
SECRET_NAME=${3:-"liquibase-databases"}

if [ -z "$DATABASE_TYPE" ] || [ -z "$DATABASE_NAME" ]; then
    echo "❌ Usage: $0 <database_type> <database_name> [secret_name]"
    echo "Database types: postgresql, mysql, sqlserver, oracle"
    exit 1
fi

echo "🏗️ Creating $DATABASE_TYPE database: $DATABASE_NAME"

# Get credentials from secrets
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query SecretString --output text)

case "$DATABASE_TYPE" in
    postgresql)
        echo "🐘 Setting up PostgreSQL database creation..."

        # Look for master connection (prefer postgres-master, fallback to postgres-system)
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["postgres-master"] // .["postgres-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No PostgreSQL master configuration found in secrets"
            echo "💡 Required: postgres-master or postgres-system configuration"
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

        # Check if database already exists
        DB_EXISTS=$(PGPASSWORD="$MASTER_PASS" psql \
            -h "$HOST" \
            -p "$PORT" \
            -U "$MASTER_USER" \
            -d postgres \
            -t -c "SELECT COUNT(*) FROM pg_database WHERE datname='$DATABASE_NAME';" 2>/dev/null || echo "0")

        if [ "$(echo $DB_EXISTS | tr -d ' ')" = "1" ]; then
            echo "ℹ️ Database $DATABASE_NAME already exists, skipping creation"
        else
            echo "📝 Creating database $DATABASE_NAME..."
            PGPASSWORD="$MASTER_PASS" psql \
                -h "$HOST" \
                -p "$PORT" \
                -U "$MASTER_USER" \
                -d postgres \
                -c "CREATE DATABASE $DATABASE_NAME;" \
                -c "COMMENT ON DATABASE $DATABASE_NAME IS 'Created by Liquibase pipeline on $(date)';"
            echo "✅ Database $DATABASE_NAME created successfully"
        fi

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
        ;;

    mysql)
        echo "🐬 Setting up MySQL database creation..."

        # Look for master connection
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["mysql-master"] // .["mysql-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No MySQL master configuration found in secrets"
            echo "💡 Required: mysql-master or mysql-system configuration"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=3306; fi

        echo "🔗 Connecting to MySQL server: $HOST:$PORT"

        # Check if database already exists
        DB_EXISTS=$(mysql \
            -h "$HOST" \
            -P "$PORT" \
            -u "$MASTER_USER" \
            -p"$MASTER_PASS" \
            -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DATABASE_NAME';" \
            -s -N 2>/dev/null || echo "0")

        if [ "$DB_EXISTS" = "1" ]; then
            echo "ℹ️ Database $DATABASE_NAME already exists, skipping creation"
        else
            echo "📝 Creating database $DATABASE_NAME..."
            mysql \
                -h "$HOST" \
                -P "$PORT" \
                -u "$MASTER_USER" \
                -p"$MASTER_PASS" \
                -e "CREATE DATABASE $DATABASE_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            echo "✅ Database $DATABASE_NAME created successfully"
        fi

        # Update secrets manager with new database config
        NEW_URL="jdbc:mysql://$HOST:$PORT/$DATABASE_NAME?useSSL=true&serverTimezone=UTC"
        NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
            --arg name "mysql-$DATABASE_NAME" \
            --arg url "$NEW_URL" \
            --arg user "$MASTER_USER" \
            --arg pass "$MASTER_PASS" \
            '. + {($name): {type: "mysql", url: $url, username: $user, password: $pass}}')

        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_CONFIG"

        echo "✅ Secrets Manager updated: mysql-$DATABASE_NAME"
        echo "📝 Database URL: $NEW_URL"
        ;;

    sqlserver)
        echo "🏢 Setting up SQL Server database creation..."

        # Look for master connection
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["sqlserver-master"] // .["sqlserver-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No SQL Server master configuration found in secrets"
            echo "💡 Required: sqlserver-master or sqlserver-system configuration"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/;]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=1433; fi

        echo "🔗 Connecting to SQL Server: $HOST:$PORT"

        # Find sqlcmd command (try different possible locations)
        SQLCMD_CMD=""
        if command -v sqlcmd >/dev/null 2>&1; then
            SQLCMD_CMD="sqlcmd"
        elif command -v /opt/mssql-tools/bin/sqlcmd >/dev/null 2>&1; then
            SQLCMD_CMD="/opt/mssql-tools/bin/sqlcmd"
        elif command -v /opt/mssql-tools18/bin/sqlcmd >/dev/null 2>&1; then
            SQLCMD_CMD="/opt/mssql-tools18/bin/sqlcmd"
        else
            echo "❌ sqlcmd not found, cannot create SQL Server database"
            echo "ℹ️ Database must be created manually before running migrations"
            exit 1
        fi

        # Check if database already exists (disable encryption for compatibility)
        DB_EXISTS=$($SQLCMD_CMD \
            -S "$HOST,$PORT" \
            -U "$MASTER_USER" \
            -P "$MASTER_PASS" \
            -C -No \
            -Q "SELECT COUNT(*) FROM sys.databases WHERE name='$DATABASE_NAME'" \
            -h -1 -W 2>/dev/null | tr -d ' ' || echo "0")

        if [ "$DB_EXISTS" = "1" ]; then
            echo "ℹ️ Database $DATABASE_NAME already exists, skipping creation"
        else
            echo "📝 Creating database $DATABASE_NAME..."
            $SQLCMD_CMD \
                -S "$HOST,$PORT" \
                -U "$MASTER_USER" \
                -P "$MASTER_PASS" \
                -C -No \
                -Q "CREATE DATABASE [$DATABASE_NAME] COLLATE SQL_Latin1_General_CP1_CI_AS;"
            echo "✅ Database $DATABASE_NAME created successfully"
        fi

        # Update secrets manager with new database config
        NEW_URL="jdbc:sqlserver://$HOST:$PORT;databaseName=$DATABASE_NAME;encrypt=false;trustServerCertificate=true"
        NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
            --arg name "sqlserver-$DATABASE_NAME" \
            --arg url "$NEW_URL" \
            --arg user "$MASTER_USER" \
            --arg pass "$MASTER_PASS" \
            '. + {($name): {type: "sqlserver", url: $url, username: $user, password: $pass}}')

        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_CONFIG"

        echo "✅ Secrets Manager updated: sqlserver-$DATABASE_NAME"
        echo "📝 Database URL: $NEW_URL"
        ;;

    oracle)
        echo "🏛️ Setting up Oracle schema creation..."

        # Look for master connection
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["oracle-master"] // .["oracle-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No Oracle master configuration found in secrets"
            echo "💡 Required: oracle-master or oracle-system configuration"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=1521; fi

        # Extract service name or SID
        SERVICE=$(echo "$MASTER_URL" | sed 's|.*[:/]\([^?]*\).*|\1|')

        echo "🔗 Connecting to Oracle server: $HOST:$PORT/$SERVICE"

        # Check if user/schema already exists
        USER_EXISTS=$(sqlplus -s "$MASTER_USER/$MASTER_PASS@$HOST:$PORT/$SERVICE" <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT COUNT(*) FROM dba_users WHERE username=UPPER('$DATABASE_NAME');
EXIT;
EOF
        )

        if [ "$(echo $USER_EXISTS | tr -d ' ')" = "1" ]; then
            echo "ℹ️ Oracle user/schema $DATABASE_NAME already exists, skipping creation"
        else
            echo "📝 Creating Oracle user/schema $DATABASE_NAME..."

            # Generate secure password
            SCHEMA_PASS=$(openssl rand -base64 16)

            sqlplus -s "$MASTER_USER/$MASTER_PASS@$HOST:$PORT/$SERVICE" <<EOF
CREATE TABLESPACE ${DATABASE_NAME}_DATA
    DATAFILE '${DATABASE_NAME}_data01.dbf' SIZE 100M
    AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

CREATE USER $DATABASE_NAME IDENTIFIED BY "$SCHEMA_PASS"
    DEFAULT TABLESPACE ${DATABASE_NAME}_DATA
    QUOTA UNLIMITED ON ${DATABASE_NAME}_DATA;

GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE TO $DATABASE_NAME;

EXIT;
EOF
            echo "✅ Oracle user/schema $DATABASE_NAME created successfully"
        fi

        # Update secrets manager with new schema config
        NEW_URL="jdbc:oracle:thin:@$HOST:$PORT:$SERVICE"
        NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
            --arg name "oracle-$DATABASE_NAME" \
            --arg url "$NEW_URL" \
            --arg user "$DATABASE_NAME" \
            --arg pass "$SCHEMA_PASS" \
            '. + {($name): {type: "oracle", url: $url, username: $user, password: $pass}}')

        aws secretsmanager put-secret-value \
            --secret-id "$SECRET_NAME" \
            --secret-string "$NEW_CONFIG"

        echo "✅ Secrets Manager updated: oracle-$DATABASE_NAME"
        echo "📝 Schema URL: $NEW_URL"
        ;;

    *)
        echo "❌ Unsupported database type: $DATABASE_TYPE"
        echo "Supported types: postgresql, mysql, sqlserver, oracle"
        exit 1
        ;;
esac

echo "✅ Database creation completed successfully"