#!/bin/bash
set -e

DATABASE=$1
COMMAND=$2
TEST_MODE=${3:-"false"}

if [ -z "$DATABASE" ] || [ -z "$COMMAND" ]; then
    echo "❌ Usage: $0 <database> <command> [test_mode]"
    echo "Commands: validate, update, update-sql, status, clear-checksums"
    exit 1
fi

PROPERTIES_FILE="liquibase-$DATABASE.properties"
SQL_OUTPUT="planned-changes-$DATABASE.sql"

if [ ! -f "$PROPERTIES_FILE" ]; then
    echo "❌ Properties file not found: $PROPERTIES_FILE"
    exit 1
fi

case "$COMMAND" in
    "validate")
        echo "🔍 Validating changelog for $DATABASE..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ./liquibase --defaults-file="$PROPERTIES_FILE" validate; then
            echo "✅ Changelog validation PASSED for $DATABASE"
        else
            echo "❌ Changelog validation FAILED for $DATABASE"
            exit 1
        fi
        ;;
    "update")
        echo "🚀 Deploying changes to $DATABASE..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ./liquibase --defaults-file="$PROPERTIES_FILE" update; then
            echo "✅ Deployment completed successfully for $DATABASE"
        else
            echo "❌ Deployment FAILED for $DATABASE"
            exit 1
        fi
        ;;
    "update-sql")
        echo "🧪 Generating SQL preview for $DATABASE..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ./liquibase --defaults-file="$PROPERTIES_FILE" update-sql > "$SQL_OUTPUT"; then
            echo "✅ SQL generation completed successfully"

            # Analyze the generated SQL
            if [ -f "$SQL_OUTPUT" ]; then
                file_size=$(wc -c < "$SQL_OUTPUT")
                line_count=$(wc -l < "$SQL_OUTPUT")

                echo ""
                echo "📊 SQL Analysis Summary:"
                echo "  📄 File size: $file_size bytes"
                echo "  📄 Total lines: $line_count"

                # Count statement types
                create_tables=$(grep -c "CREATE TABLE" "$SQL_OUTPUT" 2>/dev/null || echo "0")
                alter_tables=$(grep -c "ALTER TABLE" "$SQL_OUTPUT" 2>/dev/null || echo "0")
                inserts=$(grep -c "INSERT INTO" "$SQL_OUTPUT" 2>/dev/null || echo "0")

                echo "  🏗️  CREATE TABLE statements: $create_tables"
                echo "  🔧 ALTER TABLE statements: $alter_tables"
                echo "  ➕ INSERT statements: $inserts"

                if [ "$TEST_MODE" = "true" ] && [ "$line_count" -gt 0 ]; then
                    echo ""
                    echo "📄 SQL Preview (first 50 lines):"
                    echo "┌─────────────────────────────────────────────────────┐"
                    head -50 "$SQL_OUTPUT" | nl -ba
                    echo "└─────────────────────────────────────────────────────┘"

                    if [ "$line_count" -gt 50 ]; then
                        echo "⚠️  File contains $line_count total lines. Only first 50 shown."
                    fi
                fi
            fi
        else
            echo "❌ SQL generation failed"
            exit 1
        fi
        ;;
    "status")
        echo "📊 Checking database status for $DATABASE..."
        ./liquibase --defaults-file="$PROPERTIES_FILE" status
        ;;
    "clear-checksums")
        echo "🧹 Clearing checksums for $DATABASE..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ./liquibase --defaults-file="$PROPERTIES_FILE" clear-checksums; then
            echo "✅ Checksums cleared successfully for $DATABASE"
        else
            echo "❌ Failed to clear checksums for $DATABASE"
            exit 1
        fi
        ;;
    *)
        echo "❌ Unknown command: $COMMAND"
        exit 1
        ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"