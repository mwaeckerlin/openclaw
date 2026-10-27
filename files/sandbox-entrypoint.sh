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
home_real="$(realpath "${RUN_HOME}")"
for workspace_skills in "${RUN_HOME}/workspaces" "${RUN_HOME}"/workspaces/*/workspace; do
  [ -d "$workspace_skills" ] || continue
  # skills are only written into the volume: a skills directory that is a link
  # out of it (to the image's /app/skills) becomes a real directory, because
  # copying through the link deletes the image's skills and copies each one
  # onto itself; a workspace that leads out of the volume is left alone
  if [ -L "$workspace_skills"/skills ] && [[ "$(realpath -m "$workspace_skills"/skills)/" != "$home_real"/* ]]; then
    echo "replacing the link $workspace_skills/skills -> $(readlink "$workspace_skills"/skills) by a directory"
    rm "$workspace_skills"/skills
  fi
  if [[ "$(realpath "$workspace_skills")/" != "$home_real"/* ]]; then
    echo "WARN: $workspace_skills leads out of ${RUN_HOME}, no skills installed there" >&2
    continue
  fi
  [ -d "$workspace_skills"/skills ] || mkdir -p "$workspace_skills"/skills
  for source_dir in /app/skills/*; do
    [ -d "$source_dir" ] || continue
    skill_name="$(basename "$source_dir")"
    target_dir="${workspace_skills}/skills/${skill_name}"
    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    cp -a "$source_dir"/. "$target_dir"/
    chown -R "${RUN_USER}:${RUN_GROUP}" "$target_dir"
  done
done
# rewrite /etc/environment from scratch: appending would accumulate duplicates
# across container restarts (the file is created empty at build time)
: > /etc/environment
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
if [ -n "${OPENCLAW_OPENCODE_URL}" ]; then
  echo "==== Setting OpenCode URL ===="
  echo "OPENCLAW_OPENCODE_URL=${OPENCLAW_OPENCODE_URL}" >> /etc/environment
fi
if [ -n "${OPENCLAW_OPENCODE_TIMEOUT}" ]; then
  echo "OPENCLAW_OPENCODE_TIMEOUT=${OPENCLAW_OPENCODE_TIMEOUT}" >> /etc/environment
fi
# OpenCode in the sandbox reaches the model and the memory through its gateway,
# which adds the keys; the sandbox gets the address and the names, never a key
for name in OPENCODE_GATEWAY_URL OPENCODE_MODELS HINDSIGHT_SHARED_BANK HINDSIGHT_OWN_BANK; do
  if [ -n "${!name:-}" ]; then
    echo "${name}=${!name}" >> /etc/environment
  fi
done
chown -R ${RUN_USER}:${RUN_GROUP} ${RUN_HOME}
chmod 700 ${RUN_HOME}/.ssh
chmod 600 ${RUN_HOME}/.ssh/authorized_keys
echo "==== Starting SSH Daemon ===="
exec /usr/sbin/sshd -D -e
