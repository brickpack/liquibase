# AWS Database Cost Management

Automated solution to keep RDS databases stopped when not in use, reducing AWS costs.

## Overview

This solution deploys a Lambda function that runs on a schedule (every 30 minutes by default) to automatically stop running RDS databases. It includes safety mechanisms to protect production databases.

## Files

- `lambda/stop-databases.py` - Lambda function code
- `cloudformation/database-cost-management.yaml` - Infrastructure as code
- `deploy-database-cost-management.sh` - Deployment script

## Quick Start

1. Ensure AWS CLI is configured:
   ```bash
   aws configure
   ```

2. Deploy the infrastructure:
   ```bash
   cd aws
   ./deploy-database-cost-management.sh
   ```

## Database Protection

The Lambda function will **NOT** stop databases that have:

- `Environment=production` tag
- `AutoStop=false` tag
- `Persistent=true` tag
- Names containing "prod"

## Customization

Edit the CloudFormation parameters in `deploy-database-cost-management.sh`:

- **Schedule**: Change `rate(30 minutes)` to `cron(0 22 * * ? *)` (10 PM daily)
- **Function Name**: Customize the Lambda function name

## Monitoring

- **CloudWatch Logs**: `/aws/lambda/rds-database-stopper`
- **Lambda Console**: AWS Console → Lambda → rds-database-stopper

## Cost Savings

RDS instances are charged by the hour when running. This automation can save significant costs for:
- Development databases
- Testing environments
- Staging databases used intermittently

## Safety

- Only stops databases in "available" state
- Skips databases already stopped/stopping
- Comprehensive error handling and logging
- Respects database tags for protection