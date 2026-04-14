# OpenClaw — Gateway + SSH sandbox for OpenClaw.

Run OpenClaw in a secure environement. OpenClaw runs sandboxed in Docker containers:

 - `gateway`: The controlling process of OpenClaw.
 - `sandbox`: Ubuntu instance where the AI can run commands.

 The controlling instance `gateway` acesses `sandbox` as worker node through `ssh` and runs AI requests as unpriviledged user `somebody`.

## Setup

### 1. Generate SSH keypair and .env File

```bash
ssh-keygen -t ed25519 -f openclaw-key -N "" -C "openclaw-sandbox"
cat > .env <<EOF
OPENCLAW_GATEWAY_TOKEN=$(pwgen 40 1)
AUTHORIZED_KEY=$(cat openclaw-key.pub)
OPENAI_API_KEY=sk-...
EOF
rm openclaw-key.pub
```

You must set `OPENAI_API_KEY` to access ChatGPT as AI Agent. Get a key at https://platform.openai.com/api-keys — sory, this is the part you need to pay for.

Alternatively use Docker Secrets instead of environment variables (see below).

### 3. Start

```bash
docker compose build
docker compose up -d
```

Control UI: `http://localhost:18789/`

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | yes | Shared secret for Control UI (e.g. `pwgen 40 1`) |
| `AUTHORIZED_KEY` | yes | SSH public key (ed25519) for sandbox access |
| `OPENAI_API_KEY` | yes | OpenAI API key (e.g. `sk-...`) |
| `PRIVATE_KEY` | yes | SSH private key for gateway → sandbox (\n-encoded) |
| `OPENCLAW_CONFIG_DIR` | no | Host path for config (default: Docker volume) |
| `OPENCLAW_WORKSPACE_DIR` | no | Host path for workspace (default: Docker volume) |
| `OPENCLAW_GATEWAY_PORT` | no | Gateway port (default: 18789) |
| `OPENCLAW_BRIDGE_PORT` | no | Bridge port (default: 18790) |
| `OPENCLAW_GATEWAY_BIND` | no | Bind mode (default: lan) |

## Docker Secrets (Alternative to Env)

For `docker stack deploy` or increased security:

```yaml
secrets:
  openclaw-gateway-token:
    file: ./secrets/gateway-token
  authorized-key:
    file: ./secrets/authorized-key.pub
  private-key:
    file: ./secrets/private-key
  openai-api-key:
    file: ./secrets/openai-api-key
```

Entrypoints automatically read from `/run/secrets/` when the environment variable is empty.

## Architecture

- **openclaw-gateway**: `alpine/openclaw:latest` — control plane, LLM, web UI (port 18789)
- **openclaw-sandbox**: Custom image (`mwaeckerlin/ubuntu-base`) — SSH server for isolated tool execution
