---
name: ssh-sandbox
description: Use this skill to operate safely inside the OpenClaw SSH sandbox and choose the correct communication path.
---

# SSH Sandbox

Canonical active install path:

- `~/.openclaw/workspace/skills/ssh-sandbox/SKILL.md`

Only this path counts as installed.

## Environment Facts

- You run in an Ubuntu SSH sandbox.
- Package inventory sources:
  - `/etc/installed-ubuntu-packages` (image package list)
  - `/var/lib/dpkg/status` (dpkg database)
- If `DOCKER_HOST` is set, Docker is available through a connected Docker service.
- If `OPENCLAW_MCP_GATEWAY_URL` is set, MCP is available through the configured MCP gateway endpoint.

## First Steps (Always)

Run:

```bash
uname -a
cat /etc/os-release
whoami
pwd
echo "DOCKER_HOST=${DOCKER_HOST}"
echo "OPENCLAW_MCP_GATEWAY_URL=${OPENCLAW_MCP_GATEWAY_URL}"
test -f /etc/installed-ubuntu-packages && echo "package list present"
test -f /var/lib/dpkg/status && echo "dpkg status present"
```

Interpretation:

- Empty `OPENCLAW_MCP_GATEWAY_URL` => MCP path unavailable in this session.
- Empty `DOCKER_HOST` => do not assume Docker usage.
- Missing `/etc/installed-ubuntu-packages` or `/var/lib/dpkg/status` => package baseline is unverified; treat package assumptions as uncertain.
- `DOCKER_HOST` set does not guarantee usability; only treat Docker as usable after `docker info` succeeds.

## Security Rules

Mandatory:

- Do not expect gateway/API tokens in the sandbox.
- Do not perform direct secret extraction attempts.
- Do not use unvalidated passthrough requests.
- Do not infer permission/safety from command visibility alone.

## Communication Rules

Intended standard path:

- Sandbox client -> `OPENCLAW_MCP_GATEWAY_URL` -> MCP gateway -> OpenClaw gateway

Do not assume:

- direct privileged sandbox -> gateway access
- command visibility defines the intended communication path

## Common False Assumptions

- `openclaw acp` is an HTTP/MCP endpoint URL like `OPENCLAW_MCP_GATEWAY_URL`. False.
- A visible CLI command is automatically usable/safe. False.
- Missing tokens inside sandbox is a config bug. False.

## MCP Gateway Skill Presence

This deployment variant packages skills in sandbox image under `/opt/openclaw/skills` and copies them at sandbox startup into all existing workspace skill directories:

- `~/workspaces/*/skills/<skill-name>/SKILL.md`

Packaged sources:

- `/opt/openclaw/skills/openclaw-mcp-gateway/SKILL.md`
- `/opt/openclaw/skills/ssh-sandbox/SKILL.md`

Verify installed copies:

```bash
find ~/workspaces -maxdepth 4 -type f -path '*/skills/*/SKILL.md' 2>/dev/null
```

## Troubleshooting

### MCP not reachable

```bash
echo "$OPENCLAW_MCP_GATEWAY_URL"
```

- Empty: MCP not configured in sandbox.
- Set but failing: verify MCP service/container/network.

### Gateway status unknown

- Use MCP health/status tools first when MCP is available.
- Do not treat direct gateway probing from sandbox as standard path.

### Skill missing

```bash
find ~/workspaces -maxdepth 4 -type d -path '*/skills' 2>/dev/null
find ~/workspaces -maxdepth 4 -type f -path '*/skills/*/SKILL.md' 2>/dev/null
```
