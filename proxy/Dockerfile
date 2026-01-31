# SAP RFC TCP Proxy for ECS Fargate
# This container forwards TCP traffic to your SAP system
# Allows local Docker containers to connect to SAP through AWS

FROM alpine:3.19

RUN apk add --no-cache socat

# Default SAP RFC port (3300 for system 00, 3301 for 01, etc.)
ENV SAP_TARGET_HOST=""
ENV SAP_TARGET_PORT="3300"
ENV LISTEN_PORT="3300"

# Health check for ECS
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD pgrep socat || exit 1

EXPOSE ${LISTEN_PORT}

# Forward TCP traffic from LISTEN_PORT to SAP_TARGET_HOST:SAP_TARGET_PORT
CMD socat TCP-LISTEN:${LISTEN_PORT},fork,reuseaddr TCP:${SAP_TARGET_HOST}:${SAP_TARGET_PORT}
