# NanoClaw Agent Container
# Runs Claude Agent SDK in isolated Linux VM with browser automation

FROM node:22-alpine

# Install system dependencies
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    font-noto \
    bash \
    curl \
    git \
    jq \
    aws-cli \
    coreutils \
    oath-toolkit-oathtool \
    openjdk17-jre-headless

# Install Zscaler root CA so HTTPS traffic through the Zscaler proxy is trusted
COPY zscaler-root-ca.crt /usr/local/share/ca-certificates/zscaler-root-ca.crt
RUN update-ca-certificates

# Tell Node.js to trust the updated system CA bundle (includes Zscaler)
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# AWS Bedrock configuration
ENV CLAUDE_CODE_USE_BEDROCK=1
ENV ANTHROPIC_MODEL=us.anthropic.claude-sonnet-4-6
ENV ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-6
ENV ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-4-6-v1
ENV AWS_REGION=us-west-2

# Okta defaults (override at runtime for a different org/role)
ENV OKTA_ROLE=fed/hum/eng/eng-std-general-SAML-Role
ENV OKTA_ORG=zuora.okta.com
ENV OKTA_AWS_APP_URL=https://zuora.okta.com/home/amazon_aws/0oa1bnkg58zmE2QT11d8/272

# Set Chromium path for agent-browser
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium

# Install agent-browser and claude-code globally
RUN npm install -g agent-browser @anthropic-ai/claude-code

# Create app directory
WORKDIR /app

# Copy package files first for better caching
COPY agent-runner/package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY agent-runner/ ./

# Build TypeScript
RUN npm run build

# Create workspace directories
RUN mkdir -p /workspace/group /workspace/global /workspace/extra /workspace/ipc/messages /workspace/ipc/tasks /workspace/ipc/input

# Copy AWS credential exporter and okta-aws-login (Linux-compatible, used by entrypoint when CLAUDE_CODE_USE_BEDROCK=1)
COPY aws-auth-token-exporter.sh /usr/local/bin/aws-auth-token-exporter.sh
COPY okta-aws-login /usr/local/bin/okta-aws-login
RUN chmod +x /usr/local/bin/aws-auth-token-exporter.sh /usr/local/bin/okta-aws-login


# Copy entrypoint script
# Container input (prompt, group info) is passed via stdin JSON.
# AWS credentials are exported by aws-auth-token-exporter.sh via AWS_CREDENTIAL_EXPORT env var.
# Follow-up messages arrive via IPC files in /workspace/ipc/input/
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set ownership to node user (non-root) for writable directories
RUN chown -R node:node /workspace && chmod 777 /home/node

# Switch to non-root user (required for --dangerously-skip-permissions)
USER node

# Set working directory to group workspace
WORKDIR /workspace/group

# Entry point reads JSON from stdin, outputs JSON to stdout
ENTRYPOINT ["/app/entrypoint.sh"]
