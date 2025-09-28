#!/bin/bash
set -e

DATABASE=$1

if [ -z "$DATABASE" ]; then
    echo "❌ Usage: $0 <database>"
    exit 1
fi

echo "🧹 Cleaning up sensitive files for $DATABASE..."

# Remove properties file with credentials
rm -f "liquibase-$DATABASE.properties"

# Sanitize log files
LOG_FILE="liquibase-$DATABASE.log"
if [ -f "$LOG_FILE" ]; then
    echo "🧹 Sanitizing log file for security..."
    # Remove password occurrences
    sed -i 's/password=[^[:space:]]*/password=***REDACTED***/g' "$LOG_FILE"
    sed -i 's/jdbc:postgresql:\/\/[^:]*:[^@]*@/jdbc:postgresql:\/\/***USER***:***PASS***@/g' "$LOG_FILE"
    sed -i 's/jdbc:mysql:\/\/[^:]*:[^@]*@/jdbc:mysql:\/\/***USER***:***PASS***@/g' "$LOG_FILE"
    sed -i 's/jdbc:sqlserver:\/\/[^;]*;.*user=[^;]*;password=[^;]*/jdbc:sqlserver:\/\/***SERVER***;user=***USER***;password=***PASS***/g' "$LOG_FILE"

    echo "📄 Final log summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "No log content to show"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo "✅ Cleanup completed for $DATABASE"