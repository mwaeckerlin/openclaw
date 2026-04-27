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

echo "==== Rendering Jinja2 Configuration ===="
node /render-config.js /openclaw.json.j2.default ~/.openclaw/openclaw.json.rendered

normalize_provider_models() {
  _cfg_path="$1"
  [ -f "$_cfg_path" ] || return 0
  echo "==== Normalizing Provider Model Catalog: $_cfg_path ===="
  node -e "
  const fs = require('fs');
  const p = process.argv[1];
  const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
  const providers = cfg?.models?.providers;
  if (providers && typeof providers === 'object') {
    for (const [providerId, provider] of Object.entries(providers)) {
      if (!provider || typeof provider !== 'object') continue;
      const rows = provider.models;
      if (!Array.isArray(rows)) continue;
      provider.models = rows
        .map((m) => {
          if (typeof m === 'string') return { id: m, name: m };
          if (!m || typeof m !== 'object') return null;
          if (typeof m.id !== 'string') return null;
          if (typeof m.name !== 'string' || m.name.length === 0) return { ...m, name: m.id };
          return m;
        })
        .filter(Boolean);
      providers[providerId] = provider;
    }
  }
  fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
" "$_cfg_path"
}

normalize_provider_models ~/.openclaw/openclaw.json.rendered

echo "==== Configuring OpenClaw ===="
# Unset/true overwrites openclaw.json from the template on startup.
# Set OVERWRITE_CONFIG=false to preserve manual edits in the persistent volume.
_overwrite_config="${OVERWRITE_CONFIG:-true}"
if [ "$_overwrite_config" = "true" ] || [ "$_overwrite_config" = "1" ] || [ "$_overwrite_config" = "yes" ] || [ "$_overwrite_config" = "on" ] || [ ! -e ~/.openclaw/openclaw.json ]; then
  cp ~/.openclaw/openclaw.json.rendered ~/.openclaw/openclaw.json
  echo "openclaw.json written"
else
  echo "openclaw.json preserved (OVERWRITE_CONFIG=false)"
fi
normalize_provider_models ~/.openclaw/openclaw.json

if [ -n "$OPENCLAW_DEVICE_PAIRING" ]; then
  echo "==== Pre-Seeding Device Pairing ===="
  _state_dir="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
  mkdir -p "$_state_dir/devices"
  printf '%b' "$OPENCLAW_DEVICE_PAIRING" > "$_state_dir/devices/paired.json"
  echo "Device pairing written to $_state_dir/devices/paired.json"
fi

if [ -n "$LITELLM_URL" ] && [ -n "$LITELLM_MASTER_KEY" ]; then
  echo "==== Discovering LiteLLM Models ===="
  model_count=$(curl -sf -H "Authorization: Bearer $LITELLM_MASTER_KEY" "$LITELLM_URL/v1/models" 2>/dev/null | node -e "
    const fs = require('fs');
    const cfgPath = process.argv[1];
    const providerId = process.argv[2];
    const raw = fs.readFileSync(0, 'utf8');
    if (!raw || !raw.trim()) process.exit(2);
    const data = JSON.parse(raw);
    const rows = Array.isArray(data?.data) ? data.data : [];
    const models = rows
      .filter((m) => m && typeof m.id === 'string')
      .map((m) => ({ id: m.id, name: m.id }));
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    if (!cfg.models || typeof cfg.models !== 'object') cfg.models = {};
    if (!cfg.models.providers || typeof cfg.models.providers !== 'object') cfg.models.providers = {};
    if (!cfg.models.providers[providerId] || typeof cfg.models.providers[providerId] !== 'object') {
      cfg.models.providers[providerId] = {};
    }
    cfg.models.providers[providerId].models = models;
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
    process.stdout.write(String(models.length));
  " "$HOME/.openclaw/openclaw.json" "litellm") || {
    echo "ERROR: Failed to discover models from LiteLLM at $LITELLM_URL" >&2
    exit 1
  }
  echo "  Discovered $model_count models from LiteLLM"
  echo "Models injected into config"
fi

if [ -n "$OPENAI_API_KEY" ] && [ -z "$OPENCLAW_OPENAI_MODELS_JSON" ]; then
  _openai_base="${OPENCLAW_OPENAI_BASE_URL:-https://api.openai.com/v1}"
  _openai_url="${_openai_base%/}/models"
  echo "==== Discovering OpenAI Models ===="
  if model_count=$(curl -sf -H "Authorization: Bearer $OPENAI_API_KEY" "$_openai_url" 2>/dev/null | node -e "
    const fs = require('fs');
    const cfgPath = process.argv[1];
    const providerId = process.argv[2];
    const syncDiscoveredToAgentList = process.argv[3] === 'true';
    const raw = fs.readFileSync(0, 'utf8');
    if (!raw || !raw.trim()) process.exit(2);
    const data = JSON.parse(raw);
    const rows = Array.isArray(data?.data) ? data.data : [];
    const models = rows
      .filter((m) => m && typeof m.id === 'string')
      .map((m) => ({ id: m.id, name: m.id }));
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    if (!cfg.models || typeof cfg.models !== 'object') cfg.models = {};
    if (!cfg.models.providers || typeof cfg.models.providers !== 'object') cfg.models.providers = {};
    if (!cfg.models.providers[providerId] || typeof cfg.models.providers[providerId] !== 'object') {
      cfg.models.providers[providerId] = {};
    }
    cfg.models.providers[providerId].models = models;
    if (syncDiscoveredToAgentList) {
      if (!cfg.agents || typeof cfg.agents !== 'object') cfg.agents = {};
      if (!cfg.agents.defaults || typeof cfg.agents.defaults !== 'object') cfg.agents.defaults = {};
      cfg.agents.defaults.models = Object.fromEntries(
        models.map((m) => [providerId + '/' + m.id, {}]),
      );
    }
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
    process.stdout.write(String(models.length));
  " "$HOME/.openclaw/openclaw.json" "openai" "$([ -z "${OPENCLAW_AGENT_MODELS_JSON:-}" ] && [ -z "${OPENCLAW_AGENTS_JSON:-}" ] && echo true || echo false)"); then
    echo "  Discovered $model_count models from OpenAI"
    echo "Models injected into config"
    echo "  OpenAI discovered model IDs: $(node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
      const models = (((cfg || {}).models || {}).providers || {}).openai?.models || [];
      const ids = [];
      for (const model of models) {
        if (typeof model === 'string') {
          ids.push(model);
          continue;
        }
        if (model && typeof model.id === 'string') ids.push(model.id);
      }
      process.stdout.write(ids.join(', '));
    " "$HOME/.openclaw/openclaw.json")"
    if [ -z "${OPENCLAW_AGENT_MODELS_JSON:-}" ] && [ -z "${OPENCLAW_AGENTS_JSON:-}" ]; then
      agent_model_count=$(node -e "
        const fs = require('fs');
        const cfg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
        const models = ((((cfg || {}).agents || {}).defaults || {}).models);
        process.stdout.write(String(models && typeof models === 'object' ? Object.keys(models).length : 0));
      " "$HOME/.openclaw/openclaw.json")
      echo "  Agent model options synchronized from OpenAI provider list ($agent_model_count entries)"
    fi
  else
    echo "WARN: Could not discover OpenAI models from $_openai_url (continuing with configured/default list)" >&2
  fi
fi

if [ -n "$PLUGINS" ]; then
  echo "==== Install Plugins ===="
  echo "Plugins to install: $PLUGINS"
    openclaw plugins install "$PLUGINS"
fi

echo "==== Starting OpenClaw Gateway ===="
exec "$@"
