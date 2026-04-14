#!/bin/bash -e
echo "${AUTHORIZED_KEY:-$(</run/secrets/authorized-key)}" > ${RUN_HOME}/.ssh/authorized_keys
[ -n "${DOCKER_HOST}" ] && echo "DOCKER_HOST=${DOCKER_HOST}" >> /etc/environment
exec /usr/sbin/sshd -D -e
