#!/bin/sh -e
printf '%b' "${PRIVATE_KEY:-$(</run/secrets/private-key)}" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
export OPENAI_API_KEY="${OPENAI_API_KEY:-$(</run/secrets/openai-api-key)}"
cp -n /openclaw.json.default ~/.openclaw/openclaw.json 2>/dev/null || true
exec "$@"
