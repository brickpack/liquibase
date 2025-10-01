#!/bin/bash
set -e

# Script to safely retrieve user passwords from AWS Secrets Manager
# Usage: ./get-user-password.sh <secret_name> <username>
# Returns: Password for the specified username

SECRET_NAME=$1
USERNAME=$2

if [ -z "$SECRET_NAME" ] || [ -z "$USERNAME" ]; then
    echo "Usage: $0 <secret_name> <username>"
    echo "Example: $0 liquibase-users app_user"
    exit 1
fi

echo "Retrieving password for user '$USERNAME' from secret '$SECRET_NAME'..." >&2

# Get the secret from AWS Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --query SecretString --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$SECRET_JSON" ]; then
    echo "Failed to retrieve secret '$SECRET_NAME' from AWS Secrets Manager" >&2
    echo "Make sure the secret exists and AWS credentials are configured" >&2
    exit 1
fi

# Extract the password for the specified username
PASSWORD=$(echo "$SECRET_JSON" | jq -r --arg username "$USERNAME" '.[$username] // empty')

if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then
    echo "Password for user '$USERNAME' not found in secret '$SECRET_NAME'" >&2
    echo "Available users in secret:" >&2
    echo "$SECRET_JSON" | jq -r 'keys[]' >&2
    exit 1
fi

# Return the password (only to stdout, errors go to stderr)
echo "$PASSWORD"