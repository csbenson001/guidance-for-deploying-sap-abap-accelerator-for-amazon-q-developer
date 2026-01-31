# SAP RFC Proxy for VPN-Restricted Environments

This solution enables you to run the ABAP Accelerator Docker container locally on your Mac while your VPN blocks direct Docker-to-SAP connections.

## Architecture

```
┌─────────────────────┐      TCP/RFC      ┌─────────────────────┐     TCP/RFC     ┌────────────┐
│  Your Mac (Docker)  │  ──────────────►  │  ECS Fargate Proxy  │  ────────────►  │    SAP     │
│  ABAP Accelerator   │     Internet      │  (in AWS VPC)       │   Private VPC   │   System   │
└─────────────────────┘                   └─────────────────────┘                 └────────────┘
         │                                          │
    VPN blocks this                          Has network access
    direct connection                        to SAP system
```

## How It Works

1. A lightweight TCP proxy container runs in AWS ECS Fargate
2. The proxy is deployed in a VPC that has network access to your SAP system
3. A Network Load Balancer provides a stable public endpoint
4. Your local Docker container connects to the NLB instead of directly to SAP
5. The proxy forwards RFC traffic to your SAP system

## Prerequisites

- AWS CLI configured with appropriate credentials
- Docker Desktop installed on your Mac
- A VPC with network access to your SAP system
- Public subnets in that VPC (for the NLB)

## Quick Start

### 1. Deploy the Proxy Infrastructure

```bash
# Set required environment variables
export VPC_ID="vpc-xxxxxxxxx"           # VPC with SAP access
export SUBNET_IDS="subnet-xxx,subnet-yyy" # Public subnets
export SAP_HOST="your-sap-system.company.com"
export SAP_PORT="3300"                   # Optional, default 3300
export AWS_REGION="us-east-1"            # Optional, default us-east-1

# Run the deployment script
./deploy-proxy.sh
```

### 2. Update Your MCP Configuration

After deployment, update your `~/.aws/amazonq/mcp.json` to use the proxy endpoint:

```json
{
  "mcpServers": {
    "abap": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i", "--platform", "linux/amd64",
        "--mount", "type=bind,source=/path/to/.secrets,target=/run/secrets,readonly",
        "-e", "SAP_HOST=sap-rfc-proxy-nlb-xxxx.elb.us-east-1.amazonaws.com",
        "-e", "SAP_CLIENT=100",
        "-e", "SAP_USERNAME=your_username",
        "-e", "SAP_LANGUAGE=EN",
        "-e", "SAP_SECURE=true",
        "abap-accelerator-q-3.2.1-node22",
        "node", "dist/index.js"
      ],
      "timeout": 60000,
      "disabled": false
    }
  }
}
```

**Note:** Replace the `SAP_HOST` value with the NLB DNS name output from the deployment.

## Manual Deployment

If you prefer to deploy manually:

### 1. Create the ECR Repository and Push the Image

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"

# Create ECR repository
aws ecr create-repository --repository-name sap-rfc-proxy

# Build the image
docker build --platform linux/amd64 -t sap-rfc-proxy:latest .

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Tag and push
docker tag sap-rfc-proxy:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/sap-rfc-proxy:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/sap-rfc-proxy:latest
```

### 2. Deploy the CloudFormation Stack

```bash
aws cloudformation deploy \
  --stack-name sap-rfc-proxy \
  --template-file cloudformation-ecs-proxy.yaml \
  --parameter-overrides \
    VpcId=vpc-xxxxxxxxx \
    SubnetIds=subnet-xxx,subnet-yyy \
    SAPTargetHost=your-sap-system.company.com \
    SAPTargetPort=3300 \
    AllowedCIDR=0.0.0.0/0 \
  --capabilities CAPABILITY_NAMED_IAM
```

### 3. Get the Proxy Endpoint

```bash
aws cloudformation describe-stacks \
  --stack-name sap-rfc-proxy \
  --query "Stacks[0].Outputs[?OutputKey=='ProxyEndpoint'].OutputValue" \
  --output text
```

## Security Considerations

### Restrict Access by IP

For production use, restrict the `AllowedCIDR` parameter to your IP address or corporate IP range:

```bash
# Find your public IP
curl ifconfig.me

# Deploy with restricted access
export ALLOWED_CIDR="203.0.113.50/32"  # Your IP
./deploy-proxy.sh
```

### Use Private Subnets with NAT Gateway

For enhanced security, you can modify the CloudFormation template to:
1. Deploy the ECS tasks in private subnets
2. Use a NAT Gateway for outbound traffic
3. Keep the NLB in public subnets

### VPC Security Groups

The CloudFormation creates a security group that:
- Allows inbound TCP traffic on the SAP port from the allowed CIDR
- Allows outbound traffic to SAP and HTTPS (for ECR pulls)

## Multiple SAP Systems

To proxy multiple SAP systems, deploy multiple stacks with different names:

```bash
# ECC System
STACK_NAME="sap-proxy-ecc" SAP_HOST="ecc.company.com" SAP_PORT="3300" ./deploy-proxy.sh

# S/4HANA System
STACK_NAME="sap-proxy-s4" SAP_HOST="s4hana.company.com" SAP_PORT="3301" ./deploy-proxy.sh
```

Then configure multiple MCP servers in your `mcp.json` using the respective NLB endpoints.

## Cost Estimate

- **ECS Fargate**: ~$10-15/month for a small task running 24/7
- **Network Load Balancer**: ~$16/month + data transfer
- **NAT Gateway** (if using private subnets): ~$32/month + data transfer
- **Data Transfer**: Minimal for RFC calls (typically KB-sized payloads)

**Tip:** Use scheduled scaling to stop the service outside work hours to reduce costs.

## Troubleshooting

### Connection Timeout

1. Check the ECS task is running:
   ```bash
   aws ecs list-tasks --cluster sap-rfc-proxy-cluster
   ```

2. Check CloudWatch logs:
   ```bash
   aws logs tail /ecs/sap-rfc-proxy --follow
   ```

3. Verify security group allows your IP

### NLB Health Check Failing

1. Verify the SAP system is reachable from the VPC
2. Check the SAP port is correct (3300 for system 00, 3301 for 01, etc.)

### DNS Resolution Issues

If your SAP hostname is internal DNS, ensure:
1. The VPC has DNS resolution enabled
2. The ECS task can resolve the SAP hostname
3. Consider using the SAP IP address directly

## Cleanup

To remove all resources:

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name sap-rfc-proxy

# Delete ECR repository (optional)
aws ecr delete-repository --repository-name sap-rfc-proxy --force
```

## Alternative: SSH Tunnel

If you have an EC2 bastion host, a simpler alternative is an SSH tunnel:

```bash
# Create SSH tunnel on your Mac
ssh -L 3300:your-sap-host.company.com:3300 ec2-user@bastion.amazonaws.com -N &

# Use host.docker.internal in your Docker config
-e SAP_HOST=host.docker.internal
```

This avoids the ECS/NLB costs but requires an existing bastion host and SSH access.
