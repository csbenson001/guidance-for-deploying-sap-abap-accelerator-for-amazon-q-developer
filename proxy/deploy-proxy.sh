#!/bin/bash
# SAP RFC Proxy Deployment Script
# This script builds the proxy image and deploys the CloudFormation stack

set -e

# Configuration - Update these values
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="sap-rfc-proxy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}SAP RFC Proxy Deployment${NC}"
echo "================================"

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}Checking prerequisites...${NC}"

    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI is not installed${NC}"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed${NC}"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}Error: AWS credentials not configured${NC}"
        exit 1
    fi

    echo -e "${GREEN}Prerequisites OK${NC}"
}

# Get AWS account ID
get_account_id() {
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/sap-rfc-proxy"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo "ECR Repository: ${ECR_REPO}"
}

# Deploy CloudFormation stack (creates ECR repo first)
deploy_stack() {
    echo -e "\n${YELLOW}Deploying CloudFormation stack...${NC}"

    if [ -z "$VPC_ID" ] || [ -z "$SUBNET_IDS" ] || [ -z "$SAP_HOST" ]; then
        echo -e "${RED}Error: Required parameters not set${NC}"
        echo ""
        echo "Usage: VPC_ID=vpc-xxx SUBNET_IDS=subnet-xxx,subnet-yyy SAP_HOST=sap.example.com ./deploy-proxy.sh"
        echo ""
        echo "Required environment variables:"
        echo "  VPC_ID       - VPC ID where proxy will be deployed"
        echo "  SUBNET_IDS   - Comma-separated subnet IDs (public subnets with SAP access)"
        echo "  SAP_HOST     - SAP system hostname"
        echo ""
        echo "Optional environment variables:"
        echo "  SAP_PORT     - SAP RFC port (default: 3300)"
        echo "  ALLOWED_CIDR - CIDR allowed to connect (default: 0.0.0.0/0)"
        echo "  AWS_REGION   - AWS region (default: us-east-1)"
        exit 1
    fi

    SAP_PORT="${SAP_PORT:-3300}"
    ALLOWED_CIDR="${ALLOWED_CIDR:-0.0.0.0/0}"

    aws cloudformation deploy \
        --stack-name "${STACK_NAME}" \
        --template-file "$(dirname "$0")/cloudformation-ecs-proxy.yaml" \
        --parameter-overrides \
            VpcId="${VPC_ID}" \
            SubnetIds="${SUBNET_IDS}" \
            SAPTargetHost="${SAP_HOST}" \
            SAPTargetPort="${SAP_PORT}" \
            AllowedCIDR="${ALLOWED_CIDR}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "${AWS_REGION}"

    echo -e "${GREEN}CloudFormation stack deployed${NC}"
}

# Build and push Docker image
build_and_push() {
    echo -e "\n${YELLOW}Building Docker image...${NC}"

    cd "$(dirname "$0")"
    docker build --platform linux/amd64 -t sap-rfc-proxy:latest .

    echo -e "\n${YELLOW}Logging in to ECR...${NC}"
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    echo -e "\n${YELLOW}Pushing image to ECR...${NC}"
    docker tag sap-rfc-proxy:latest "${ECR_REPO}:latest"
    docker push "${ECR_REPO}:latest"

    echo -e "${GREEN}Image pushed successfully${NC}"
}

# Update ECS service to use new image
update_service() {
    echo -e "\n${YELLOW}Updating ECS service...${NC}"

    aws ecs update-service \
        --cluster sap-rfc-proxy-cluster \
        --service sap-rfc-proxy-service \
        --force-new-deployment \
        --region "${AWS_REGION}" > /dev/null

    echo -e "${GREEN}ECS service updated${NC}"
}

# Get outputs
get_outputs() {
    echo -e "\n${YELLOW}Getting stack outputs...${NC}"

    PROXY_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --query "Stacks[0].Outputs[?OutputKey=='ProxyEndpoint'].OutputValue" \
        --output text \
        --region "${AWS_REGION}")

    PROXY_PORT=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --query "Stacks[0].Outputs[?OutputKey=='ProxyPort'].OutputValue" \
        --output text \
        --region "${AWS_REGION}")

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Proxy Endpoint: ${PROXY_ENDPOINT}"
    echo "Proxy Port: ${PROXY_PORT}"
    echo ""
    echo -e "${YELLOW}Update your MCP configuration:${NC}"
    echo ""
    echo "  SAP_HOST=${PROXY_ENDPOINT}"
    echo ""
    echo -e "${YELLOW}Example Docker command:${NC}"
    echo ""
    echo "  docker run --rm -i --platform linux/amd64 \\"
    echo "    --mount type=bind,source=/path/to/secrets,target=/run/secrets,readonly \\"
    echo "    -e SAP_HOST=${PROXY_ENDPOINT} \\"
    echo "    -e SAP_CLIENT=100 \\"
    echo "    -e SAP_USERNAME=your_username \\"
    echo "    abap-accelerator-q-3.2.1-node22 \\"
    echo "    node dist/index.js"
}

# Main
check_prerequisites
get_account_id
deploy_stack
build_and_push
update_service
get_outputs
