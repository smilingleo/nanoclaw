#!/bin/bash
# Linux-compatible AWS credential export for NanoClaw containers.
# Adapted from host-side script for GNU date and container paths.

PROFILE="${OKTA_PROFILE:-dev}"

# Generate okta-aws-login config.properties from env vars if not already present.
# Runs here (not just entrypoint.sh) so the script works when invoked directly
# by Claude Code via awsCredentialExport or for standalone testing.
if [[ -n "$OKTA_ORG" && -n "$OKTA_AWS_APP_URL" && ! -f "$HOME/.okta-config.properties" ]]; then
  cat > "$HOME/.okta-config.properties" <<EOF
[$PROFILE]
OKTA_ORG=$OKTA_ORG
OKTA_AWS_APP_URL=$OKTA_AWS_APP_URL
AWS_IAM_KEY=
AWS_IAM_SECRET=
EOF
fi

# Validate required env vars
for var in OKTA_USERNAME OKTA_PASSWORD OKTA_ROLE OKTA_TOTP_SECRET; do
  if [[ -z "${!var}" ]]; then
    echo "Error: required env var $var is not set" >&2
    exit 1
  fi
done

# Ensure mounted ~/bin tools are in PATH
export PATH="/workspace/extra/bin:$PATH"

# Java resolves user.home from /etc/passwd, not $HOME.
# Since the container runs as the host uid (not in /etc/passwd),
# we must tell Java where HOME is explicitly.
export JAVA_TOOL_OPTIONS="-Duser.home=$HOME"

# Unset all AWS environment variables
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_SECURITY_TOKEN

# Read the expiration date from cache
if [[ ! -f /tmp/aws-token-expiration.log ]]; then
  expiration_date=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
else
  expiration_date=$(cat /tmp/aws-token-expiration.log)
fi

# Check if credentials are still valid (5 minute buffer)
if [[ $(date -u -d "+5 minutes" +"%Y-%m-%dT%H:%M:%SZ") < $expiration_date ]]; then
  aws_access_key_id="$(aws configure get aws_access_key_id --profile $PROFILE)"
  aws_secret_access_key="$(aws configure get aws_secret_access_key --profile $PROFILE)"
  aws_session_token="$(aws configure get aws_session_token --profile $PROFILE)"

  if [[ -n $aws_access_key_id && -n $aws_secret_access_key && -n $aws_session_token ]]; then
    cat <<EOF
{
  "Credentials": {
    "AccessKeyId": "$aws_access_key_id",
    "SecretAccessKey": "$aws_secret_access_key",
    "SessionToken": "$aws_session_token",
    "Expiration": "$expiration_date"
  }
}
EOF
    exit 0
  fi
fi

echo "$(date) - Starting refresh aws token for claude" >> /tmp/aws-creds-process-${PROFILE}.log

# Refresh credentials via Okta
(okta-aws-login -p "$PROFILE" -usr "$OKTA_USERNAME" -psw "$OKTA_PASSWORD" -r "$OKTA_ROLE" -typ google -tok $(oathtool --totp -b "$OKTA_TOTP_SECRET") > /dev/null 2>&1)

if [[ $? -ne 0 ]]; then
  echo "Failed to get AWS credentials" >&2
  exit 1
fi

aws_access_key_id="$(aws configure get aws_access_key_id --profile $PROFILE)"
aws_secret_access_key="$(aws configure get aws_secret_access_key --profile $PROFILE)"
aws_session_token="$(aws configure get aws_session_token --profile $PROFILE)"
aws_expiration=$(date -u -d "+1 hour" +"%Y-%m-%dT%H:%M:%SZ")

echo $aws_expiration > /tmp/aws-token-expiration.log

cat <<EOF
{
  "Credentials": {
    "AccessKeyId": "$aws_access_key_id",
    "SecretAccessKey": "$aws_secret_access_key",
    "SessionToken": "$aws_session_token",
    "Expiration": "$aws_expiration"
  }
}
EOF
