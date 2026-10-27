#!/usr/bin/env bash
# Local OpenCode contract: OpenCode works in the agent's own sandbox, on its
# checkout, and reaches the model through the gateway that holds the key.
#
#   - the entrypoint hands OPENCODE_GATEWAY_URL, OPENCODE_MODELS and the two
#     memory banks to the SSH sessions of the agent (/etc/environment), and
#     nothing that is a key
#   - in such a session, `opencode run` in a checkout gets the answer of the
#     model, and the model endpoint sees the key the gateway added, while the
#     sandbox sent only the placeholder
#   - the configuration names both memory banks through the gateway
#   - the sandbox holds the key nowhere: not in its environment, not in its
#     configuration, not in a file
#
# The model is the recording OpenAI-compatible endpoint of tests/openai-stub.cjs,
# which answers "pong". Needs the built sandbox image (`npm run build`).
# Usage: tests/opencode-local.sh

set -uo pipefail
cd "$(dirname "$0")"

export OPENCLAW_OPENCODE_LOCAL_KEY="openclaw-opencode-local-key-of-the-test-stack"
COMPOSE=(docker compose -f opencode-local.yml)
PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

cleanup() { "${COMPOSE[@]}" down -v --remove-orphans > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

# as_agent <command>: a shell of the agent's user with the variables an SSH
# session gets from /etc/environment
as_agent() {
    docker exec -u somebody "${SANDBOX}" bash -c "set -a; . /etc/environment; set +a; cd; $1"
}

echo "==> Local OpenCode contract"
"${COMPOSE[@]}" up -d || exit 1
SANDBOX=$("${COMPOSE[@]}" ps -q openclaw-sandbox)

SESSION_ENV=""
for _ in $(seq 1 30); do
    SESSION_ENV=$(docker exec "${SANDBOX}" cat /etc/environment 2> /dev/null)
    grep -q '^HINDSIGHT_OWN_BANK=' <<< "${SESSION_ENV}" && break
    sleep 1
done
if grep -qx 'OPENCODE_GATEWAY_URL=http://openclaw-opencode-gateway:8080' <<< "${SESSION_ENV}" \
    && grep -qx 'OPENCODE_MODELS=stub-model' <<< "${SESSION_ENV}" \
    && grep -qx 'HINDSIGHT_SHARED_BANK=shared' <<< "${SESSION_ENV}" \
    && grep -qx 'HINDSIGHT_OWN_BANK=openclaw' <<< "${SESSION_ENV}"; then
    _pass "gateway_and_models_reach_the_agent"
else
    _fail "gateway_and_models_reach_the_agent" "${SESSION_ENV}; sandbox log: $(docker logs --tail 15 "${SANDBOX}" 2>&1)"
fi

CONFIG=$(as_agent 'opencode --print-config' 2>&1)
if [[ "$(jq -r '.mcp["hindsight-shared"].url, .mcp["hindsight-own"].url' <<< "${CONFIG}" 2> /dev/null | paste -sd ' ')" \
    == "http://openclaw-opencode-gateway:8080/mcp/shared/ http://openclaw-opencode-gateway:8080/mcp/openclaw/" ]]; then
    _pass "memory_banks_through_the_gateway"
else
    _fail "memory_banks_through_the_gateway" "${CONFIG}"
fi

# the session works on a checkout of its own, as the agent does
ANSWER=$(as_agent 'mkdir -p checkout && cd checkout && git init -q && opencode run "Reply with exactly: pong"' 2>&1)
STUB_LOG=$("${COMPOSE[@]}" logs --no-log-prefix stub 2>&1)
if grep -q 'pong' <<< "${ANSWER}" \
    && grep -q "authorization=Bearer ${OPENCLAW_OPENCODE_LOCAL_KEY}" <<< "${STUB_LOG}" \
    && ! grep -q 'the-gateway-replaces-this' <<< "${STUB_LOG}"; then
    _pass "local_task_answered_through_the_gateway"
else
    _fail "local_task_answered_through_the_gateway" "answer: $(tail -n 10 <<< "${ANSWER}"); model saw: $(grep REQUEST <<< "${STUB_LOG}" | tail -n 3)"
fi

if docker exec "${SANDBOX}" env | grep -q "${OPENCLAW_OPENCODE_LOCAL_KEY}"; then
    _fail "no_key_in_sandbox" "the key stands in the environment"
elif grep -q "${OPENCLAW_OPENCODE_LOCAL_KEY}" <<< "${CONFIG}${SESSION_ENV}"; then
    _fail "no_key_in_sandbox" "the key stands in the configuration or the session environment"
elif docker exec "${SANDBOX}" grep -rqs "${OPENCLAW_OPENCODE_LOCAL_KEY}" /run /etc /home /tmp 2> /dev/null; then
    _fail "no_key_in_sandbox" "the key stands in a file"
else
    _pass "no_key_in_sandbox"
fi

echo ""
echo "==> Local OpenCode contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    "${COMPOSE[@]}" logs --tail 30
    exit 1
fi
