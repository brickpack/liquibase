#!/bin/bash

# Script to create AWS Secrets Manager secret for Liquibase
# Usage: ./create-aws-secret.sh [RDS_ENDPOINT]

set -e

# Get RDS endpoint from command line or prompt for it
if [ -z "$1" ]; then
    echo "Enter your RDS endpoint (e.g., postgres-prod.xxxxxxxxx.us-east-1.rds.amazonaws.com):"
    read -r RDS_ENDPOINT
else
    RDS_ENDPOINT="$1"
fi

SECRET_NAME="liquibase-databases"
DB_NAME="userdb"
USERNAME="postgres_user"
PASSWORD="secure_postgres_password"

echo "Creating AWS Secrets Manager secret..."
echo "Secret Name: $SECRET_NAME"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo ""

# Create the secret JSON (properly formatted)
SECRET_JSON=$(cat <<EOF
{
  "postgres-prod": {
    "type": "postgresql",
    "url": "jdbc:postgresql://${RDS_ENDPOINT}:5432/${DB_NAME}",
    "username": "${USERNAME}",
    "password": "${PASSWORD}"
  }
}
EOF
)

# Validate JSON format
echo "Validating JSON format..."
echo "$SECRET_JSON" | jq . > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ JSON format is valid"
else
    echo "❌ JSON format is invalid"
    echo "$SECRET_JSON"
    exit 1
fi

# Create the secret
aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "Liquibase database credentials for PostgreSQL" \
    --secret-string "$SECRET_JSON"

echo ""
echo "✅ Secret created successfully!"
echo ""
echo "Verify the secret:"
echo "aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text | jq ."
echo ""
echo "Test secret parsing:"
echo "aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text | jq -r '.\"postgres-prod\".url'"