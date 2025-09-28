#!/bin/bash
set -e

DATABASE=$1

if [ -z "$DATABASE" ]; then
    echo "❌ Usage: $0 <database>"
    exit 1
fi

echo "📁 Changelog Analysis for $DATABASE:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CHANGELOG_FILE="changelog-$DATABASE.xml"

if [ -f "$CHANGELOG_FILE" ]; then
    echo "✅ Found $CHANGELOG_FILE"
    echo ""

    # Show included files
    echo "🔍 Scanning for included SQL files:"
    if grep -q 'file=' "$CHANGELOG_FILE"; then
        grep -o 'file="[^"]*"' "$CHANGELOG_FILE" | sed 's/file="//g' | sed 's/"//g' | while read file; do
            if [ -f "$file" ]; then
                echo "  ✅ $file"
                changeset_count=$(grep -c "^--changeset" "$file" 2>/dev/null || echo "0")
                echo "      📊 Contains $changeset_count changeset(s)"
            else
                echo "  ❌ $file (NOT FOUND)"
            fi
        done
    else
        echo "  ℹ️  No included files found"
    fi
else
    echo "❌ $CHANGELOG_FILE not found!"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"