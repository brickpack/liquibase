#!/bin/bash

# Simple script to create the smallest AWS RDS PostgreSQL instance
# Usage: ./create-postgres-rds.sh

set -e  # Exit on any error

# Configuration - modify these values as needed
DB_INSTANCE_IDENTIFIER="postgres-prod"
DB_NAME="userdb"
MASTER_USERNAME="postgres_user"
MASTER_PASSWORD="secure_postgres_password"  # Change this to a secure password
DB_INSTANCE_CLASS="db.t3.micro"     # Smallest available instance
ALLOCATED_STORAGE="20"              # Minimum storage (20 GB)
ENGINE_VERSION="17.6"               # PostgreSQL version (latest)

echo "Creating AWS RDS PostgreSQL micro instance..."
echo "Instance ID: $DB_INSTANCE_IDENTIFIER"
echo "Database Name: $DB_NAME"
echo "Instance Class: $DB_INSTANCE_CLASS"
echo "Storage: ${ALLOCATED_STORAGE}GB"
echo "PostgreSQL Version: $ENGINE_VERSION"
echo ""

# Create the RDS instance
aws rds create-db-instance \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --db-instance-class "$DB_INSTANCE_CLASS" \
    --engine postgres \
    --engine-version "$ENGINE_VERSION" \
    --master-username "$MASTER_USERNAME" \
    --master-user-password "$MASTER_PASSWORD" \
    --allocated-storage "$ALLOCATED_STORAGE" \
    --storage-type gp2 \
    --db-name "$DB_NAME" \
    --backup-retention-period 0 \
    --no-multi-az \
    --storage-encrypted \
    --publicly-accessible \
    --auto-minor-version-upgrade \
    --no-deletion-protection \
    --no-copy-tags-to-snapshot

echo ""
echo "✅ RDS instance creation initiated!"
echo ""
echo "⏳ The instance is being created. This typically takes 5-10 minutes."
echo ""
echo "Check status with:"
echo "aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --query 'DBInstances[0].DBInstanceStatus'"
echo ""
echo "Once available, get connection details:"
echo "aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --query 'DBInstances[0].Endpoint'"
echo ""
echo "Connection string will be:"
echo "jdbc:postgresql://[ENDPOINT]:5432/$DB_NAME"
echo "Username: $MASTER_USERNAME"
echo "Password: $MASTER_PASSWORD"
echo ""
echo "📋 This matches your database-credentials-example.json structure:"
echo "- Instance ID: $DB_INSTANCE_IDENTIFIER"
echo "- Database: $DB_NAME"
echo "- Username: $MASTER_USERNAME"
echo ""
echo "💰 Cost estimate: ~$15-20/month for db.t3.micro with 20GB storage"
echo ""
echo "🗑️  To delete later:"
echo "aws rds delete-db-instance --db-instance-identifier $DB_INSTANCE_IDENTIFIER --skip-final-snapshot"