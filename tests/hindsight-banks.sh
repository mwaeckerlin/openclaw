#!/usr/bin/env bash
# Hindsight bank contract: the gateway reaches both Hindsight banks with the
# key of the Docker secret openclaw_hindsight_api_key, as in the swarm.
#
#   - a real Hindsight that demands its tenant key serves the banks of
#     OPENCLAW_HINDSIGHT_SHARED_URL and OPENCLAW_HINDSIGHT_OWN_URL; the key
#     reaches the gateway only as the secret file, never in the environment
#     the container was started with
#   - Hindsight answers an MCP request without the key and with a wrong key
#     with 401, so a session it opens is one that carried the key
#   - in an agent turn through the gateway, Hindsight opens an MCP session for
#     each of the two banks and answers their tool list; OpenClaw offers the
#     model these tools behind its tool_search, so the model stub sees none
#     of their names
#   - with a wrong key in the secret, the agent turn still answers, and
#     Hindsight opens no session for the gateway
#
# The sessions run without the sandbox, which this test does not start; the
# MCP connect runs in the gateway process, the only one that holds the key.
#
# Needs the built image: `npm run build` (or `docker compose build
# openclaw-gateway`). Usage: tests/hindsight-banks.sh [<image>]

set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-mwaeckerlin/openclaw:gateway}"
HINDSIGHT_IMAGE="ghcr.io/vectorize-io/hindsight:latest"
PREFIX="openclaw-hindsight-banks-test-$$"
NETWORK="${PREFIX}"
STUB="${PREFIX}-stub"
HINDSIGHT="${PREFIX}-hindsight"
TENANT_KEY="openclaw-hindsight-test-key"
SECRETS_DIR="$(mktemp -d)"
PASS=0
FAIL=0
declare -a FAILED_NAMES
declare -a CONTAINERS=("${STUB}" "${HINDSIGHT}")

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

cleanup() {
    docker rm -f "${CONTAINERS[@]}" >/dev/null 2>&1
    docker network rm "${NETWORK}" >/dev/null 2>&1
    rm -rf "${SECRETS_DIR}"
}
trap cleanup EXIT

# wait_healthy: <container> — until the gateway answers /healthz or stops
wait_healthy() {
    for _ in $(seq 1 150); do
        if docker exec "$1" node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
            return 0
        fi
        if [[ "$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null)" != "true" ]]; then
            return 1
        fi
        sleep 2
    done
    return 1
}

# start_gateway: <name> <key> — the gateway with the key as the secret file
# openclaw_hindsight_api_key and both banks; prints nothing, fails when the
# gateway does not answer /healthz
start_gateway() {
    local name="$1" key="$2"
    CONTAINERS+=("${name}")
    rm -rf "${SECRETS_DIR}/secrets"
    mkdir -p "${SECRETS_DIR}/secrets"
    printf '%s' "${key}" > "${SECRETS_DIR}/secrets/openclaw_hindsight_api_key"
    docker create --name "${name}" --network "${NETWORK}" \
        -e OPENCLAW_GATEWAY_TOKEN=test-token \
        -e "OPENCLAW_SANDBOX_SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----" \
        -e OPENCLAW_AGENT_SANDBOX_MODE=off \
        -e "LITELLM_BASE_URL=http://${STUB}:4000" \
        -e OPENCLAW_PRIMARY_MODEL=litellm/stub-model \
        -e 'OPENCLAW_LITELLM_MODELS_JSON=[{"id":"stub-model","name":"stub-model"}]' \
        -e "OPENCLAW_HINDSIGHT_SHARED_URL=http://${HINDSIGHT}:8888/mcp/shared/" \
        -e "OPENCLAW_HINDSIGHT_OWN_URL=http://${HINDSIGHT}:8888/mcp/openclaw/" \
        "${IMAGE}" >/dev/null
    docker cp "${SECRETS_DIR}/secrets" "${name}:/run/secrets" >/dev/null
    docker start "${name}" >/dev/null
    wait_healthy "${name}"
}

# agent_turn: <gateway> — one agent turn through the gateway; prints its output
agent_turn() {
    docker exec "$1" node openclaw.mjs agent --agent main --message "Reply with exactly: pong" --json 2>&1
}

# count_in_hindsight_log: <text> — how many lines of the Hindsight log carry it
count_in_hindsight_log() {
    docker logs "${HINDSIGHT}" 2>&1 | grep -cF "$1"
}

# mcp_status: <key or empty> — the HTTP status Hindsight answers an MCP
# initialize on the shared bank with
mcp_status() {
    docker exec "${STUB}" node -e '
        const headers = { "content-type": "application/json", accept: "application/json, text/event-stream" }
        if (process.argv[2]) headers.authorization = "Bearer " + process.argv[2]
        fetch(process.argv[1], { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize",
            params: { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "probe", version: "1" } } }) })
            .then((response) => console.log(response.status)).catch((error) => console.log(error.message))
    ' "http://${HINDSIGHT}:8888/mcp/shared/" "$1" 2>&1
}

SESSION_LINE="Created new transport with session ID"
TOOLS_LINE="Processing request of type ListToolsRequest"

echo "==> Hindsight bank contract: ${IMAGE}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    _fail "image_present" "${IMAGE} is not built — run npm run build first"
else
    docker network create "${NETWORK}" >/dev/null
    docker run -d --name "${STUB}" --network "${NETWORK}" --entrypoint node "${IMAGE}" -e "$(cat tests/openai-stub.cjs)" >/dev/null
    # the mock LLM of Hindsight derives facts from the stored text, no LLM key
    # needed; the tenant extension refuses every request without the key
    docker run -d --name "${HINDSIGHT}" --network "${NETWORK}" \
        -e HINDSIGHT_API_HOST=0.0.0.0 -e HINDSIGHT_API_PORT=8888 \
        -e HINDSIGHT_API_LLM_PROVIDER=mock -e HINDSIGHT_API_LLM_MODEL=mock-model \
        -e HINDSIGHT_API_TENANT_EXTENSION=hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension \
        -e "HINDSIGHT_API_TENANT_API_KEY=${TENANT_KEY}" \
        -e HINDSIGHT_API_WORKER_ID=hindsight \
        "${HINDSIGHT_IMAGE}" >/dev/null
    HINDSIGHT_UP=""
    for _ in $(seq 1 120); do
        if docker exec "${HINDSIGHT}" python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8888/health', timeout=5)" >/dev/null 2>&1; then
            HINDSIGHT_UP=yes
            break
        fi
        sleep 3
    done
    if [[ -z "${HINDSIGHT_UP}" ]]; then
        _fail "hindsight_starts" "$(docker logs --tail 30 "${HINDSIGHT}" 2>&1)"
    else
        # the tenant check of Hindsight is on: no key and a wrong key are refused
        WITHOUT_KEY=$(mcp_status "")
        WRONG_KEY=$(mcp_status "not-the-tenant-key")
        if [[ "${WITHOUT_KEY}" == 401 && "${WRONG_KEY}" == 401 ]]; then
            _pass "hindsight_refuses_without_the_key"
        else
            _fail "hindsight_refuses_without_the_key" "without key: ${WITHOUT_KEY}, wrong key: ${WRONG_KEY}"
        fi

        # the key of the secret: Hindsight opens a session for each bank and
        # answers its tool list
        GATEWAY="${PREFIX}-gateway"
        SESSIONS_BEFORE=$(count_in_hindsight_log "${SESSION_LINE}")
        TOOL_LISTS_BEFORE=$(count_in_hindsight_log "${TOOLS_LINE}")
        if start_gateway "${GATEWAY}" "${TENANT_KEY}"; then
            TURN=$(agent_turn "${GATEWAY}")
            SESSIONS=$(( $(count_in_hindsight_log "${SESSION_LINE}") - SESSIONS_BEFORE ))
            TOOL_LISTS=$(( $(count_in_hindsight_log "${TOOLS_LINE}") - TOOL_LISTS_BEFORE ))
            if [[ "${TURN}" == *pong* && ${SESSIONS} -ge 2 && ${TOOL_LISTS} -ge 2 ]]; then
                _pass "banks_connect_with_the_secret_key"
            else
                _fail "banks_connect_with_the_secret_key" "${SESSIONS} sessions, ${TOOL_LISTS} tool lists; turn: $(tail -n 5 <<<"${TURN}"); hindsight log: $(docker logs --tail 15 "${HINDSIGHT}" 2>&1)"
            fi
            # the key stays out of the configuration on the volume
            STORED=$(docker exec "${GATEWAY}" cat /home/node/.openclaw/openclaw.json 2>&1)
            if [[ "${STORED}" != *"${TENANT_KEY}"* && "${STORED}" == *'Bearer ${OPENCLAW_HINDSIGHT_API_KEY}'* ]]; then
                _pass "no_hindsight_key_in_stored_config"
            else
                _fail "no_hindsight_key_in_stored_config" "openclaw.json holds the key or lacks its placeholder"
            fi
            docker rm -f "${GATEWAY}" >/dev/null 2>&1
        else
            _fail "banks_connect_with_the_secret_key" "the gateway did not start: $(docker logs --tail 30 "${GATEWAY}" 2>&1)"
        fi

        # a wrong key: the agent turn still answers, and Hindsight opens no
        # session for the gateway
        WRONG="${PREFIX}-wrong-key"
        SESSIONS_BEFORE=$(count_in_hindsight_log "${SESSION_LINE}")
        if start_gateway "${WRONG}" "not-the-tenant-key"; then
            TURN=$(agent_turn "${WRONG}")
            SESSIONS=$(( $(count_in_hindsight_log "${SESSION_LINE}") - SESSIONS_BEFORE ))
            if [[ "${TURN}" == *pong* && ${SESSIONS} -eq 0 ]]; then
                _pass "wrong_key_refused"
            else
                _fail "wrong_key_refused" "${SESSIONS} sessions; turn: $(tail -n 5 <<<"${TURN}"); hindsight log: $(docker logs --tail 15 "${HINDSIGHT}" 2>&1)"
            fi
        else
            _fail "wrong_key_refused" "the gateway did not start: $(docker logs --tail 30 "${WRONG}" 2>&1)"
        fi
    fi
fi

echo ""
echo "==> Hindsight bank contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
