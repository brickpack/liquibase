#!/bin/bash
set -e

# Script to set up multiple database servers efficiently
# Supports dozens of servers per database type

echo "=== Liquibase Multi-Server Setup ==="
echo "This script helps you set up dozens of database servers efficiently."
echo ""

# Function to validate server name
validate_server_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        echo "❌ Invalid server name: '$name' (only letters, numbers, hyphens allowed)"
        return 1
    fi
    return 0
}

# Function to create secret for a server
create_server_secret() {
    local db_type="$1"
    local server_name="$2"
    local region="$3"
    local secret_name="liquibase-${db_type}-${server_name}"
    
    echo "  Creating secret: $secret_name"
    
    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$region" 2>/dev/null; then
        echo "    ⚠️  Secret already exists - skipping"
        return 0
    fi
    
    # Create empty secret structure
    local secret_json=$(cat <<EOF
{
  "master": {
    "type": "$db_type",
    "url": "TBD",
    "username": "TBD", 
    "password": "TBD"
  },
  "databases": {}
}
EOF
)
    
    aws secretsmanager create-secret \
        --name "$secret_name" \
        --description "Liquibase $db_type server configuration for $server_name" \
        --secret-string "$secret_json" \
        --region "$region" >/dev/null
    
    echo "    ✅ Created: $secret_name"
}

# Function to configure a server
configure_server() {
    local db_type="$1"
    local server_name="$2"
    local region="$3"
    
    echo ""
    echo "=== Configuring $db_type server: $server_name ==="
    
    # Get master connection details
    echo "Enter master connection details for $server_name:"
    
    case "$db_type" in
        "postgres")
            read -p "  Host (e.g., $server_name-postgres.aws.com): " host
            read -p "  Port [5432]: " port
            port=${port:-5432}
            read -p "  Username [postgres]: " username
            username=${username:-postgres}
            read -sp "  Password: " password
            echo ""
            url="jdbc:postgresql://${host}:${port}/postgres"
            ;;
        "mysql")
            read -p "  Host (e.g., $server_name-mysql.aws.com): " host
            read -p "  Port [3306]: " port
            port=${port:-3306}
            read -p "  Username [root]: " username
            username=${username:-root}
            read -sp "  Password: " password
            echo ""
            url="jdbc:mysql://${host}:${port}/mysql?useSSL=true&serverTimezone=UTC"
            ;;
        "sqlserver")
            read -p "  Host (e.g., $server_name-sqlserver.aws.com): " host
            read -p "  Port [1433]: " port
            port=${port:-1433}
            read -p "  Username [sa]: " username
            username=${username:-sa}
            read -sp "  Password: " password
            echo ""
            url="jdbc:sqlserver://${host}:${port};databaseName=master;encrypt=true;trustServerCertificate=true"
            ;;
        "oracle")
            read -p "  Host (e.g., $server_name-oracle.aws.com): " host
            read -p "  Port [1521]: " port
            port=${port:-1521}
            read -p "  Username [admin]: " username
            username=${username:-admin}
            read -sp "  Password: " password
            echo ""
            read -p "  Service Name [ORCL]: " service_name
            service_name=${service_name:-ORCL}
            url="jdbc:oracle:thin:@${host}:${port}:${service_name}"
            ;;
    esac
    
    # Update secret with master connection
    local secret_name="liquibase-${db_type}-${server_name}"
    local secret_json=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --region "$region" --query SecretString --output text)
    
    secret_json=$(echo "$secret_json" | jq \
        --arg url "$url" \
        --arg username "$username" \
        --arg password "$password" \
        '.master.url = $url | .master.username = $username | .master.password = $password')
    
    aws secretsmanager put-secret-value \
        --secret-id "$secret_name" \
        --secret-string "$secret_json" \
        --region "$region" >/dev/null
    
    echo "  ✅ Master connection configured for $server_name"
}

# Main script
echo "=== AWS Region Selection ==="
echo "Current AWS_REGION environment variable: ${AWS_REGION:-not set}"
echo ""
read -p "Enter AWS region [us-west-2]: " INPUT_REGION
REGION="${INPUT_REGION:-${AWS_REGION:-us-west-2}}"

echo ""
echo "=== Database Type Selection ==="
echo "1) PostgreSQL"
echo "2) MySQL" 
echo "3) SQL Server"
echo "4) Oracle"
echo "5) All types"
echo ""
read -p "Select database type (1-5): " DB_TYPE_CHOICE

case "$DB_TYPE_CHOICE" in
    1) DB_TYPES=("postgres") ;;
    2) DB_TYPES=("mysql") ;;
    3) DB_TYPES=("sqlserver") ;;
    4) DB_TYPES=("oracle") ;;
    5) DB_TYPES=("postgres" "mysql" "sqlserver" "oracle") ;;
    *) echo "❌ Invalid choice"; exit 1 ;;
esac

echo ""
echo "=== Server Names ==="
echo "Enter server names (one per line, empty line to finish):"
echo "Examples: prod, staging, dev-west, analytics, erp, reporting"
echo ""

servers=()
while true; do
    read -p "Server name: " server_name
    if [ -z "$server_name" ]; then
        break
    fi
    
    if validate_server_name "$server_name"; then
        servers+=("$server_name")
        echo "  ✅ Added: $server_name"
    else
        echo "  ❌ Skipped: $server_name"
    fi
done

if [ ${#servers[@]} -eq 0 ]; then
    echo "❌ No valid servers entered"
    exit 1
fi

echo ""
echo "=== Summary ==="
echo "Database types: ${DB_TYPES[*]}"
echo "Servers: ${servers[*]}"
echo "Region: $REGION"
echo "Total secrets to create: $((${#DB_TYPES[@]} * ${#servers[@]}))"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "=== Creating Secrets ==="

# Create all secrets first
for db_type in "${DB_TYPES[@]}"; do
    echo ""
    echo "Creating $db_type secrets..."
    for server_name in "${servers[@]}"; do
        create_server_secret "$db_type" "$server_name" "$REGION"
    done
done

echo ""
echo "=== Configuration Phase ==="
echo "Now configure the master connections for each server."
echo "You can skip servers you want to configure later."
echo ""

for db_type in "${DB_TYPES[@]}"; do
    for server_name in "${servers[@]}"; do
        read -p "Configure $db_type server '$server_name' now? (y/n/s to skip all remaining): " -n 1 -r
        echo
        case $REPLY in
            [Yy]) configure_server "$db_type" "$server_name" "$REGION" ;;
            [Ss]) echo "Skipping remaining servers"; break 2 ;;
            *) echo "Skipped $db_type-$server_name" ;;
        esac
    done
done

echo ""
echo "=== Setup Complete ==="
echo "✅ Created secrets for:"
for db_type in "${DB_TYPES[@]}"; do
    for server_name in "${servers[@]}"; do
        echo "  - liquibase-${db_type}-${server_name}"
    done
done

echo ""
echo "Next steps:"
echo "1. Configure master connections for servers you skipped (re-run creation scripts)"
echo "2. Add databases to each server using add-database-to-server.sh"
echo "3. Test with workflow dispatch in test mode"
echo ""
echo "To add a database to a server:"
echo "  .github/scripts/add-database-to-server.sh"


