#!/bin/bash
set -e

# Create ~/.claude/settings.json with awsCredentialExport if not already provided
# (in NanoClaw usage this file is mounted from the host; this covers standalone runs)
SETTINGS_FILE="$HOME/.claude/settings.json"
if [[ ! -f "$SETTINGS_FILE" ]]; then
  mkdir -p "$HOME/.claude"
  cat > "$SETTINGS_FILE" <<'EOF'
{
  "awsCredentialExport": "/usr/local/bin/aws-auth-token-exporter.sh",
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD": "1",
    "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "0"
  }
}
EOF
fi

# Run AWS credential export if configured
if [[ -n "$AWS_CREDENTIAL_EXPORT" && -x "$AWS_CREDENTIAL_EXPORT" ]]; then
  creds=$("$AWS_CREDENTIAL_EXPORT") && {
    export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r '.Credentials.AccessKeyId // empty')
    export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r '.Credentials.SecretAccessKey // empty')
    export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r '.Credentials.SessionToken // empty')
  } || echo "Warning: AWS credential export failed" >&2
fi

if [[ "$CLAUDE_DIRECT" == "1" ]]; then
  # Direct mode: launch Claude interactively, bypassing the agent-runner
  exec claude "$@"
else
  # Agent-runner mode: compile TypeScript, read JSON prompt from stdin, run agent
  cd /app && npx tsc --outDir /tmp/dist 2>&1 >&2
  ln -s /app/node_modules /tmp/dist/node_modules
  chmod -R a-w /tmp/dist
  cat > /tmp/input.json
  node /tmp/dist/index.js < /tmp/input.json
fi
