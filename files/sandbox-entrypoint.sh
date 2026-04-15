#!/bin/bash -e
echo "${OPENCLAW_SANDBOX_SSH_PUBLIC_KEY:-$(</run/secrets/openclaw-sandbox-ssh-public-key)}" > ${RUN_HOME}/.ssh/authorized_keys
[ -n "${DOCKER_HOST}" ] && echo "DOCKER_HOST=${DOCKER_HOST}" >> /etc/environment
exec /usr/sbin/sshd -D -e
