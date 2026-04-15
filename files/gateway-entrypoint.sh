#!/bin/sh -e
echo "==== Setting All Secrets ===="
for secret in /run/secrets/*; do
  test -e "$secret" || continue
  varname=$(basename "$secret" | tr '[:lower:]-' '[:upper:]_')
  echo "Setting $varname from $secret"
  export "$varname=$(cat "$secret")"
done
echo "==== Setting SSH Authorized Key ===="
if [ -z "$OPENCLAW_SANDBOX_SSH_PRIVATE_KEY" ]; then
  echo "ERROR: No SSH private key provided for sandbox. Please set OPENCLAW_SANDBOX_SSH_PRIVATE_KEY variable or provide a secret named openclaw_sandbox_ssh_private_key." >&2
  exit 1
fi
printf '%b' "${OPENCLAW_SANDBOX_SSH_PRIVATE_KEY}" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
echo "==== Configuring OpenClaw ===="
[ -e ~/.openclaw/openclaw.json ] || cp /openclaw.json.default ~/.openclaw/openclaw.json
echo "==== Starting OpenClaw Gateway ===="
exec "$@"
