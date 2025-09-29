#!/bin/bash

# Deploy AWS infrastructure for automated database cost management
# This script deploys a Lambda function that automatically stops RDS databases

set -e

STACK_NAME="database-cost-management"
TEMPLATE_FILE="cloudformation/database-cost-management.yaml"
REGION=${AWS_DEFAULT_REGION:-us-east-1}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying Database Cost Management Infrastructure${NC}"
echo -e "${BLUE}Region: ${REGION}${NC}"
echo -e "${BLUE}Stack: ${STACK_NAME}${NC}"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}❌ AWS CLI not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}❌ CloudFormation template not found: $TEMPLATE_FILE${NC}"
    exit 1
fi

# Validate CloudFormation template
echo -e "${YELLOW}📋 Validating CloudFormation template...${NC}"
if aws cloudformation validate-template --template-body file://$TEMPLATE_FILE >/dev/null; then
    echo -e "${GREEN}✅ Template validation successful${NC}"
else
    echo -e "${RED}❌ Template validation failed${NC}"
    exit 1
fi

# Check if stack already exists
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>/dev/null || echo "false")

if [ "$STACK_EXISTS" != "false" ]; then
    echo -e "${YELLOW}🔄 Stack exists. Updating...${NC}"
    OPERATION="update-stack"
    OPERATION_NAME="Update"
else
    echo -e "${YELLOW}🆕 Creating new stack...${NC}"
    OPERATION="create-stack"
    OPERATION_NAME="Create"
fi

# Deploy the stack
echo -e "${YELLOW}🔧 ${OPERATION_NAME}ing CloudFormation stack...${NC}"

STACK_ID=$(aws cloudformation $OPERATION \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION \
    --parameters \
        ParameterKey=ScheduleExpression,ParameterValue="rate(30 minutes)" \
        ParameterKey=FunctionName,ParameterValue="rds-database-stopper" \
    --query 'StackId' --output text 2>/dev/null || true)

if [ -z "$STACK_ID" ] && [ "$OPERATION" = "update-stack" ]; then
    echo -e "${YELLOW}ℹ️ No updates required${NC}"
    STACK_ID=$STACK_NAME
else
    echo -e "${GREEN}📤 Stack operation initiated: $STACK_ID${NC}"
fi

# Wait for stack operation to complete
echo -e "${YELLOW}⏳ Waiting for stack operation to complete...${NC}"

if [ "$OPERATION" = "create-stack" ]; then
    WAIT_CONDITION="stack-create-complete"
else
    WAIT_CONDITION="stack-update-complete"
fi

if aws cloudformation wait $WAIT_CONDITION --stack-name $STACK_NAME --region $REGION; then
    echo -e "${GREEN}✅ Stack operation completed successfully${NC}"
else
    echo -e "${RED}❌ Stack operation failed${NC}"
    echo "Check CloudFormation console for details:"
    echo "https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks/stackinfo?stackId=$STACK_NAME"
    exit 1
fi

# Get stack outputs
echo ""
echo -e "${BLUE}📊 Stack Outputs:${NC}"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

echo ""
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo ""
echo -e "${BLUE}💡 What happens next:${NC}"
echo "• Lambda function will run every 30 minutes to check for running databases"
echo "• Databases will be stopped automatically unless they have protective tags:"
echo "  - Environment=production"
echo "  - AutoStop=false"
echo "  - Persistent=true"
echo "  - Names containing 'prod' are also protected"
echo ""
echo -e "${BLUE}🔍 Monitor the function:${NC}"
echo "• CloudWatch Logs: /aws/lambda/rds-database-stopper"
echo "• Lambda Console: https://console.aws.amazon.com/lambda/home?region=$REGION#/functions/rds-database-stopper"
echo ""
echo -e "${YELLOW}⚠️ Important: Test this with non-production databases first!${NC}"