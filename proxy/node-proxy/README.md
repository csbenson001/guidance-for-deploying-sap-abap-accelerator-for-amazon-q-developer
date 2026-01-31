# SAP RFC Proxy - Node.js Version

A Node.js TCP proxy for SAP RFC connections, designed to work with **restricted AWS environments** that require specific base images and shared deployment workflows.

## Why This Version?

If your organization:
- Requires specific base images (e.g., Chainguard from internal ECR)
- Uses shared GitHub workflows for deployments
- Cannot create custom ECS task definitions
- Has restricted access to AWS infrastructure

This Node.js proxy follows the same patterns as your existing applications (like `digital-margin-management-ui`).

## Architecture

```
┌─────────────────────┐                    ┌─────────────────────┐                    ┌────────────┐
│  Your Mac (Docker)  │      TCP/RFC       │   ECS Fargate       │      TCP/RFC       │    SAP     │
│  ABAP Accelerator   │  ───────────────►  │   Node.js Proxy     │  ───────────────►  │   System   │
└─────────────────────┘     via NLB        │   (this service)    │    Internal VPC    └────────────┘
                                           └─────────────────────┘
```

## Project Structure

```
node-proxy/
├── server.mjs              # TCP proxy server (Node.js built-in modules only)
├── package.json            # Project configuration
├── Dockerfile              # Production build (uses Chainguard base)
├── Dockerfile.local        # Local testing (uses node:22-alpine)
└── .github/
    └── workflows/
        └── deploy-dev.yml  # GitHub Actions workflow
```

## Local Testing

### 1. Build the Local Image

```bash
cd proxy/node-proxy
docker build -f Dockerfile.local -t sap-rfc-proxy:local .
```

### 2. Test the Proxy

```bash
# Start the proxy (replace with your SAP host)
docker run --rm -it \
  -e SAP_TARGET_HOST=your-sap-system.company.com \
  -e SAP_TARGET_PORT=3300 \
  -e LISTEN_PORT=3300 \
  -e HEALTH_CHECK_PORT=8080 \
  -e LOG_LEVEL=debug \
  -p 3300:3300 \
  -p 8080:8080 \
  sap-rfc-proxy:local
```

### 3. Test Health Check

```bash
curl http://localhost:8080/health
# Returns: {"status":"healthy","connections":0,"target":"your-sap-system:3300"}
```

## Deployment to ECS

### Prerequisites

Before deploying, you need your DevOps/Platform team to:

1. **Create the ECS Task Definition**: `sap-rfc-proxy-dev`
2. **Configure environment variables** in the task definition
3. **Set up a Network Load Balancer (NLB)** to expose port 3300
4. **Ensure VPC connectivity** - the ECS task must be able to reach your SAP system

### Required ECS Task Configuration

Ask your DevOps team to configure the task definition with:

```json
{
  "containerDefinitions": [
    {
      "name": "sap-rfc-proxy-dev",
      "portMappings": [
        {
          "containerPort": 3300,
          "hostPort": 3300,
          "protocol": "tcp"
        },
        {
          "containerPort": 8080,
          "hostPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        { "name": "SAP_TARGET_HOST", "value": "your-sap-system.company.com" },
        { "name": "SAP_TARGET_PORT", "value": "3300" },
        { "name": "LISTEN_PORT", "value": "3300" },
        { "name": "HEALTH_CHECK_PORT", "value": "8080" },
        { "name": "LOG_LEVEL", "value": "info" }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "node -e \"fetch('http://localhost:8080/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 10
      }
    }
  ]
}
```

### Load Balancer Configuration

For the NLB target group:

| Setting | Value |
|---------|-------|
| Protocol | TCP |
| Port | 3300 |
| Health check protocol | HTTP |
| Health check path | /health |
| Health check port | 8080 |

### Deploy via GitHub Actions

1. **Fork/copy this directory** to a new repository (e.g., `sap-rfc-proxy`)
2. **Push to main branch** - the workflow will trigger automatically
3. **Get the NLB DNS name** from your DevOps team

```bash
# The shared workflow will:
# 1. Build the image using your Chainguard base
# 2. Push to your internal ECR
# 3. Deploy to ECS using your standard task definition
```

## Using the Proxy

Once deployed, update your local MCP configuration to use the NLB endpoint:

### Update `~/.aws/amazonq/mcp.json`

```json
{
  "mcpServers": {
    "abap-accelerator-q": {
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

**Key change**: Replace your direct SAP hostname with the NLB DNS name.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SAP_TARGET_HOST` | Yes | - | SAP system hostname to forward traffic to |
| `SAP_TARGET_PORT` | No | 3300 | SAP RFC port (3300 for system 00, 3301 for 01, etc.) |
| `LISTEN_PORT` | No | 3300 | Port the proxy listens on |
| `HEALTH_CHECK_PORT` | No | - | If set, enables HTTP health endpoint on this port |
| `LOG_LEVEL` | No | info | Logging verbosity: debug, info, error |

## Multiple SAP Systems

To proxy multiple SAP systems, deploy multiple instances:

| Proxy Instance | SAP_TARGET_HOST | LISTEN_PORT | Use Case |
|----------------|-----------------|-------------|----------|
| sap-rfc-proxy-ecc-dev | ecc.company.com | 3300 | ECC Development |
| sap-rfc-proxy-s4-dev | s4hana.company.com | 3301 | S/4HANA Development |

Each would need its own:
- ECS task definition
- NLB target group and listener
- GitHub repository (or separate workflow)

## Troubleshooting

### Proxy not connecting to SAP

1. Check ECS task logs in CloudWatch
2. Verify SAP hostname is resolvable from the VPC
3. Ensure security groups allow outbound traffic to SAP
4. Test with `LOG_LEVEL=debug` for detailed connection info

### Health check failing

1. Ensure `HEALTH_CHECK_PORT` is set (e.g., 8080)
2. Verify port 8080 is exposed in task definition
3. Check that NLB health check targets port 8080, not 3300

### Connection timeouts from local Docker

1. Verify NLB is internet-facing
2. Check NLB security group allows inbound on port 3300
3. Ensure your IP is not blocked by WAF/ACL

### Getting the NLB DNS Name

Ask your DevOps team, or if you have AWS console access:

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'sap-rfc-proxy')].DNSName" \
  --output text
```

## Security Considerations

1. **Restrict NLB access** - Use security groups to limit who can connect
2. **Use VPC endpoints** - If SAP is in AWS, use PrivateLink
3. **Enable access logging** - Track who connects to the proxy
4. **Rotate credentials** - The proxy doesn't handle credentials, but ensure SAP passwords are rotated

## Request to DevOps Team

Copy this template when requesting infrastructure setup:

---

**Request: SAP RFC Proxy Infrastructure**

Hi team,

I need to set up a TCP proxy for SAP RFC connections to enable local ABAP Accelerator development. The proxy will run in ECS and forward TCP traffic to our SAP system.

**Required infrastructure:**

1. **ECS Task Definition**: `sap-rfc-proxy-dev`
   - Image: Will be pushed to ECR via standard workflow
   - CPU: 256, Memory: 512
   - Port mappings: 3300/tcp, 8080/tcp

2. **Environment Variables**:
   - `SAP_TARGET_HOST`: [SAP hostname - I'll provide]
   - `SAP_TARGET_PORT`: 3300
   - `LISTEN_PORT`: 3300
   - `HEALTH_CHECK_PORT`: 8080
   - `LOG_LEVEL`: info

3. **Network Load Balancer**:
   - Internet-facing (or internal if VPN provides access)
   - TCP listener on port 3300
   - Health check: HTTP on port 8080, path `/health`

4. **Security**:
   - Restrict inbound to specific IPs/CIDRs if possible
   - Allow outbound to SAP system on RFC port

**VPC Requirements**:
- The ECS task must be in a subnet that can reach [SAP hostname]

Please let me know what information you need from me.

---
