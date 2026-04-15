#!/bin/bash -e
echo "==== Setting SSH Authorized Key ===="
key="${OPENCLAW_SANDBOX_SSH_PUBLIC_KEY:-$(</run/secrets/openclaw_sandbox_ssh_public_key)}"
if [ -z "$key" ]; then
  echo "ERROR: No SSH public key provided for sandbox. Please set OPENCLAW_SANDBOX_SSH_PUBLIC_KEY variable or provide a secret named openclaw_sandbox_ssh_public_key." >&2
  exit 1
fi
[ -d ${RUN_HOME}/.ssh ] || mkdir -p ${RUN_HOME}/.ssh
echo "$key" > ${RUN_HOME}/.ssh/authorized_keys
if [ -n "${DOCKER_HOST}" ]; then
  echo "==== Enabling Docker Host ===="
  echo "DOCKER_HOST=${DOCKER_HOST}" >> /etc/environment
fi
echo "==== Starting SSH Daemon ===="
exec /usr/sbin/sshd -D -e
