#!/usr/bin/env bash
# State migration contract: the gateway starts on the state volume an older
# OpenClaw release wrote, with an agent that has held a conversation, and
# keeps that conversation.
#
#   - for each former release, its gateway image writes a configuration and
#     holds one agent turn against a recording model endpoint on a fresh
#     volume; the gateway image then starts on that volume, migrates the
#     state and answers /healthz
#   - the migrated state still holds the agent's session
#   - neither the configuration nor its backups on the volume carry the token
#   - a restart on the migrated volume does not migrate again
#
# The former releases are the ones this image shipped: 2026.6.9 of
# alpine/openclaw up to 1.1.1, and 2026.9.6 of openclaw/openclaw from 1.1.2.
#
# Needs the built image: `npm run build` (or `docker compose build
# openclaw-gateway`). Usage: tests/state-migration.sh [<image>]

set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-mwaeckerlin/openclaw:gateway}"
FORMER_RELEASES=(alpine/openclaw:2026.6.9 openclaw/openclaw:2026.9.6)
PREFIX="openclaw-state-migration-test-$$"
NETWORK="${PREFIX}"
STUB="${PREFIX}-stub"
PASS=0
FAIL=0
declare -a FAILED_NAMES
declare -a CONTAINERS=("${STUB}")
declare -a VOLUMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

cleanup() {
    docker rm -f "${CONTAINERS[@]}" >/dev/null 2>&1
    docker network rm "${NETWORK}" >/dev/null 2>&1
    [[ ${#VOLUMES[@]} -gt 0 ]] && docker volume rm "${VOLUMES[@]}" >/dev/null 2>&1
}
trap cleanup EXIT

BASE_ENV=(
    -e OPENCLAW_GATEWAY_TOKEN=test-token
    -e "OPENCLAW_SANDBOX_SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
)

# wait_healthy: <container> — until the gateway answers /healthz or stops;
# the migration of an old state takes minutes
wait_healthy() {
    for _ in $(seq 1 200); do
        if docker exec "$1" node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
            return 0
        fi
        if [[ "$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null)" != "true" ]]; then
            return 1
        fi
        sleep 3
    done
    return 1
}

echo "==> State migration contract: ${IMAGE}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    _fail "image_present" "${IMAGE} is not built — run npm run build first"
else
    docker network create "${NETWORK}" >/dev/null
    docker run -d --name "${STUB}" --network "${NETWORK}" --entrypoint node "${IMAGE}" -e "$(cat tests/openai-stub.cjs)" >/dev/null

    # the configuration the former release runs with: its agent answers with
    # the model of the recording endpoint
    FORMER_CONFIG="{\"models\":{\"providers\":{\"litellm\":{\"baseUrl\":\"http://${STUB}:4000/v1\",\"api\":\"openai-completions\",\"apiKey\":\"stub-key\",\"models\":[{\"id\":\"stub-model\",\"name\":\"stub-model\"}]}}},\"agents\":{\"defaults\":{\"model\":{\"primary\":\"litellm/stub-model\"}}}}"

    for FORMER in "${FORMER_RELEASES[@]}"; do
        RELEASE="${FORMER##*:}"
        NAME="${PREFIX}-${RELEASE}"
        VOLUME="${PREFIX}-${RELEASE}"
        CONTAINERS+=("${NAME}")
        VOLUMES+=("${VOLUME}")
        docker image inspect "${FORMER}" >/dev/null 2>&1 || docker pull --quiet "${FORMER}" >/dev/null

        # the former release writes its state: configuration, then one agent turn
        docker run --rm -v "${VOLUME}:/home/node/.openclaw" --entrypoint node "${FORMER}" \
            -e "require('fs').writeFileSync(require('os').homedir() + '/.openclaw/openclaw.json', process.argv[1])" "${FORMER_CONFIG}" >/dev/null 2>&1
        TURN=$(docker run --rm --network "${NETWORK}" -v "${VOLUME}:/home/node/.openclaw" --entrypoint node "${FORMER}" \
            openclaw.mjs agent --local --agent main --message "Reply with exactly: pong" --json 2>&1)
        SESSIONS_BEFORE=$(docker run --rm --network none -v "${VOLUME}:/home/node/.openclaw" --entrypoint node "${FORMER}" \
            openclaw.mjs sessions --json 2>&1)
        if [[ "${TURN}" != *pong* || "${SESSIONS_BEFORE}" != *agent:main* ]]; then
            _fail "state_of_${RELEASE}_written" "the former release held no agent turn: $(echo "${TURN}" | tail -n 10) — sessions: $(echo "${SESSIONS_BEFORE}" | tail -n 5)"
            continue
        fi

        # the gateway image starts on the state of the former release
        docker run -d --name "${NAME}" --network none -v "${VOLUME}:/home/node/.openclaw" "${BASE_ENV[@]}" "${IMAGE}" >/dev/null
        if wait_healthy "${NAME}"; then
            _pass "state_of_${RELEASE}_migrated"
        else
            _fail "state_of_${RELEASE}_migrated" "$(docker logs --tail 30 "${NAME}" 2>&1)"
            continue
        fi

        SESSIONS_AFTER=$(docker exec "${NAME}" node openclaw.mjs sessions --json 2>&1)
        if [[ "${SESSIONS_AFTER}" == *agent:main* ]]; then
            _pass "session_of_${RELEASE}_kept"
        else
            _fail "session_of_${RELEASE}_kept" "$(echo "${SESSIONS_AFTER}" | tail -n 10)"
        fi

        # the migration rewrites openclaw.json and keeps a backup of it
        STORED=$(docker exec "${NAME}" sh -c 'cat "$HOME"/.openclaw/openclaw.json*' 2>&1)
        if [[ "${STORED}" != *test-token* && "${STORED}" == *'${OPENCLAW_GATEWAY_TOKEN}'* ]]; then
            _pass "no_token_after_migration_of_${RELEASE}"
        else
            _fail "no_token_after_migration_of_${RELEASE}" "openclaw.json or its backup holds the token or lacks its placeholder"
        fi

        # the log is read whole before it is searched: under pipefail, a grep
        # that stops at its first hit fails the docker logs that still writes
        docker restart "${NAME}" >/dev/null
        HEALTHY=""
        wait_healthy "${NAME}" && HEALTHY=yes
        LOG=$(docker logs "${NAME}" 2>&1)
        if [[ -n "${HEALTHY}" && "${LOG}" == *"state already migrated"* ]]; then
            _pass "restart_after_${RELEASE}_without_migration"
        else
            _fail "restart_after_${RELEASE}_without_migration" "$(grep -A6 -E 'Migrating OpenClaw State|state (already )?migrated|WARN: openclaw doctor' <<<"${LOG}")"
        fi
        docker rm -f "${NAME}" >/dev/null 2>&1
    done
fi

echo ""
echo "==> State migration contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
