#!/usr/bin/env bash
# OpenCode delegation contract: the agent's sandbox hands a development task to
# a central OpenCode server and gets the result back, headless.
#
#   - the sandbox image carries the OpenCode client and opencode-delegate
#   - `opencode-delegate` from a sandbox reaches an OpenCode server, the task
#     reaches OpenCode's model, and the answer comes back on stdout together
#     with the session id; a follow-up in the same session is answered too
#   - a server with the optional password refuses the sandbox, which holds no
#     password, with a clear message, while it answers a client that has it
#
# The OpenCode server runs from the sandbox image (the same OpenCode release);
# its model is the recording OpenAI-compatible endpoint of tests/openai-stub.cjs,
# which answers "pong". Needs the built sandbox image (`npm run build`).
# Usage: tests/opencode-delegation.sh [<sandbox image>]

set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-mwaeckerlin/openclaw:sandbox}"
NETWORK="openclaw-opencode-test-$$"
STUB="openclaw-opencode-stub-$$"
SERVER="openclaw-opencode-server-$$"
LOCKED="openclaw-opencode-locked-$$"
PASSWORD="opencode-test-password"
PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

cleanup() {
    docker rm -f "${STUB}" "${SERVER}" "${LOCKED}" "openclaw-opencode-stalled-$$" "openclaw-opencode-stalled-$$-client" >/dev/null 2>&1
    docker network rm "${NETWORK}" >/dev/null 2>&1
}
trap cleanup EXIT

# OpenCode's model: the recording endpoint as an OpenAI-compatible provider
OPENCODE_CONFIG=$(printf '{"$schema":"https://opencode.ai/config.json","model":"stub/stub-model","small_model":"stub/stub-model","provider":{"stub":{"npm":"@ai-sdk/openai-compatible","name":"stub","options":{"baseURL":"http://%s:4000/v1","apiKey":"stub"},"models":{"stub-model":{"name":"stub-model"}}}}}' "${STUB}")

# serve: <name> <env…> — an OpenCode server on the test network
serve() {
    local name="$1"
    shift
    docker run -d --name "${name}" --network "${NETWORK}" --entrypoint opencode \
        -e "OPENCODE_CONFIG_CONTENT=${OPENCODE_CONFIG}" "$@" \
        "${IMAGE}" serve --hostname 0.0.0.0 --port 4096 >/dev/null
    for _ in $(seq 1 90); do
        docker run --rm --network "${NETWORK}" --entrypoint curl "${IMAGE}" -s -o /dev/null "http://${name}:4096/" && return 0
        sleep 2
    done
    return 1
}

# delegate: <server> <opencode-delegate arguments…> — one task from a sandbox
delegate() {
    local server="$1"
    shift
    docker run --rm --network "${NETWORK}" -e "OPENCLAW_OPENCODE_URL=http://${server}:4096" \
        --entrypoint opencode-delegate "${IMAGE}" "$@" 2>&1
}

echo "==> OpenCode delegation contract: ${IMAGE}"

VERSION=$(docker run --rm --network none --entrypoint opencode "${IMAGE}" --version 2>&1)
if [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+ ]] \
    && docker run --rm --network none --entrypoint sh "${IMAGE}" -c 'test -x /usr/local/bin/opencode-delegate' >/dev/null 2>&1; then
    _pass "sandbox_has_opencode_client"
    echo "        OpenCode in the sandbox: ${VERSION}"
else
    _fail "sandbox_has_opencode_client" "${VERSION}"
fi

docker network create "${NETWORK}" >/dev/null
docker run -d --name "${STUB}" --network "${NETWORK}" --entrypoint node "${IMAGE}" -e "$(cat tests/openai-stub.cjs)" >/dev/null

if serve "${SERVER}"; then
    ANSWER=$(delegate "${SERVER}" "Reply with exactly: pong")
    SESSION=$(echo "${ANSWER}" | sed -n 's/^OpenCode session: //p')
    FOLLOW_UP=""
    [[ -n "${SESSION}" ]] && FOLLOW_UP=$(delegate "${SERVER}" --session "${SESSION}" "Reply again with exactly: pong")
    if [[ "$(echo "${ANSWER}" | head -n 1)" == "pong" && -n "${SESSION}" && "${FOLLOW_UP}" == pong* ]] \
        && docker logs "${STUB}" 2>&1 | grep -q "Reply again with exactly: pong"; then
        _pass "task_delegated_and_answered"
    else
        _fail "task_delegated_and_answered" "answer: ${ANSWER}; follow-up: ${FOLLOW_UP}; server log: $(docker logs --tail 10 "${SERVER}" 2>&1)"
    fi
else
    _fail "task_delegated_and_answered" "OpenCode server did not start: $(docker logs --tail 15 "${SERVER}" 2>&1)"
fi

if serve "${LOCKED}" -e "OPENCODE_SERVER_PASSWORD=${PASSWORD}"; then
    REFUSED=$(delegate "${LOCKED}" "Reply with exactly: pong")
    REFUSED_STATUS=$?
    OPEN_STATUS=$(docker run --rm --network "${NETWORK}" --entrypoint curl "${IMAGE}" -s -o /dev/null -w '%{http_code}' -u "opencode:${PASSWORD}" "http://${LOCKED}:4096/session")
    if [[ ${REFUSED_STATUS} -eq 5 && "${REFUSED}" == *"HTTP 401"* && "${REFUSED}" != *SyntaxError* && "${OPEN_STATUS}" == "200" ]]; then
        _pass "password_server_refuses_sandbox"
    else
        _fail "password_server_refuses_sandbox" "sandbox without password: exit ${REFUSED_STATUS}, ${REFUSED}; client with password: HTTP ${OPEN_STATUS}"
    fi
else
    _fail "password_server_refuses_sandbox" "OpenCode server with password did not start: $(docker logs --tail 15 "${LOCKED}" 2>&1)"
fi

# an address nobody answers on: the command ends at once with its message
UNREACHABLE=$(docker run --rm --network "${NETWORK}" -e "OPENCLAW_OPENCODE_URL=http://nobody-here-$$:4096" \
    --entrypoint opencode-delegate "${IMAGE}" "Reply with exactly: pong" 2>&1)
UNREACHABLE_STATUS=$?
if [[ ${UNREACHABLE_STATUS} -eq 4 && "${UNREACHABLE}" == *"is not reachable"* && "${UNREACHABLE}" != *SyntaxError* ]]; then
    _pass "unreachable_server_reported"
else
    _fail "unreachable_server_reported" "exit ${UNREACHABLE_STATUS}: ${UNREACHABLE}"
fi

# a server that takes the connection and never answers: the wait ends after
# OPENCLAW_OPENCODE_TIMEOUT seconds with the message, and the agent goes on
STALLED="openclaw-opencode-stalled-$$"
docker run -d --name "${STALLED}" --network "${NETWORK}" --entrypoint node "${IMAGE}" \
    -e 'require("http").createServer(() => {}).listen(4096)' >/dev/null
sleep 2
START=$(date +%s)
# the outer limit keeps a command without its own limit from blocking the suite
STALL=$(timeout 60 docker run --rm --name "${STALLED}-client" --network "${NETWORK}" -e "OPENCLAW_OPENCODE_URL=http://${STALLED}:4096" \
    -e OPENCLAW_OPENCODE_TIMEOUT=3 --entrypoint opencode-delegate "${IMAGE}" "Reply with exactly: pong" 2>&1)
STALL_STATUS=$?
STALL_SECONDS=$(( $(date +%s) - START ))
docker rm -f "${STALLED}" "${STALLED}-client" >/dev/null 2>&1
if [[ ${STALL_STATUS} -eq 4 && "${STALL}" == *"did not answer within 3s"* && ${STALL_SECONDS} -lt 30 ]]; then
    _pass "stalled_server_ends_the_wait"
else
    _fail "stalled_server_ends_the_wait" "exit ${STALL_STATUS} after ${STALL_SECONDS}s: ${STALL}"
fi

echo ""
echo "==> OpenCode delegation contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
