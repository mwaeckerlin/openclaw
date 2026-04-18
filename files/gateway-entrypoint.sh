#!/bin/sh -e
echo "==== Setting All Secrets ===="
for secret in /run/secrets/*; do
  test -e "$secret" || continue
  varname=$(basename "$secret" | tr '[:lower:]-' '[:upper:]_')
  echo "Setting $varname from $secret"
  export "$varname=$(sed -z 's/\n/\\n/g' "$secret")"
done

echo "==== Setting OpenAI API Key ===="
if [ -z "$OPENCLAW_WHISPER_API_KEY" -a -n "$OPENAI_API_KEY" ]; then
  export OPENCLAW_WHISPER_API_KEY="$OPENAI_API_KEY"
  echo "OPENCLAW_WHISPER_API_KEY set from OPENAI_API_KEY"
fi

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

if [ -n "$LITELLM_URL" ] && [ -n "$LITELLM_MASTER_KEY" ]; then
  echo "==== Discovering LiteLLM Models ===="
  models_json=$(curl -sf -H "Authorization: Bearer $LITELLM_MASTER_KEY" "$LITELLM_URL/v1/models" 2>/dev/null)
  if [ -z "$models_json" ]; then
    echo "ERROR: Failed to discover models from LiteLLM at $LITELLM_URL" >&2
    exit 1
    echo "LiteLLM models: $models_json"
  fi

  model_array=$(node -e "
    const data = JSON.parse(process.argv[1]);
    const models = data.data.map(m => ({ id: m.id }));
    process.stdout.write(JSON.stringify(models));
  " "$models_json")
  model_count=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).length))" "$model_array")
  echo "  Discovered $model_count models from LiteLLM"
  openclaw config set models.providers.litellm.models "$model_array" --strict-json
  echo "Models injected into config"
fi

if [ -n "$PLUGINS" ]; then
  echo "==== Install Plugins ===="
  echo "Plugins to install: $PLUGINS"
    openclaw plugins install "$PLUGINS"
fi

echo "==== Starting OpenClaw Gateway ===="
exec "$@"
