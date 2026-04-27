#!/bin/bash -e
echo "==== Setting SSH Authorized Key ===="
key="${OPENCLAW_SANDBOX_SSH_PUBLIC_KEY:-$(</run/secrets/openclaw_sandbox_ssh_public_key)}"
if [ -z "$key" ]; then
  echo "ERROR: No SSH public key provided for sandbox. Please set OPENCLAW_SANDBOX_SSH_PUBLIC_KEY variable or provide a secret named openclaw_sandbox_ssh_public_key." >&2
  exit 1
fi
[ -d ${RUN_HOME}/.ssh ] || mkdir -p ${RUN_HOME}/.ssh
echo "$key" > ${RUN_HOME}/.ssh/authorized_keys
echo "==== Installing Skills to Existing Workspaces ===="
for workspace_skills in "${RUN_HOME}"/workspaces/*/skills; do
  [ -d "$workspace_skills" ] || continue
  for source_file in /opt/openclaw/skills/*/SKILL.md; do
    [ -f "$source_file" ] || continue
    skill_name="$(basename "$(dirname "$source_file")")"
    install -D -m 644 -o "${RUN_USER}" -g "${RUN_GROUP}" "$source_file" "${workspace_skills}/${skill_name}/SKILL.md"
  done
done
if [ -n "${DOCKER_HOST}" ]; then
  echo "==== Enabling Docker Host ===="
  echo "DOCKER_HOST=${DOCKER_HOST}" >> /etc/environment
fi
if [ -n "${OPENCLAW_MCP_GATEWAY_URL}" ]; then
  echo "==== Setting MCP Gateway URL ===="
  echo "OPENCLAW_MCP_GATEWAY_URL=${OPENCLAW_MCP_GATEWAY_URL}" >> /etc/environment
fi
if [ -n "${MCP_GITHUB_URL}" ]; then
  echo "==== Setting MCP GitHub URL ===="
  echo "MCP_GITHUB_URL=${MCP_GITHUB_URL}" >> /etc/environment
fi
chown -R ${RUN_USER}:${RUN_GROUP} ${RUN_HOME}
chmod 700 ${RUN_HOME}/.ssh
chmod 600 ${RUN_HOME}/.ssh/authorized_keys
echo "==== Starting SSH Daemon ===="
exec /usr/sbin/sshd -D -e
