# AWS Setup for Multi-Database Liquibase CI/CD

## 1. Create IAM Role for GitHub Actions (OIDC)

Create an IAM role that GitHub Actions can assume using OpenID Connect. This is more secure than using long-lived access keys.

### Option A: Using AWS CLI (Recommended)

Follow these exact steps to create the role with CLI commands:

#### Step 1: Create Trust Policy File

Create a file called `trust-policy.json` (replace `YOUR_ACCOUNT_ID`, `YOUR_GITHUB_USERNAME` and `YOUR_REPO_NAME`):

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
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/feature/*",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/hotfix/*",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:pull_request"
          ]
        }
      }
    }
  ]
}
```

> **Security Note**: This trust policy now restricts access to specific branch patterns instead of using a wildcard (*). This follows AWS security best practices by limiting which GitHub Actions can assume the role to:
>
> - Main branch deployments (`ref:refs/heads/main`)
> - Feature branches (`ref:refs/heads/feature/*`)
> - Hotfix branches (`ref:refs/heads/hotfix/*`)
> - Pull request validations (`pull_request`)

#### Step 2: Create the IAM Role

```bash
# Create the IAM role with the trust policy
aws iam create-role \
  --role-name GitHubActionsLiquibaseRole \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role for GitHub Actions to access Liquibase database credentials"
```

#### Step 3: Create Permission Policy File

Create a file called `permissions-policy.json`:

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
        "arn:aws:secretsmanager:*:*:secret:liquibase-databases-*"
      ]
    }
  ]
}
```

#### Step 4: Attach the Permission Policy to the Role

```bash
# Attach the permission policy to the role
aws iam put-role-policy \
  --role-name GitHubActionsLiquibaseRole \
  --policy-name LiquibaseSecretsAccess \
  --policy-document file://permissions-policy.json
```

#### Step 5: Get the Role ARN (save this for GitHub configuration)

```bash
# Get the role ARN - you'll need this for GitHub repository variables
aws iam get-role \
  --role-name GitHubActionsLiquibaseRole \
  --query 'Role.Arn' \
  --output text
```

Copy the ARN output - it will look like: `arn:aws:iam::123456789012:role/GitHubActionsLiquibaseRole`

### Option B: Using AWS Console (Alternative)

If you prefer using the AWS Console:

1. **Go to IAM Console** → Roles → Create role
2. **Select trusted entity**: Web identity
3. **Identity provider**: token.actions.githubusercontent.com
4. **Audience**: sts.amazonaws.com
5. **GitHub organization**: YOUR_GITHUB_USERNAME
6. **GitHub repository**: YOUR_REPO_NAME
7. **GitHub branch**: main (you can add more branches later)
8. **Next** → Skip adding permissions for now
9. **Role name**: GitHubActionsLiquibaseRole
10. **Create role**
11. **Go back to the role** → Trust relationships → Edit trust policy
12. **Replace the policy** with the JSON from Step 1 above
13. **Add permissions** → Create inline policy → JSON → paste the permissions policy JSON
14. **Policy name**: LiquibaseSecretsAccess
15. **Create policy**

## 2. Set up GitHub OIDC Provider (if not already exists)

The GitHub OIDC provider allows GitHub Actions to authenticate with AWS without storing long-lived credentials. Most AWS accounts don't have this provider by default, so you'll likely need to create it.

### Check if OIDC Provider Already Exists

First, check if your AWS account already has the GitHub OIDC provider:

```bash
# Check for existing GitHub OIDC provider
aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `token.actions.githubusercontent.com`)]'
```

If this returns an empty list `[]`, you need to create the provider.

### Option A: Create OIDC Provider with AWS CLI

```bash
# Create the GitHub OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Option B: Create OIDC Provider via AWS Console

1. **Go to IAM Console** → Identity providers → Add provider
2. **Provider type**: OpenID Connect
3. **Provider URL**: `https://token.actions.githubusercontent.com`
4. **Audience**: `sts.amazonaws.com`
5. **Add provider**

### OIDC Provider Settings Explained

- **Provider URL**: `https://token.actions.githubusercontent.com`
  - This is GitHub's OIDC endpoint that issues tokens for GitHub Actions
- **Audience**: `sts.amazonaws.com`
  - This specifies that the tokens are intended for AWS STS (Security Token Service)
- **Thumbprint**: `6938fd4d98bab03faadb97b34396831e3780aea1`
  - This is the SSL certificate thumbprint for GitHub's OIDC provider (GitHub manages this)

### Verify OIDC Provider Creation

After creating the provider, verify it was created successfully:

```bash
# Verify the OIDC provider exists
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID.

### Common OIDC Provider Issues

- **Provider already exists**: If you get an error that the provider already exists, skip this step and proceed to create the IAM role
- **Thumbprint verification**: The thumbprint `6938fd4d98bab03faadb97b34396831e3780aea1` is current as of 2024. If GitHub updates their certificates, you may need to update this value
- **Multiple audiences**: If you need to add more audiences later, you can update the provider to include additional client IDs

## 3. Create Single Consolidated Secret in AWS Secrets Manager

Create one secret in AWS Secrets Manager containing all database configurations:

### Secret Structure

The secret should be stored as JSON with all databases in a single object. Each database entry supports multiple database types:

```json
{
  "postgres-prod": {
    "type": "postgresql",
    "url": "jdbc:postgresql://postgres-prod.company.com:5432/userdb",
    "username": "postgres_user",
    "password": "secure_postgres_password"
  },
  "mysql-prod": {
    "type": "mysql",
    "url": "jdbc:mysql://mysql-prod.company.com:3306/ecommerce?useSSL=true&serverTimezone=UTC",
    "username": "mysql_user",
    "password": "secure_mysql_password"
  },
  "sqlserver-prod": {
    "type": "sqlserver",
    "url": "jdbc:sqlserver://sqlserver-prod.company.com:1433;databaseName=reporting;encrypt=true",
    "username": "sqlserver_user",
    "password": "secure_sqlserver_password"
  },
  "oracle-prod": {
    "type": "oracle",
    "url": "jdbc:oracle:thin:@oracle-prod.company.com:1521:LEGACY",
    "username": "oracle_user",
    "password": "secure_oracle_password"
  }
}
```

### Supported Database Types

| Type | Driver | Notes |
|------|--------|-------|
| `postgresql` | PostgreSQL JDBC Driver | Auto-downloaded |
| `mysql` | MySQL Connector/J | Auto-downloaded |
| `sqlserver` | Microsoft SQL Server JDBC Driver | Auto-downloaded |
| `oracle` | Oracle JDBC Driver | Requires manual setup (license) |

### Database Type Detection

The `type` field is optional - the pipeline can auto-detect database type from the JDBC URL:

- URLs containing `postgresql` → `postgresql`
- URLs containing `mysql` → `mysql`
- URLs containing `sqlserver` or `mssql` → `sqlserver`
- URLs containing `oracle` → `oracle`

If auto-detection fails, specify the `type` field explicitly.

### Secret Name

Default: `liquibase-databases` (configurable via GitHub variable `SECRET_NAME`)

### Creating the Secret via AWS CLI

```bash
# Create the consolidated secret with multi-database support
aws secretsmanager create-secret \
  --name "liquibase-databases" \
  --description "All Liquibase database credentials" \
  --secret-string '{
    "postgres-prod": {
      "type": "postgresql",
      "url": "jdbc:postgresql://postgres-prod.company.com:5432/userdb",
      "username": "postgres_user",
      "password": "secure_postgres_password"
    },
    "mysql-prod": {
      "type": "mysql",
      "url": "jdbc:mysql://mysql-prod.company.com:3306/ecommerce?useSSL=true&serverTimezone=UTC",
      "username": "mysql_user",
      "password": "secure_mysql_password"
    },
    "sqlserver-prod": {
      "type": "sqlserver",
      "url": "jdbc:sqlserver://sqlserver-prod.company.com:1433;databaseName=reporting;encrypt=true",
      "username": "sqlserver_user",
      "password": "secure_sqlserver_password"
    },
    "oracle-prod": {
      "type": "oracle",
      "url": "jdbc:oracle:thin:@oracle-prod.company.com:1521:LEGACY",
      "username": "oracle_user",
      "password": "secure_oracle_password"
    }
  }'

# Or create from a JSON file (recommended)
aws secretsmanager create-secret \
  --name "liquibase-databases" \
  --description "All Liquibase database credentials" \
  --secret-string file://database-credentials-example.json
```

### Oracle Driver Setup

Oracle JDBC drivers require license agreement and cannot be auto-downloaded. For Oracle databases:

1. Download the Oracle JDBC driver manually from Oracle website
2. Add to your workflow as a custom step, or
3. Use a private Maven repository with the driver

Example custom Oracle driver step:

```yaml
- name: Download Oracle driver
  if: contains(matrix.database, 'oracle')
  run: |
    # Download from your private repository or artifact store
    wget -q https://your-repo.com/drivers/ojdbc11.jar -O drivers/oracle.jar
```

### Adding New Databases

To add a new database, update the existing secret:

```bash
# Get current secret
CURRENT_SECRET=$(aws secretsmanager get-secret-value --secret-id "liquibase-databases" --query SecretString --output text)

# Add new database (using jq)
NEW_SECRET=$(echo "$CURRENT_SECRET" | jq '. + {
  "newdb": {
    "type": "mysql",
    "url": "jdbc:mysql://newdb.example.com:3306/newdatabase",
    "username": "newdb_user",
    "password": "new_secure_password"
  }
}')

# Update the secret
aws secretsmanager update-secret \
  --secret-id "liquibase-databases" \
  --secret-string "$NEW_SECRET"
```

## 4. GitHub Repository Configuration

### Repository Variables

Add these variables to your GitHub repository (Settings > Secrets and variables > Actions > Variables):

- `AWS_ROLE_ARN`: The ARN of the IAM role created above
- `AWS_REGION`: AWS region (e.g., us-east-1)
- `SECRET_NAME`: Name of the consolidated secret (defaults to 'liquibase-databases')

### No GitHub Secrets Required

All database credentials are now stored securely in AWS Secrets Manager. No GitHub secrets are needed for database access.

## 5. Security Features

- **Password Masking**: Passwords are automatically masked in GitHub Actions logs
- **Temporary Files**: Credential files are automatically cleaned up after use
- **Log Sanitization**: Any password leaks in Liquibase logs are automatically redacted
- **Least Privilege**: IAM role has minimal required permissions
- **OIDC Authentication**: No long-lived AWS keys stored in GitHub

## 6. Step-by-Step Setup Guide

### Step 1: Create Policy Files

Create `trust-policy.json`:

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
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/feature/*",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:ref:refs/heads/hotfix/*",
            "repo:YOUR_GITHUB_USERNAME/YOUR_REPO_NAME:pull_request"
          ]
        }
      }
    }
  ]
}
```

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
        "arn:aws:secretsmanager:*:*:secret:liquibase-databases-*"
      ]
    }
  ]
}
```

### Step 2: Execute Setup Commands

```bash
# 1. Create OIDC provider (if not exists)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2. Create the IAM role
aws iam create-role \
  --role-name GitHubActionsLiquibaseRole \
  --assume-role-policy-document file://trust-policy.json

# 3. Attach the permission policy
aws iam put-role-policy \
  --role-name GitHubActionsLiquibaseRole \
  --policy-name LiquibaseSecretsAccess \
  --policy-document file://permissions-policy.json

# 4. Create the secrets (update URLs and credentials for your environment)
aws secretsmanager create-secret \
  --name "liquibase-databases" \
  --description "All Liquibase database credentials" \
  --secret-string file://database-credentials-example.json

# 5. Get the role ARN for GitHub configuration
aws iam get-role --role-name GitHubActionsLiquibaseRole --query 'Role.Arn' --output text
```

### Step 3: Configure GitHub Repository

1. Go to your GitHub repository
2. Navigate to **Settings > Secrets and variables > Actions**
3. Click **Variables** tab
4. Add these repository variables:
   - `AWS_ROLE_ARN`: The ARN from step 5 above
   - `AWS_REGION`: Your AWS region (e.g., `us-east-1`)
   - `SECRET_NAME`: `liquibase-databases` (optional, this is the default)

### Step 4: Test the Setup

Create a test branch and push to trigger the pipeline:

```bash
git checkout -b test/pipeline-setup
git push origin test/pipeline-setup
```

The pipeline should:

- ✅ Discover all 4 databases
- ✅ Download drivers automatically
- ✅ Run in test mode (no AWS credentials needed)
- ✅ Generate SQL previews for all platforms

## 7. Troubleshooting

### Common Issues

1. **"Context access might be invalid" warnings**
   - These are VS Code warnings and don't affect functionality
   - The variables are correctly referenced in the workflow

2. **Oracle driver not found**
   - Add custom Oracle driver download step to workflow
   - Or remove Oracle database from your setup

3. **OIDC provider already exists**
   - Skip the OIDC provider creation step
   - Use existing provider

4. **Permission denied on Secrets Manager**
   - Verify the IAM role ARN in GitHub variables
   - Check the permission policy includes correct secret ARN

### Verification Commands

```bash
# Test AWS CLI access
aws sts get-caller-identity

# List secrets
aws secretsmanager list-secrets --query 'SecretList[?Name==`liquibase-databases`]'

# Test secret access
aws secretsmanager get-secret-value --secret-id liquibase-databases --query SecretString

# Verify IAM role
aws iam get-role --role-name GitHubActionsLiquibaseRole
```

## 8. Production Checklist

Before deploying to production:

- [ ] Replace example URLs with actual database endpoints
- [ ] Use strong, unique passwords for each database
- [ ] Test connectivity from GitHub Actions to your databases
- [ ] Verify backup procedures are in place
- [ ] Review and approve all changesets before merging to main
- [ ] Set up monitoring for failed deployments
- [ ] Document rollback procedures
- [ ] Train team on the new pipeline
