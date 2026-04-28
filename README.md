# Simple Secure OpenClaw in SSH Sandbox


Combine OpenClaw with Security and Easiness! Run out of the box a secure docker based sandboxed OpenClaw, locally or in a cloud.

**It has never been so easy to run a *secure* sandboxed pre-configured OpenClaw!**:
1. get an [OpenAI token](https://platform.openai.com/api-keys) (or use [LiteLLM](https://docs.litellm.ai/docs/))
1. write some [configuration variables in `.env`](#development-setup)
2. run `npm start`
3. open: [`http://localhost:18789/`](http://localhost:18789/)

**Target audience:** Security aware **developer** with some basic docker know how. Everybody else: **Keep your hands away from OpenClaw!**

![](doc/overview.svg)

<details>
<summary>PlantUML source</summary>
```plantuml
@startuml overview
cloud Docker {
  component [Openclaw:Gateway] {
    (secrets) . [Gateway]
  }
  component [Openclaw:Sandbox] {
    [Ubuntu]
  }
}
:User: --> [Gateway] : control
:Agent: --> [Ubuntu] : execute\ncommands
[Gateway] -> [Ubuntu] : ssh
@enduml
```

</details>

## Security Model

The primary security mechanism is **strict isolation**: The AI runs in a dedicated sandbox container that contains only its tools and workspace — no host secrets, no production data, no unrelated resources.

### Seggregation in Container

- **Isolation in Seggregated Container** — The gateway controlls access and secrets. The agent has no direct access to the gateway (no tokens, no secrets). The agent cannot access files or variables or secrets defined on the gateway. *Never expose any secret to the sandbox!*
- **Access through MCP** — Where the SSH sandboxed agent cannot get access from the gateway, we add an MCP server that holds the token in a seggregated container.
- **Container hardening** — `no-new-privileges`, `pids_limit: 256` against escalation and fork bombs

### Network Isolation

- **Network isolation** — Containers communicate on seggregated internal networks. Every two containers have their own network.
- **Network Encryption** (production) — When going to production, *encrypt the networks* (e.g. encrypted overlay in docker swarm: for all networks set `networks.<network>.driver_opts.encrypted: "true"`, or add a service mesh)
- **No port over-exposure** — Only port 18789 (UI/API) is published for *local testing only*; internal ports stay internal. If you attach chat tool, such as [Telegram](https://telegram.org/), you can even close that port. You can then reach your OpenClaw through Telegram. *Do not expose 18789 to the Internet without further protection.* You may add e.g. [Traefik](https://doc.traefik.io/traefik/) service and an [Authentik proxy-provider outpost](https://docs.goauthentik.io/add-secure-apps/outposts) in front of OpenClaw when you want to access it through the internet.

**Note:** If networks are neither seggregated nor encrypted, the agent can *sniff for secrets* on the shared or unencrypted network. So network isolation is crucial, and encryption is highly recommended at least in production.

### Secrets

- **Secrets** (production) — Use docker secrets instead of environment variables in docker swarm (or use a vault such as Hashicorps to deploy in e.g. Kubernetes). Secrets can be mounted on `/var/secrets/secret-name` and are then exported to the OpenClaw environment variables as `SECRET_NAME`.

### Additional Tools and Seggregations

- **Docker-in-Docker isolation** — If yo uwant to allow the agent to run docker commands, you may attach a dedicated Docker container (`docker:dind`) where the agent can run docker in an isolated installation, seggregated from your docker installation. Be aware that the agent can gain root, but only in tis isolated container. Just restart the container to restore in case of a break out. No data is in danger.
- **OpenClaw-MCP-Gateway** — The project [mwaeckerlin/openclaw-mcp-gateway](https://github.com/mwaeckerlin/openclaw-mcp-gateway) runs an MCP server to give the sandbox limited access to the gateway to execute some safe `openclaw` CLI commands. It helps for self analysis and allows to setup cron jobs. Only the MCP server holds the gateway token, the sandbox has no access to the token.
- **MCP-Github** — The project [mwaeckerlin/mcp-github](https://github.com/mwaeckerlin/mcp-github) gives the sandbox access to the GitHub API. Only the MCP server holds the GitHub token, the sandbox has no access to the token.
- **MCP-Gitea** — The [gitea/gitea-mcp](https://gitea.com/gitea/gitea-mcp) server gives the sandbox access to a self-hosted Gitea instance. Only the MCP server holds the Gitea access token, the sandbox has no access to the token. Set `OPENCLAW_GITEA_TOKEN` and `OPENCLAW_GITEA_HOST` to enable.

### Hardened OpenClaw Setup

- **Workspace restriction** (`tools.fs.workspaceOnly: true`) — File tools limited to the sandbox workspace.  
  **Note:** The `workspaceOnly` setting restricts OpenClaw's **file tools** to the workspace. However, `exec`/shell commands can still read container system files (e.g. `/etc/passwd`, `/proc`). This is acceptable because the sandbox is an isolated container — there are no host secrets inside it.
- **Loop detection** (`loopDetection`) — Circuit breaker against tool/agent loops. That's more to prevent token over spending.

### `strictHostKeyChecking: false`

Acceptable in a controlled internal Docker network where DNS is managed by Docker. For production hardening, consider pinning host keys.

## Full Architecture

![](doc/architecture.svg)

<details>
<summary>PlantUML source</summary>

```plantuml

@startuml architecture
actor User as user

cloud docker {

  node "mwaeckerlin/openclaw:gateway" as gw {
    [Gateway] as ctrl
    storage "openclaw-config" as cfg
    ctrl - cfg
  }

  node "mwaeckerlin/openclaw-mcp-gateway" {
    [MCP OpenClaw Server] as mcp
  }

  node "mwaeckerlin/openclaw:sandbox" as sb {
    [Sandbox] as sshd
    storage "openclaw-workspace" as ws
    sshd -right- ws
  }

  node "openclaw-dind" as dind {
    [Docker] as dd
    storage "openclaw-docker" as dv
    dd -left- dv
  }

  node "mwaeckerlin/mcp-github" {
    [Github-Gateway] as gh
  }

  node "gitea/gitea-mcp" {
    [Gitea-Gateway] as gt
  }

  component "allow-write-access" as aw
}

user --> ctrl : "HTTP"
ctrl --> sshd : "SSH"
sshd --up--> mcp : openclaw\ncommands
mcp --up--> ctrl : forward\ncommands
sshd -left-> dd : docker
aw .up.> cfg : chown
sshd --> gh
gh ----> [GitHub]
sshd --> gt
gt ----> [Gitea]
@enduml
```

</details>

## Local Development Setup

For local testing with `docker compose` and `.env` file.

### 1. Generate SSH Keypair and .env

Simplest use is with an [OpenAI token](https://platform.openai.com/api-keys) that you store in `OPENAI_API_KEY`. All other secrets can just be randomly generated:

```bash
ssh-keygen -t ed25519 -f openclaw-key -N "" -C "openclaw-sandbox"
cat > .env <<EOF
OPENCLAW_GATEWAY_TOKEN=$(pwgen 40 1)
OPENCLAW_SANDBOX_SSH_PUBLIC_KEY=$(cat openclaw-key.pub)
OPENCLAW_SANDBOX_SSH_PRIVATE_KEY=$(sed -z 's/\n/\\n/g' openclaw-key)
OPENAI_API_KEY=sk-...[PLACE-TOKEN-HERE]
EOF
rm openclaw-key openclaw-key.pub
```

### 2. Generate MCP Gateway Device Pairing

If you use the MCP gateway (enabled by default), generate a device keypair for secure gateway-to-MCP communication:

```bash
node generate-device-pairing.mjs
```

This appends `OPENCLAW_DEVICE_IDENTITY` and `OPENCLAW_DEVICE_PAIRING` to `.env`. The MCP gateway uses the private key to authenticate, and the OpenClaw gateway pre-registers the public key so the device is trusted on first connect.

Use `--stdout` to print the values instead of writing to `.env`.

### 3. Start

**In foreground (see logs in real-time):**
```bash
npm start
```

**In background (daemon mode):**
```bash
npm run start:daemon
```

Control UI: `http://localhost:18789/`

**This is for local / trusted-network use only.** The gateway token is transmitted unencrypted. Do not expose port 18789 to the internet without a TLS reverse proxy.

## Full Configuration Guide

### Automatic Secret Mapping

The gateway entrypoint iterates over all files in `/run/secrets/` and exports each as an environment variable. The filename is uppercased and dashes are replaced by underscores, e.g.:

| Environment Variable | Secret Name | Alternative Secret Name |
|---|---|---|
| `OPENAI_API_KEY` | `openai_api_key` | `openai-api-key` |
| `OPENCLAW_SANDBOX_SSH_PRIVATE_KEY` | `openclaw_sandbox_ssh_private_key` | `openclaw-sandbox-ssh-private-key` |
| … | … | … |

The sandbox reads its public key directly from `/run/secrets/openai_api_key  or alternatively `/run/secrets/openai-api-key` (fallback when `OPENAI_API_KEY` is not set,`-` and `_` are interchangable).

This means *any* Docker Secret is automatically available as an environment variable — no explicit mapping required. Secrets take precedence over environment variables.

### Core Configuration

| Variable | Required | Description |
|---|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | yes | Shared secret for Control UI |
| `OPENCLAW_SANDBOX_SSH_PUBLIC_KEY` | yes | SSH public key (ed25519) for sandbox access |
| `OPENCLAW_SANDBOX_SSH_PRIVATE_KEY` | yes | SSH private key, `\n`-encoded (gateway → sandbox) |

### Feature Configuration

| Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | no | OpenAI API key; enables OpenAI provider, Whisper audio transcription, and is used as default model provider if `LITELLM_MASTER_KEY` is not set |
| `OPENCLAW_WHISPER_API_KEY` | no | Whisper API key override; if unset and `OPENAI_API_KEY` is set, the rendered configuration uses `OPENAI_API_KEY` for Whisper |
| `OVERWRITE_CONFIG` | no | Unset/true overwrites `openclaw.json` from the template on startup; set `false` to preserve manual edits |
| `OPENCLAW_CONFIG_DIR` | no | Host path for config (default: Docker volume) |
| `OPENCLAW_STATE_DIR` | no | OpenClaw state directory path inside the gateway container (defaults to `~/.openclaw`) |
| `OPENCLAW_GATEWAY_PORT` | no | Gateway port (default: 18789) |
| `OPENCLAW_ELEVENLABS_API_KEY` | — | ElevenLabs API key; enables TTS via ElevenLabs (else Microsoft TTS) |
| `OPENCLAW_NOTION_API_KEY` | — | Notion API key; enables Notion skill |
| `OPENCLAW_GITHUB_TOKEN` | — | GitHub personal access token; enables GitHub MCP server via ACPX (token stays gateway-side, sandbox only sees MCP tools) |
| `MCP_GITHUB_URL` | no (compose default) | MCP GitHub endpoint used from the sandbox. Default in this setup: `http://mcp-github:4000`. This value is written to `/etc/environment` by the sandbox entrypoint so the non-root SSH user can read it. |
| `OPENCLAW_GITEA_HOST` | — | Gitea host URL (e.g. `https://gitea.example.com`); required to enable Gitea MCP server integration |
| `OPENCLAW_GITEA_TOKEN` | — | Gitea personal access token; enables Gitea MCP server (token stays in the mcp-gitea container, sandbox only sees MCP tools) |
| `OPENCLAW_GITEA_INSECURE` | — | Set to `true` to skip TLS verification for the Gitea connection (optional, not recommended for production) |
| `MCP_GITEA_URL` | no (compose default) | MCP Gitea endpoint used from the sandbox. Default in this setup: `http://mcp-gitea:8080`. This value is written to `/etc/environment` by the sandbox entrypoint so the non-root SSH user can read it. |
| `OPENCLAW_TRELLO_API_KEY` | — | Trello API key; enables Trello skill |
| `OPENCLAW_TELEGRAM_BOT_TOKEN` | — | Telegram bot token; enables Telegram channel |
| `OPENCLAW_DISCORD_BOT_TOKEN` | — | Discord bot token; enables Discord channel |
| `OPENCLAW_SLACK_BOT_TOKEN` | — | Slack bot token; enables Slack channel |
| `OPENCLAW_SLACK_APP_TOKEN` | — | Slack app token for socket mode (`channels.slack.appToken`) |
| `OPENCLAW_BRAVE_API_KEY` | — | Brave Search API key; enables Brave plugin (else DuckDuckGo) |
| `OPENCLAW_GOOGLECHAT_SERVICE_ACCOUNT_JSON` | — | Google Chat service account JSON; enables Google Chat channel |
| `OPENCLAW_GOOGLECHAT_SERVICE_ACCOUNT_FILE` | — | Path to Google Chat service account file |
| `OPENCLAW_MATTERMOST_BOT_TOKEN` | — | Mattermost bot token; enables Mattermost channel |
| `OPENCLAW_MATTERMOST_BASE_URL` | — | Mattermost base URL |
| `OPENCLAW_MATRIX_HOMESERVER` | — | Matrix homeserver URL |
| `OPENCLAW_MATRIX_ACCESS_TOKEN` | — | Matrix access token; enables Matrix channel |
| `OPENCLAW_MSTEAMS_APP_ID` | — | Microsoft Teams app ID |
| `OPENCLAW_MSTEAMS_APP_PASSWORD` | — | Microsoft Teams app password |
| `OPENCLAW_MSTEAMS_TENANT_ID` | — | Microsoft Teams tenant ID |
| `OPENCLAW_BLUEBUBBLES_SERVER_URL` | — | BlueBubbles server URL |
| `OPENCLAW_BLUEBUBBLES_PASSWORD` | — | BlueBubbles password |
| `OPENCLAW_IRC_NICKSERV_PASSWORD` | — | IRC NickServ password |

### LiteLLM Configuration

When `LITELLM_MASTER_KEY` is set, LiteLLM is enabled as model provider and the default model switches to `litellm/openrouter/~moonshotai/kimi-latest`. Without LiteLLM, OpenClaw uses `openrouter/~moonshotai/kimi-latest` when `OPENROUTER_API_KEY` is set, otherwise `openai/gpt-4.6`.

| Variable | Default | Description |
|---|---|---|
| `LITELLM_MASTER_KEY` | — | Bearer token for LiteLLM API authentication; enables LiteLLM provider |
| `LITELLM_URL` | — | Base URL of LiteLLM proxy for model discovery |
| `LITELLM_BASE_URL` | `http://litellm:4000` | Base URL for connecting to LiteLLM |

When configured, model lists are discovered dynamically from providers:

- LiteLLM: `LITELLM_URL/v1/models` → `models.providers.litellm.models`
- OpenAI: `${OPENCLAW_OPENAI_BASE_URL:-https://api.openai.com/v1}/models` → `models.providers.openai.models` (unless `OPENCLAW_OPENAI_MODELS_JSON` is explicitly set)

### Agent & Model Configuration

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_PRIMARY_MODEL` | _(auto)_ | Default LLM model; auto-selects `litellm/openrouter/~moonshotai/kimi-latest` with LiteLLM, `openrouter/~moonshotai/kimi-latest` with OpenRouter, else `openai/gpt-4.6` |
| `OPENCLAW_HEARTBEAT_INTERVAL` | `0s` | Duration for agent heartbeat (e.g. `30m`, `2h`, `0s` = disabled) |
| `OPENCLAW_TIMEOUT_SECONDS` | `300` | Agent execution timeout in seconds |
| `OPENCLAW_MAX_CONCURRENT` | `5` | Maximum concurrent agents |
| `OPENCLAW_CRON_ENABLED` | `true` | Enable cron scheduler support |
| `OPENCLAW_BASE_PATH` | _(empty)_ | Base path for Control UI (e.g. `/openclaw` behind reverse proxy) |
| `OPENCLAW_AGENT_SCOPE` | `agent` | Sandbox scope for agent sessions; allowed: `session`, `agent`, `shared` |
| `OPENCLAW_DM_SCOPE` | `main` | DM scope for session routing; allowed: `main`, `per-peer`, `per-channel-peer`, `per-account-channel-peer` |
| `OPENCLAW_SESSION_VISIBILITY` | `agent` | Session visibility for tools; allowed: `agent`, `global` |
| `OPENCLAW_SESSION_TOOLS_VISIBILITY` | `all` | Which tools are visible in sandbox sessions; allowed: `all`, `none` |

### Plugin Configuration & Installation

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_PLUGINS_JSON` | — | Full `plugins` section as JSON |
| `OPENCLAW_PLUGIN_ENTRIES_JSON` | — | Additional `plugins.entries` object merged into the generated config |
| `PLUGINS` | — | Manual install spec passed to `openclaw plugins install` |

Example:

```bash
OPENCLAW_PLUGIN_ENTRIES_JSON='{"matrix":{"enabled":true,"config":{"homeserver":"https://matrix.example","accessToken":"${OPENCLAW_MATRIX_ACCESS_TOKEN}"}}}'
PLUGINS='@openclaw/matrix'
```

### Full OpenClaw Config Coverage (Schema Roots)

Each root section in `files/openclaw.json.j2` is configurable via a section JSON variable:

`OPENCLAW_<SECTION>_JSON`

Example:

```bash
OPENCLAW_GATEWAY_JSON='{"mode":"local","bind":"lan","port":18789,"auth":{"mode":"token","token":"${OPENCLAW_GATEWAY_TOKEN}"},"trustedProxies":["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"]}'
```

Supported section variables (from official OpenClaw schema roots):

`OPENCLAW_META_JSON`, `OPENCLAW_ENV_JSON`, `OPENCLAW_WIZARD_JSON`, `OPENCLAW_DIAGNOSTICS_JSON`, `OPENCLAW_LOGGING_JSON`, `OPENCLAW_CLI_JSON`, `OPENCLAW_UPDATE_JSON`, `OPENCLAW_BROWSER_JSON`, `OPENCLAW_UI_JSON`, `OPENCLAW_SECRETS_JSON`, `OPENCLAW_AUTH_JSON`, `OPENCLAW_ACP_JSON`, `OPENCLAW_MODELS_JSON`, `OPENCLAW_NODE_HOST_JSON`, `OPENCLAW_AGENTS_JSON`, `OPENCLAW_TOOLS_JSON`, `OPENCLAW_BINDINGS_JSON`, `OPENCLAW_BROADCAST_JSON`, `OPENCLAW_AUDIO_JSON`, `OPENCLAW_MEDIA_JSON`, `OPENCLAW_MESSAGES_JSON`, `OPENCLAW_COMMANDS_JSON`, `OPENCLAW_APPROVALS_JSON`, `OPENCLAW_SESSION_JSON`, `OPENCLAW_CRON_JSON`, `OPENCLAW_HOOKS_JSON`, `OPENCLAW_WEB_JSON`, `OPENCLAW_CHANNELS_JSON`, `OPENCLAW_DISCOVERY_JSON`, `OPENCLAW_CANVAS_HOST_JSON`, `OPENCLAW_TALK_JSON`, `OPENCLAW_GATEWAY_JSON`, `OPENCLAW_MEMORY_JSON`, `OPENCLAW_MCP_JSON`, `OPENCLAW_SKILLS_JSON`, `OPENCLAW_PLUGINS_JSON`.

If `OPENCLAW_<SECTION>_JSON` is set, it replaces that full section from the template.
If not set, the template defaults and feature toggles apply.

Plugin configurations are supported in two modes:

- complete plugin section replacement via `OPENCLAW_PLUGINS_JSON`
- additive plugin entry mapping via `OPENCLAW_PLUGIN_ENTRIES_JSON`

### Individual Overrides (Per-Parameter)

In addition to section-level JSON overrides, common single settings can be overridden directly via environment variables.

Most useful groups:

- Models and providers: `OPENCLAW_MODELS_MODE`, `OPENCLAW_OPENAI_BASE_URL`, `OPENCLAW_OPENAI_MODELS_JSON`, `OPENCLAW_LITELLM_*`, `OPENCLAW_AGENT_MODELS_JSON`
- Agent runtime: `OPENCLAW_AGENT_SANDBOX_MODE`, `OPENCLAW_AGENT_WORKSPACE_ACCESS`, `OPENCLAW_SUBAGENT_*`
- Tools and media: `OPENCLAW_TOOLS_FS_WORKSPACE_ONLY`, `OPENCLAW_LOOP_DETECTION_*`, `OPENCLAW_MEDIA_AUDIO_*`, `OPENCLAW_TTS_*`
- Messaging and hooks: `OPENCLAW_MESSAGES_QUEUE_*`, `OPENCLAW_COMMANDS_*`, `OPENCLAW_HOOKS_*`
- Channels: `OPENCLAW_TELEGRAM_*`, `OPENCLAW_DISCORD_*`, `OPENCLAW_SLACK_*`, `OPENCLAW_WHATSAPP_*`, `OPENCLAW_GOOGLECHAT_*`, `OPENCLAW_MATTERMOST_*`, `OPENCLAW_SIGNAL_*`, `OPENCLAW_IRC_*`
- Gateway and UI: `OPENCLAW_GATEWAY_*`, `OPENCLAW_CONTROL_UI_*`, `OPENCLAW_ALLOWED_ORIGINS_JSON`, `OPENCLAW_TAILSCALE_*`, `OPENCLAW_TRUSTED_PROXIES_JSON`
- Plugins and MCP/ACPX: `OPENCLAW_PLUGIN_*`, `OPENCLAW_ACPX_*`, `OPENCLAW_GITHUB_TOKEN`, `OPENCLAW_GITEA_*`, `PLUGINS`

For token/secret-based channels, there is intentionally no separate `*_ENABLED` toggle: the token/secret is the feature enabler.

Special case:

- `OPENCLAW_ALLOWED_ORIGINS_JSON` sets `gateway.controlUi.allowedOrigins`.
- There is no built-in default for `allowedOrigins`; if not set, the field is not written.

Model handling:

- Agent model mappings can be set via `OPENCLAW_AGENT_MODELS_JSON`.
- Provider model catalogs are managed per provider (`models.providers.*.models`), including LiteLLM discovery via `LITELLM_URL` + `LITELLM_MASTER_KEY`.

For a full technical variable reference, use the gateway service environment block in `docker-compose.yml` and the template defaults in `files/openclaw.json.j2`.


## Docker-in-Docker (Optional)

The `openclaw-dind` service provides an isolated Docker daemon for the sandbox. It is **optional** — simply remove the `openclaw-dind` service and the `DOCKER_HOST` environment variable from the sandbox to disable it.

**Who needs this?** Developers and DevOps engineers who want OpenClaw to autonomously build, run, and test containerized applications. For general use (writing, research, scripting), DinD is not needed.

**Security warning:** The AI has full root access inside the DinD daemon. It can mount the DinD container's root filesystem, destroy all images/containers, or exhaust disk space on the `openclaw-docker` volume. DinD is isolated from the host Docker, but within its own daemon the AI has unrestricted access. Only enable this if you accept that risk.

### DinD in Docker Swarm

Docker Swarm does not support `privileged: true` in stack deploy files. Docker-in-Docker is therefore not supported in this Swarm setup.

### Production Checklist

- [ ] All secrets via `docker secret`, not environment variables
- [ ] Encrypted overlay network (`--opt encrypted`)
- [ ] Port 18789 behind TLS reverse proxy (nginx, Traefik, Kong)
- [ ] Port 18790 not exposed (internal bridge only)
- [ ] Firewall restricts access to gateway port
- [ ] Consider `read_only: true` + `tmpfs` mounts if OpenClaw supports it
