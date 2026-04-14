#!/bin/sh -e
echo "==== Setting Private Key ===="
printf '%b' "${PRIVATE_KEY:-$(</run/secrets/private-key)}" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
echo "==== Setting OpenAI API Key ===="
export OPENAI_API_KEY="${OPENAI_API_KEY:-$(</run/secrets/openai-api-key)}"
echo "==== Configuring OpenClaw ===="
cp /openclaw.json.default ~/.openclaw/openclaw.json
echo "==== Starting OpenClaw Gateway ===="
exec "$@"
