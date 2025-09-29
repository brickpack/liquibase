#!/bin/bash
set -e

DATABASE=${1:-"oracle-finance"}
SECRET_NAME=${2:-"liquibase-databases"}

echo "🔍 Diagnosing Oracle schema for $DATABASE..."

# Get database configuration from AWS
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query SecretString --output text)
DB_URL=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].url // empty')
DB_USERNAME=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].username // empty')
DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r --arg db "$DATABASE" '.[$db].password // empty')

if [ -z "$DB_URL" ]; then
    echo "❌ Database configuration for '$DATABASE' not found"
    exit 1
fi

# Mask password
echo "::add-mask::$DB_PASSWORD"

# Convert Oracle URL for RDS compatibility
if [[ "$DB_URL" =~ jdbc:oracle:thin:@([^:]+):([0-9]+):([^/?]+) ]]; then
    HOST="${BASH_REMATCH[1]}"
    PORT="${BASH_REMATCH[2]}"
    DB_URL="jdbc:oracle:thin:@${HOST}:${PORT}/ORCL"
fi

echo "🔗 Connecting to: $DB_URL as $DB_USERNAME"

# Create a temporary SQL script to check schema contents
cat > /tmp/oracle_diagnose.sql << 'EOF'
-- Check current user and connection
SELECT 'Current User: ' || USER FROM dual;
SELECT 'Current Schema: ' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') FROM dual;

-- Check for finance-related tables in current schema
SELECT 'Tables in ' || USER || ' schema:' as info FROM dual;
SELECT table_name FROM user_tables WHERE table_name LIKE '%ACCOUNT%' OR table_name LIKE '%TRANSACTION%';

-- Check for finance-related sequences in current schema
SELECT 'Sequences in ' || USER || ' schema:' as info FROM dual;
SELECT sequence_name FROM user_sequences WHERE sequence_name LIKE '%ACCOUNT%' OR sequence_name LIKE '%TRANSACTION%';

-- Check for tablespaces
SELECT 'Tablespaces:' as info FROM dual;
SELECT tablespace_name FROM dba_tablespaces WHERE tablespace_name LIKE '%FINANCE%';

-- Check Liquibase changelog table
SELECT 'Liquibase Changesets:' as info FROM dual;
SELECT COUNT(*) as total_changesets FROM databasechangelog;
SELECT id, author, filename FROM databasechangelog WHERE filename LIKE '%finance%' ORDER BY dateexecuted;

-- Check for any tables in all schemas that might be finance-related
SELECT 'Finance tables in all schemas:' as info FROM dual;
SELECT owner, table_name FROM dba_tables WHERE table_name LIKE '%ACCOUNT%' OR table_name LIKE '%TRANSACTION%' OR owner LIKE '%FINANCE%';

EOF

# Execute the diagnostic SQL using Liquibase's SQL command
echo "📋 Running Oracle schema diagnosis..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create temporary properties file
cat > "/tmp/liquibase-diagnose.properties" << EOF
url=$DB_URL
username=$DB_USERNAME
password=$DB_PASSWORD
driver=oracle.jdbc.OracleDriver
EOF

# Run the SQL using liquibase
if command -v liquibase >/dev/null 2>&1; then
    liquibase --defaults-file="/tmp/liquibase-diagnose.properties" --changelog-file="/tmp/oracle_diagnose.sql" execute-sql --sql-file="/tmp/oracle_diagnose.sql" || true
else
    echo "⚠️ Liquibase not available locally. SQL script created at /tmp/oracle_diagnose.sql"
    echo "📄 SQL script contents:"
    cat /tmp/oracle_diagnose.sql
fi

# Cleanup
rm -f /tmp/oracle_diagnose.sql /tmp/liquibase-diagnose.properties

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Oracle schema diagnosis completed"