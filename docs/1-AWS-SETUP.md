# AWS Setup for Liquibase CI/CD Pipeline

## 1. Create GitHub OIDC Provider (if needed)

Check if it already exists:
```bash
aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `token.actions.githubusercontent.com`)]'
```

If empty, create it:
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

## 2. Create IAM Role for GitHub Actions

### Step 1: Create Trust Policy

Create `trust-policy.json` (replace YOUR_ACCOUNT_ID, YOUR_GITHUB_USERNAME, YOUR_REPO_NAME):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/main",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/*",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:pull_request"
          ]
        }
      }
    }
  ]
}
```

### Step 2: Create Permissions Policy

Create `permissions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:*:*:secret:liquibase-databases-*",
        "arn:aws:secretsmanager:*:*:secret:liquibase-users-*"
      ]
    }
  ]
}
```

### Step 3: Create the IAM Role

```bash
# Create the role
aws iam create-role \
  --role-name GitHubActionsLiquibaseRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for GitHub Actions to access Liquibase database credentials"

# Attach permissions
aws iam put-role-policy \
  --role-name GitHubActionsLiquibaseRole \
  --policy-name LiquibaseSecretsAccess \
  --policy-document file://permissions-policy.json

# Get the role ARN (save this for GitHub configuration)
aws iam get-role \
  --role-name GitHubActionsLiquibaseRole \
  --query 'Role.Arn' \
  --output text
```

## 3. Create AWS Secrets Manager Secrets

### Database Credentials Secret

Create the main database credentials secret:

```bash
aws secretsmanager create-secret \
  --name "liquibase-databases" \
  --description "Database credentials for Liquibase deployments" \
  --secret-string '{
    "postgres-prod-myappdb": {
      "type": "postgresql",
      "url": "jdbc:postgresql://your-rds-endpoint:5432/myappdb",
      "username": "postgres_user",
      "password": "your-postgres-password"
    },
    "postgres-prod-userdb": {
      "type": "postgresql",
      "url": "jdbc:postgresql://your-rds-endpoint:5432/userdb",
      "username": "postgres_user",
      "password": "your-postgres-password"
    },
    "mysql-ecommerce": {
      "type": "mysql",
      "url": "jdbc:mysql://your-mysql-endpoint:3306/ecommerce",
      "username": "mysql_user",
      "password": "your-mysql-password"
    },
    "sqlserver-inventory": {
      "type": "sqlserver",
      "url": "jdbc:sqlserver://your-sqlserver-endpoint:1433;databaseName=inventory",
      "username": "sqlserver_user",
      "password": "your-sqlserver-password"
    },
    "oracle-finance": {
      "type": "oracle",
      "url": "jdbc:oracle:thin:@your-oracle-endpoint:1521:ORCL",
      "username": "oracle_user",
      "password": "your-oracle-password"
    }
  }'
```

### User Passwords Secret

Create the user passwords secret for database user creation:

```bash
aws secretsmanager create-secret \
  --name "liquibase-users" \
  --description "Database user passwords for Liquibase user creation" \
  --secret-string '{
    "finance_app": "SecureFinancePassword123!",
    "finance_readonly": "ReadOnlyFinancePass456!",
    "mysql_app_user": "MySQLAppPassword789!",
    "mysql_report_user": "MySQLReportPassword012!",
    "sqlserver_app_user": "SQLServerAppPass345!",
    "sqlserver_report_user": "SQLServerReportPass678!"
  }'
```

## 4. Configure GitHub Repository Variables

Go to your GitHub repository **Settings > Secrets and variables > Actions > Variables** and add:

- `AWS_ROLE_ARN`: The ARN from step 3 above
- `AWS_REGION`: Your AWS region (e.g., `us-east-1`)
- `SECRET_NAME`: `liquibase-databases` (optional, this is the default)
- `USER_SECRET_NAME`: `liquibase-users` (optional, this is the default)

## 5. Update Database URLs

Replace the example URLs in the secrets with your actual database endpoints:

```bash
# Get your actual database endpoints
aws rds describe-db-instances --query 'DBInstances[].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address}'

# Update the secret with real endpoints
aws secretsmanager update-secret \
  --secret-id "liquibase-databases" \
  --secret-string '{
    "postgres-prod-myappdb": {
      "type": "postgresql",
      "url": "jdbc:postgresql://your-actual-rds-endpoint:5432/myappdb",
      "username": "postgres_user",
      "password": "your-actual-password"
    }
  }'
```

## 6. Test the Setup

Create a test branch to verify the pipeline works:

```bash
git checkout -b test/aws-setup
git push origin test/aws-setup
```

The pipeline should:
- Discover all databases from changelog files
- Run in test mode (no AWS credentials needed for validation)
- Generate SQL previews for all platforms

## Security Features

- ✅ **OIDC Authentication**: No long-lived AWS keys stored in GitHub
- ✅ **Least Privilege**: IAM role has minimal required permissions
- ✅ **Password Masking**: Passwords automatically masked in GitHub Actions logs
- ✅ **Secure Storage**: All credentials stored in AWS Secrets Manager
- ✅ **Temporary Files**: Credential files automatically cleaned up

## Troubleshooting

**"Secret value can't be converted to key name and value pairs"**
- Your JSON format is invalid in Secrets Manager
- Use "Plaintext" tab in AWS Console, not "Key/value pairs"
- Validate JSON format before uploading

**"Permission denied on Secrets Manager"**
- Verify the IAM role ARN in GitHub variables
- Check the permission policy includes correct secret ARNs

**"Context access might be invalid" warnings**
- These are VS Code warnings and don't affect functionality
- The variables are correctly referenced in the workflow

## Adding New Databases

To add a new database, update the existing secret:

```bash
# Get current secret
current=$(aws secretsmanager get-secret-value --secret-id liquibase-databases --query SecretString --output text)

# Add new database using jq
updated=$(echo "$current" | jq '. + {
  "new-database": {
    "type": "postgresql",
    "url": "jdbc:postgresql://new-endpoint:5432/newdb",
    "username": "new_user",
    "password": "new_password"
  }
}')

# Update the secret
aws secretsmanager update-secret \
  --secret-id "liquibase-databases" \
  --secret-string "$updated"
```

That's it! Your AWS setup is complete and ready for secure database deployments.