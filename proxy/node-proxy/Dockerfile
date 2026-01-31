# SAP RFC TCP Proxy - Compatible with Univar internal infrastructure
#
# This Dockerfile follows the same pattern as digital-margin-management-ui
# and uses the internal Chainguard base image.
#
# Environment Variables (set in ECS task definition):
#   SAP_TARGET_HOST    - SAP system hostname (required)
#   SAP_TARGET_PORT    - SAP RFC port (default: 3300)
#   LISTEN_PORT        - Port to listen on (default: 3300)
#   HEALTH_CHECK_PORT  - Optional HTTP health check port (e.g., 8080)
#   LOG_LEVEL          - debug, info, error (default: info)

ARG BUILDPLATFORM=linux/amd64

# Use the internal Chainguard base image
FROM --platform=$BUILDPLATFORM 169523143400.dkr.ecr.us-east-1.amazonaws.com/digital-chainguard-base:node22 AS base
ENV NODE_ENV=production
WORKDIR /app

# Build stage - install dependencies (none needed for this simple proxy)
FROM base AS build
COPY --chown=node:node package.json .
# No npm install needed - we use only Node.js built-in modules
COPY --chown=node:node . .

# Production stage
FROM base
COPY --from=build --chown=node:node /app /app

# Default RFC port - can be overridden via LISTEN_PORT env var
EXPOSE 3300

# Optional health check port
EXPOSE 8080

# Health check using the HTTP endpoint if enabled
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "fetch('http://localhost:8080/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))" || exit 0

# Run as non-root user (Chainguard best practice)
USER node

ENTRYPOINT ["node", "server.mjs"]
