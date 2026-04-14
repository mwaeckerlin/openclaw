#!/bin/bash -e
echo "${AUTHORIZED_KEY:-$(</run/secrets/authorized-key)}" > ${RUN_HOME}/.ssh/authorized_keys
exec /usr/sbin/sshd -D -e
