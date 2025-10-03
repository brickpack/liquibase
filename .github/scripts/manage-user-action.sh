#!/bin/bash
set -e

# This script handles user management actions
# Called from manage-users.yml workflow
# Environment variables are set by the workflow

# Parse database identifier
DB_SERVER=$(echo "$DATABASE" | cut -d'-' -f1)
DB_NAME=$(echo "$DATABASE" | cut -d'-' -f2-)

echo "Parsed: Server=$DB_SERVER, Database=$DB_NAME"

# Get database connection from per-server secret
SECRET_NAME="liquibase-${DB_SERVER}-prod"
echo "Reading secret: $SECRET_NAME"

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --query SecretString --output text)

# Extract database configuration
DB_CONFIG=$(echo "$SECRET_JSON" | jq -r --arg db "$DB_NAME" '.databases[$db] // empty')

if [ -z "$DB_CONFIG" ] || [ "$DB_CONFIG" = "null" ]; then
  echo "❌ Database '$DB_NAME' not found in secret '$SECRET_NAME'"
  exit 1
fi

DB_URL=$(echo "$DB_CONFIG" | jq -r '.connection.url')
DB_USER=$(echo "$DB_CONFIG" | jq -r '.connection.username')
DB_PASS=$(echo "$DB_CONFIG" | jq -r '.connection.password')

# Auto-detect database type
case "$DB_SERVER" in
  postgres|postgresql) DB_TYPE="postgresql" ;;
  mysql) DB_TYPE="mysql" ;;
  sqlserver|mssql) DB_TYPE="sqlserver" ;;
  oracle|ora) DB_TYPE="oracle" ;;
  *)
    if [[ "$DB_URL" == *"postgresql"* ]]; then DB_TYPE="postgresql"
    elif [[ "$DB_URL" == *"mysql"* ]]; then DB_TYPE="mysql"
    elif [[ "$DB_URL" == *"sqlserver"* ]]; then DB_TYPE="sqlserver"
    elif [[ "$DB_URL" == *"oracle"* ]]; then DB_TYPE="oracle"
    else
      echo "❌ Cannot determine database type"
      exit 1
    fi
    ;;
esac

echo "Database type: $DB_TYPE"

# Parse JDBC URL to get host, port, database name
if [[ "$DB_URL" =~ jdbc:sqlserver://([^:]+):([^\;]+) ]]; then
  DB_HOST="${BASH_REMATCH[1]}"
  DB_PORT="${BASH_REMATCH[2]}"
  JDBC_DB_NAME=$(echo "$DB_URL" | sed -n 's/.*databaseName=\([^;]*\).*/\1/p')
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@//([^:]+):([^/]+)/(.+) ]]; then
  DB_HOST="${BASH_REMATCH[1]}"
  DB_PORT="${BASH_REMATCH[2]}"
  JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([^:]+):(.+) ]]; then
  DB_HOST="${BASH_REMATCH[1]}"
  DB_PORT="${BASH_REMATCH[2]}"
  JDBC_DB_NAME="${BASH_REMATCH[3]}"
elif [[ "$DB_URL" =~ jdbc:([^:]+)://([^:]+):([^/]+)/(.+) ]]; then
  DB_HOST="${BASH_REMATCH[2]}"
  DB_PORT="${BASH_REMATCH[3]}"
  JDBC_DB_NAME="${BASH_REMATCH[4]}"
fi

echo "Connection: $DB_HOST:$DB_PORT/$JDBC_DB_NAME"

# Execute action
case "$ACTION" in
  sync-passwords)
    echo "Syncing all user passwords from AWS Secrets Manager..."
    chmod +x ./.github/scripts/manage-users.sh
    ./.github/scripts/manage-users.sh "$DATABASE"
    ;;

  create-user)
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
      echo "❌ create-user requires username and password"
      exit 1
    fi

    echo "Creating user: $USERNAME"

    case "$DB_TYPE" in
      postgresql)
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$JDBC_DB_NAME" -v ON_ERROR_STOP=1 <<'EOSQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '${USERNAME}') THEN
        CREATE USER ${USERNAME} WITH PASSWORD '${PASSWORD}';
        RAISE NOTICE 'Created user: ${USERNAME}';
    ELSE
        RAISE NOTICE 'User already exists: ${USERNAME}';
    END IF;
END
$$;
EOSQL
        ;;

      mysql)
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$JDBC_DB_NAME" <<EOSQL
CREATE USER IF NOT EXISTS '${USERNAME}'@'%' IDENTIFIED BY '${PASSWORD}';
SELECT 'User created: ${USERNAME}' AS result;
EOSQL
        ;;

      sqlserver)
        sqlcmd -S "$DB_HOST,$DB_PORT" -U "$DB_USER" -P "$DB_PASS" -d "$JDBC_DB_NAME" -C <<EOSQL
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = '${USERNAME}')
BEGIN
    CREATE LOGIN [${USERNAME}] WITH PASSWORD = '${PASSWORD}';
END
USE [${JDBC_DB_NAME}];
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '${USERNAME}')
BEGIN
    CREATE USER [${USERNAME}] FOR LOGIN [${USERNAME}];
END
GO
EOSQL
        ;;
    esac
    echo "✅ User created"
    ;;

  update-password)
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
      echo "❌ update-password requires username and password"
      exit 1
    fi

    echo "Updating password for: $USERNAME"

    case "$DB_TYPE" in
      postgresql)
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$JDBC_DB_NAME" -c "ALTER USER $USERNAME WITH PASSWORD '$PASSWORD';"
        ;;

      mysql)
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$JDBC_DB_NAME" -e "ALTER USER '${USERNAME}'@'%' IDENTIFIED BY '${PASSWORD}'; FLUSH PRIVILEGES;"
        ;;

      sqlserver)
        sqlcmd -S "$DB_HOST,$DB_PORT" -U "$DB_USER" -P "$DB_PASS" -d "$JDBC_DB_NAME" -C -Q "ALTER LOGIN [${USERNAME}] WITH PASSWORD = '${PASSWORD}';"
        ;;
    esac
    echo "✅ Password updated"
    ;;

  grant-privileges)
    if [ -z "$USERNAME" ]; then
      echo "❌ grant-privileges requires username"
      exit 1
    fi

    echo "Granting '$PRIVILEGES' privileges to: $USERNAME"

    # Build GRANT SQL
    if [ "$PRIVILEGES" = "custom" ]; then
      if [ -z "$CUSTOM_SQL" ]; then
        echo "❌ Custom privileges requires custom_sql input"
        exit 1
      fi
      GRANT_SQL="$CUSTOM_SQL"
    else
      case "$DB_TYPE-$PRIVILEGES" in
        postgresql-readwrite)
          GRANT_SQL="GRANT CONNECT ON DATABASE $JDBC_DB_NAME TO $USERNAME;
GRANT USAGE ON SCHEMA public TO $USERNAME;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $USERNAME;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $USERNAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $USERNAME;"
          ;;
        postgresql-readonly)
          GRANT_SQL="GRANT CONNECT ON DATABASE $JDBC_DB_NAME TO $USERNAME;
GRANT USAGE ON SCHEMA public TO $USERNAME;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $USERNAME;"
          ;;
        postgresql-admin)
          GRANT_SQL="GRANT ALL PRIVILEGES ON DATABASE $JDBC_DB_NAME TO $USERNAME;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $USERNAME;"
          ;;
        mysql-readwrite)
          GRANT_SQL="GRANT SELECT, INSERT, UPDATE, DELETE ON ${JDBC_DB_NAME}.* TO '${USERNAME}'@'%'; FLUSH PRIVILEGES;"
          ;;
        mysql-readonly)
          GRANT_SQL="GRANT SELECT ON ${JDBC_DB_NAME}.* TO '${USERNAME}'@'%'; FLUSH PRIVILEGES;"
          ;;
        mysql-admin)
          GRANT_SQL="GRANT ALL PRIVILEGES ON ${JDBC_DB_NAME}.* TO '${USERNAME}'@'%'; FLUSH PRIVILEGES;"
          ;;
        sqlserver-readwrite)
          GRANT_SQL="USE [${JDBC_DB_NAME}]; ALTER ROLE db_datareader ADD MEMBER [${USERNAME}]; ALTER ROLE db_datawriter ADD MEMBER [${USERNAME}];"
          ;;
        sqlserver-readonly)
          GRANT_SQL="USE [${JDBC_DB_NAME}]; ALTER ROLE db_datareader ADD MEMBER [${USERNAME}];"
          ;;
        sqlserver-admin)
          GRANT_SQL="USE [${JDBC_DB_NAME}]; ALTER ROLE db_owner ADD MEMBER [${USERNAME}];"
          ;;
      esac
    fi

    # Execute GRANT
    case "$DB_TYPE" in
      postgresql)
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$JDBC_DB_NAME" -c "$GRANT_SQL"
        ;;
      mysql)
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$JDBC_DB_NAME" -e "$GRANT_SQL"
        ;;
      sqlserver)
        sqlcmd -S "$DB_HOST,$DB_PORT" -U "$DB_USER" -P "$DB_PASS" -C -Q "$GRANT_SQL"
        ;;
    esac
    echo "✅ Privileges granted"
    ;;

  revoke-privileges)
    if [ -z "$USERNAME" ]; then
      echo "❌ revoke-privileges requires username"
      exit 1
    fi

    echo "Revoking '$PRIVILEGES' privileges from: $USERNAME"

    # Build REVOKE SQL
    if [ "$PRIVILEGES" = "custom" ]; then
      if [ -z "$CUSTOM_SQL" ]; then
        echo "❌ Custom privileges requires custom_sql input"
        exit 1
      fi
      REVOKE_SQL="$CUSTOM_SQL"
    else
      case "$DB_TYPE-$PRIVILEGES" in
        postgresql-*)
          REVOKE_SQL="REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM $USERNAME;
REVOKE ALL PRIVILEGES ON DATABASE $JDBC_DB_NAME FROM $USERNAME;"
          ;;
        mysql-*)
          REVOKE_SQL="REVOKE ALL PRIVILEGES ON ${JDBC_DB_NAME}.* FROM '${USERNAME}'@'%'; FLUSH PRIVILEGES;"
          ;;
        sqlserver-readwrite)
          REVOKE_SQL="USE [${JDBC_DB_NAME}]; ALTER ROLE db_datawriter DROP MEMBER [${USERNAME}];"
          ;;
        sqlserver-readonly)
          REVOKE_SQL="USE [${JDBC_DB_NAME}]; ALTER ROLE db_datareader DROP MEMBER [${USERNAME}];"
          ;;
        sqlserver-admin)
          REVOKE_SQL="USE [${JDBC_DB_NAME}]; ALTER ROLE db_owner DROP MEMBER [${USERNAME}];"
          ;;
      esac
    fi

    # Execute REVOKE
    case "$DB_TYPE" in
      postgresql)
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$JDBC_DB_NAME" -c "$REVOKE_SQL"
        ;;
      mysql)
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$JDBC_DB_NAME" -e "$REVOKE_SQL"
        ;;
      sqlserver)
        sqlcmd -S "$DB_HOST,$DB_PORT" -U "$DB_USER" -P "$DB_PASS" -C -Q "$REVOKE_SQL"
        ;;
    esac
    echo "✅ Privileges revoked"
    ;;

  drop-user)
    if [ -z "$USERNAME" ]; then
      echo "❌ drop-user requires username"
      exit 1
    fi

    echo "⚠️  Dropping user: $USERNAME"

    case "$DB_TYPE" in
      postgresql)
        PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$JDBC_DB_NAME" -c "DROP USER IF EXISTS $USERNAME;"
        ;;
      mysql)
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$JDBC_DB_NAME" -e "DROP USER IF EXISTS '${USERNAME}'@'%'; FLUSH PRIVILEGES;"
        ;;
      sqlserver)
        sqlcmd -S "$DB_HOST,$DB_PORT" -U "$DB_USER" -P "$DB_PASS" -d "$JDBC_DB_NAME" -C -Q "USE [${JDBC_DB_NAME}]; DROP USER IF EXISTS [${USERNAME}]; DROP LOGIN IF EXISTS [${USERNAME}];"
        ;;
    esac
    echo "✅ User dropped"
    ;;

  *)
    echo "❌ Unknown action: $ACTION"
    exit 1
    ;;
esac
