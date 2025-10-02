#!/bin/bash
set -e

# Script to rollback Liquibase changesets
# Usage: ./rollback-changeset.sh <database> <count>

DATABASE=$1
COUNT=${2:-1}

if [ -z "$DATABASE" ]; then
    echo "Usage: $0 <database> [count]"
    echo "Example: $0 postgres-prod-myappdb 2"
    echo ""
    echo "Rolls back the last [count] changesets (default: 1)"
    exit 1
fi

PROPERTIES_FILE="liquibase-$DATABASE.properties"

if [ ! -f "$PROPERTIES_FILE" ]; then
    echo "❌ Properties file not found: $PROPERTIES_FILE"
    echo "Run configure-database.sh first to create the properties file"
    exit 1
fi

echo "Rolling back last $COUNT changeset(s) for $DATABASE..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show what will be rolled back
echo "Preview of changesets to rollback:"
liquibase --defaults-file="$PROPERTIES_FILE" rollback-count-sql $COUNT

echo ""
read -p "Continue with rollback? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled"
    exit 0
fi

# Execute rollback
if liquibase --defaults-file="$PROPERTIES_FILE" rollback-count $COUNT; then
    echo "✅ Rollback completed successfully for $DATABASE"
    echo ""
    echo "Current database status:"
    liquibase --defaults-file="$PROPERTIES_FILE" status
else
    echo "❌ Rollback FAILED for $DATABASE"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
