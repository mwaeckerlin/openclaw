#!/bin/sh -e
echo "==== Setting All Secrets ===="
for secret in /run/secrets/*; do
  test -e "$secret" || continue
  varname=$(basename "$secret" | tr '[:lower:]-' '[:upper:]_')
  echo "Setting $varname from $secret"
  export "$varname=$(sed -z 's/\n/\\n/g' "$secret")"
done
echo "==== Setting SSH Authorized Key ===="
if [ -z "$OPENCLAW_SANDBOX_SSH_PRIVATE_KEY" ]; then
  echo "ERROR: No SSH private key provided for sandbox. Please set OPENCLAW_SANDBOX_SSH_PRIVATE_KEY variable or provide a secret named openclaw_sandbox_ssh_private_key." >&2
  exit 1
fi
printf '%b' "${OPENCLAW_SANDBOX_SSH_PRIVATE_KEY}" > ~/.ssh/ssh-id-gateway
chmod 600 ~/.ssh/ssh-id-gateway
echo "==== Configuring OpenClaw ===="
if [ -n "$OVERWRITE_CONFIG" ] || [ ! -e ~/.openclaw/openclaw.json ]; then
  cp /openclaw.json.default ~/.openclaw/openclaw.json
fi
echo "==== Starting OpenClaw Gateway ===="
exec "$@"
