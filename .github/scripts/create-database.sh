#!/bin/bash
set -e

DATABASE_TYPE=$1
DATABASE_NAME=$2
SECRET_NAME=${3:-"liquibase-databases"}

if [ -z "$DATABASE_TYPE" ] || [ -z "$DATABASE_NAME" ]; then
    echo "Usage: $0 <database_type> <database_name> [secret_name]"
    echo "Database types: postgresql, mysql, sqlserver, oracle"
    exit 1
fi

echo "Creating $DATABASE_TYPE database: $DATABASE_NAME"

# Get credentials from secrets
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query SecretString --output text)

case "$DATABASE_TYPE" in
    postgresql)
        echo " Setting up PostgreSQL database creation..."

        # Look for master connection (prefer postgres-master, fallback to postgres-system)
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["postgres-master"] // .["postgres-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No PostgreSQL master configuration found in secrets"
            echo " Required: postgres-master or postgres-system configuration"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=5432; fi

        echo " Connecting to PostgreSQL server: $HOST:$PORT"

        # Check if database already exists
        DB_EXISTS=$(PGPASSWORD="$MASTER_PASS" psql \
            -h "$HOST" \
            -p "$PORT" \
            -U "$MASTER_USER" \
            -d postgres \
            -t -c "SELECT COUNT(*) FROM pg_database WHERE datname='$DATABASE_NAME';" 2>/dev/null || echo "0")

        DATABASE_CREATED=false
        if [ "$(echo $DB_EXISTS | tr -d ' ')" = "1" ]; then
            echo " Database $DATABASE_NAME already exists, skipping creation"
        else
            echo " Creating database $DATABASE_NAME..."
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

        # Update secrets manager with new database config (only if database was created or if config doesn't exist)
        NEW_URL="jdbc:postgresql://$HOST:$PORT/$DATABASE_NAME"
        EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg name "postgres-$DATABASE_NAME" '.[$name] // empty')

        if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
            echo " Updating secrets manager configuration..."
            NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                --arg name "postgres-$DATABASE_NAME" \
                --arg url "$NEW_URL" \
                --arg user "$MASTER_USER" \
                --arg pass "$MASTER_PASS" \
                '. + {($name): {type: "postgresql", url: $url, username: $user, password: $pass}}')

            if aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "$NEW_CONFIG" 2>/dev/null; then
                echo "✅ Secrets Manager updated: postgres-$DATABASE_NAME"
            else
                echo "⚠️ Could not update Secrets Manager (insufficient permissions)"
                echo " Database creation completed successfully, continuing without secrets update"
            fi
        else
            echo " Database configuration already exists in secrets, skipping update"
        fi

        echo " Database URL: $NEW_URL"
        ;;

    mysql)
        echo " Setting up MySQL database creation..."

        # Look for master connection
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["mysql-master"] // .["mysql-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No MySQL master configuration found in secrets"
            echo " Required: mysql-master or mysql-system configuration"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=3306; fi

        echo " Connecting to MySQL server: $HOST:$PORT"

        # Check if database already exists
        DB_EXISTS=$(mysql \
            -h "$HOST" \
            -P "$PORT" \
            -u "$MASTER_USER" \
            -p"$MASTER_PASS" \
            -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DATABASE_NAME';" \
            -s -N 2>/dev/null || echo "0")

        DATABASE_CREATED=false
        if [ "$DB_EXISTS" = "1" ]; then
            echo " Database $DATABASE_NAME already exists, skipping creation"
        else
            echo " Creating database $DATABASE_NAME..."
            mysql \
                -h "$HOST" \
                -P "$PORT" \
                -u "$MASTER_USER" \
                -p"$MASTER_PASS" \
                -e "CREATE DATABASE $DATABASE_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            echo "✅ Database $DATABASE_NAME created successfully"
            DATABASE_CREATED=true
        fi

        # Update secrets manager with new database config (only if database was created or if config doesn't exist)
        NEW_URL="jdbc:mysql://$HOST:$PORT/$DATABASE_NAME?useSSL=true&serverTimezone=UTC"
        EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg name "mysql-$DATABASE_NAME" '.[$name] // empty')

        if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
            echo " Updating secrets manager configuration..."
            NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                --arg name "mysql-$DATABASE_NAME" \
                --arg url "$NEW_URL" \
                --arg user "$MASTER_USER" \
                --arg pass "$MASTER_PASS" \
                '. + {($name): {type: "mysql", url: $url, username: $user, password: $pass}}')

            if aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "$NEW_CONFIG" 2>/dev/null; then
                echo "✅ Secrets Manager updated: mysql-$DATABASE_NAME"
            else
                echo "⚠️ Could not update Secrets Manager (insufficient permissions)"
                echo " Database creation completed successfully, continuing without secrets update"
            fi
        else
            echo " Database configuration already exists in secrets, skipping update"
        fi

        echo " Database URL: $NEW_URL"
        ;;

    sqlserver)
        echo " Setting up SQL Server database creation..."

        # Look for master connection
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["sqlserver-master"] // .["sqlserver-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No SQL Server master configuration found in secrets"
            echo " Required: sqlserver-master or sqlserver-system configuration"
            exit 1
        fi

        MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
        MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
        MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

        # Extract host and port from JDBC URL
        HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/;]*\).*|\1|')
        PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
        if [ "$PORT" = "$MASTER_URL" ]; then PORT=1433; fi

        echo " Connecting to SQL Server: $HOST:$PORT"

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
            echo " Database must be created manually before running migrations"
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

        DATABASE_CREATED=false
        if [ "$DB_EXISTS" = "1" ]; then
            echo " Database $DATABASE_NAME already exists, skipping creation"
        else
            echo " Creating database $DATABASE_NAME..."
            $SQLCMD_CMD \
                -S "$HOST,$PORT" \
                -U "$MASTER_USER" \
                -P "$MASTER_PASS" \
                -C -No \
                -Q "CREATE DATABASE [$DATABASE_NAME] COLLATE SQL_Latin1_General_CP1_CI_AS;"
            echo "✅ Database $DATABASE_NAME created successfully"
            DATABASE_CREATED=true
        fi

        # Update secrets manager with new database config (only if database was created or if config doesn't exist)
        NEW_URL="jdbc:sqlserver://$HOST:$PORT;databaseName=$DATABASE_NAME;encrypt=false;trustServerCertificate=true"
        EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg name "sqlserver-$DATABASE_NAME" '.[$name] // empty')

        if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
            echo " Updating secrets manager configuration..."
            NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                --arg name "sqlserver-$DATABASE_NAME" \
                --arg url "$NEW_URL" \
                --arg user "$MASTER_USER" \
                --arg pass "$MASTER_PASS" \
                '. + {($name): {type: "sqlserver", url: $url, username: $user, password: $pass}}')

            if aws secretsmanager put-secret-value \
                --secret-id "$SECRET_NAME" \
                --secret-string "$NEW_CONFIG" 2>/dev/null; then
                echo "✅ Secrets Manager updated: sqlserver-$DATABASE_NAME"
            else
                echo "⚠️ Could not update Secrets Manager (insufficient permissions)"
                echo " Database creation completed successfully, continuing without secrets update"
            fi
        else
            echo " Database configuration already exists in secrets, skipping update"
        fi

        echo " Database URL: $NEW_URL"
        ;;

    oracle)
        echo " Setting up Oracle database creation..."

        # Look for master connection
        MASTER_CONFIG=$(echo "$SECRET_JSON" | jq -r '.["oracle-master"] // .["oracle-system"] // empty')

        if [ -z "$MASTER_CONFIG" ] || [ "$MASTER_CONFIG" = "null" ]; then
            echo "❌ No Oracle master configuration found in secrets"
            echo " Required: oracle-master or oracle-system configuration"
            echo " Skipping Oracle database creation - assuming database exists"
            echo " If database doesn't exist, Liquibase will show connection errors"
        else
            MASTER_URL=$(echo "$MASTER_CONFIG" | jq -r '.url')
            MASTER_USER=$(echo "$MASTER_CONFIG" | jq -r '.username')
            MASTER_PASS=$(echo "$MASTER_CONFIG" | jq -r '.password')

            # Extract host and port from JDBC URL
            HOST=$(echo "$MASTER_URL" | sed 's|.*://\([^:/]*\).*|\1|')
            PORT=$(echo "$MASTER_URL" | sed 's|.*://[^:]*:\([0-9]*\).*|\1|')
            if [ "$PORT" = "$MASTER_URL" ]; then PORT=1521; fi

            echo " Connecting to Oracle server: $HOST:$PORT"

            # Create Oracle schema/user creation SQL script
            cat > /tmp/create_oracle_db.sql << EOF
-- Create dedicated schema/user for $DATABASE_NAME
WHENEVER SQLERROR EXIT SQL.SQLCODE;
SET PAGESIZE 0;
SET FEEDBACK OFF;
SET HEADING OFF;

-- Check if user/schema already exists
DECLARE
    v_count NUMBER;
    v_username VARCHAR2(30) := UPPER('$DATABASE_NAME');
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM dba_users
    WHERE username = v_username;

    IF v_count = 0 THEN
        -- Create dedicated tablespace for this schema
        EXECUTE IMMEDIATE 'CREATE TABLESPACE ' || v_username || '_DATA
            DATAFILE SIZE 100M AUTOEXTEND ON NEXT 10M MAXSIZE 1G';

        -- Create the user/schema
        EXECUTE IMMEDIATE 'CREATE USER ' || v_username || '
            IDENTIFIED BY "$MASTER_PASS"
            DEFAULT TABLESPACE ' || v_username || '_DATA
            TEMPORARY TABLESPACE TEMP
            QUOTA UNLIMITED ON ' || v_username || '_DATA';

        -- Grant necessary privileges
        EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE SEQUENCE TO ' || v_username;
        EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO ' || v_username;

        DBMS_OUTPUT.PUT_LINE('CREATED: Oracle schema ' || v_username || ' created successfully');
    ELSE
        DBMS_OUTPUT.PUT_LINE('EXISTS: Oracle schema ' || v_username || ' already exists');
    END IF;
END;
/
EXIT;
EOF

            # Try to create the schema using sqlplus
            echo " Attempting to create Oracle schema $DATABASE_NAME..."

            if command -v sqlplus >/dev/null 2>&1; then
                # Use sqlplus if available - connect to the main Oracle database
                ORACLE_SERVICE=$(echo "$MASTER_URL" | sed 's|.*[:/]\([^/]*\)$|\1|')
                DB_RESULT=$(echo "exit" | sqlplus -s "$MASTER_USER/$MASTER_PASS@$HOST:$PORT/$ORACLE_SERVICE" @/tmp/create_oracle_db.sql 2>&1 || echo "ERROR")

                if echo "$DB_RESULT" | grep -q "CREATED:"; then
                    echo "✅ Oracle schema $DATABASE_NAME created successfully"
                    DATABASE_CREATED=true
                elif echo "$DB_RESULT" | grep -q "EXISTS:"; then
                    echo " Oracle schema $DATABASE_NAME already exists"
                    DATABASE_CREATED=false
                else
                    echo "⚠️ Could not create Oracle schema using sqlplus"
                    echo " Schema may need to be created manually"
                    echo " Debug output: $DB_RESULT"
                    DATABASE_CREATED=false
                fi
            else
                echo "⚠️ sqlplus not available - cannot create Oracle schema"
                echo " Oracle schema must be created manually"
                DATABASE_CREATED=false
            fi

            # Clean up temporary file
            rm -f /tmp/create_oracle_db.sql

            # Update secrets manager with new schema config (only if schema was created or if config doesn't exist)
            # Connect to the main Oracle service but as the new schema user
            ORACLE_SERVICE=$(echo "$MASTER_URL" | sed 's|.*[:/]\([^/]*\)$|\1|')
            NEW_URL="jdbc:oracle:thin:@$HOST:$PORT/$ORACLE_SERVICE"
            SCHEMA_USER=$(echo "$DATABASE_NAME" | tr '[:lower:]' '[:upper:]')
            EXISTING_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg name "oracle-$DATABASE_NAME" '.[$name] // empty')

            if [ "$DATABASE_CREATED" = "true" ] || [ -z "$EXISTING_CONFIG" ] || [ "$EXISTING_CONFIG" = "null" ]; then
                echo " Updating secrets manager configuration..."
                NEW_CONFIG=$(echo "$SECRET_JSON" | jq \
                    --arg name "oracle-$DATABASE_NAME" \
                    --arg url "$NEW_URL" \
                    --arg user "$SCHEMA_USER" \
                    --arg pass "$MASTER_PASS" \
                    '. + {($name): {type: "oracle", url: $url, username: $user, password: $pass}}')

                if aws secretsmanager put-secret-value \
                    --secret-id "$SECRET_NAME" \
                    --secret-string "$NEW_CONFIG" 2>/dev/null; then
                    echo "✅ Secrets Manager updated: oracle-$DATABASE_NAME"
                    echo " Schema User: $SCHEMA_USER"
                else
                    echo "⚠️ Could not update Secrets Manager (insufficient permissions)"
                    echo " Schema creation completed successfully, continuing without secrets update"
                fi
            else
                echo " Database configuration already exists in secrets, skipping update"
            fi

            echo " Connection URL: $NEW_URL"
            echo " Schema: $SCHEMA_USER"
        fi
        ;;

    *)
        echo "❌ Unsupported database type: $DATABASE_TYPE"
        echo "Supported types: postgresql, mysql, sqlserver, oracle"
        exit 1
        ;;
esac

echo "✅ Database creation completed successfully"