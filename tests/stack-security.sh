#!/usr/bin/env bash
# Stack security contract: in the running stack, the AI agent can neither
# reach a credential nor ask for one.
#
#   - the agent's sessions are sandboxed, and their tool policy grants no tool
#     that requests a credential (secrets), runs in the gateway (gateway,
#     elevated exec) or reaches the web (web_fetch, web_search, browser)
#   - elevated mode is switched off
#   - the sandbox container, where the agent's commands run, holds none of the
#     credentials the gateway holds, neither in its environment nor as a
#     Docker secret file
#
# Starts gateway and sandbox (with docker-in-docker and the GitHub MCP
# service they depend on) under a compose project of its own with test
# credentials, and removes everything again. Needs the built images
# (`npm run build`). Usage: tests/stack-security.sh

set -uo pipefail
cd "$(dirname "$0")/.."

PROJECT="openclaw-stack-test-$$"
WORK="$(mktemp -d)"
ENV_FILE="${WORK}/stack.env"
PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

compose() { docker compose --env-file "${ENV_FILE}" -p "${PROJECT}" "$@"; }

cleanup() {
    compose down -v --remove-orphans >/dev/null 2>&1
    rm -rf "${WORK}"
}
trap cleanup EXIT

# every value below is a credential of the gateway; none may reach the agent
SECRET_VALUES=(
    stack-test-gateway-token
    sk-stack-test-openai
    123456789:stack-test-telegram-token-AAAAAAAAAAAAAAAA
    stack-test-discord-token
    stack-test-github-token
    stack-test-litellm-key
    stack-test-hindsight-key
)

ssh-keygen -q -t ed25519 -N "" -C stack-test -f "${WORK}/key"
{
    echo "OPENCLAW_GATEWAY_TOKEN=${SECRET_VALUES[0]}"
    echo "OPENCLAW_SANDBOX_SSH_PUBLIC_KEY=$(cat "${WORK}/key.pub")"
    echo "OPENCLAW_SANDBOX_SSH_PRIVATE_KEY=$(sed -z 's/\n/\\n/g' "${WORK}/key")"
    echo "OPENAI_API_KEY=${SECRET_VALUES[1]}"
    echo "OPENCLAW_TELEGRAM_BOT_TOKEN=${SECRET_VALUES[2]}"
    echo "OPENCLAW_DISCORD_BOT_TOKEN=${SECRET_VALUES[3]}"
    echo "OPENCLAW_GITHUB_TOKEN=${SECRET_VALUES[4]}"
    echo "LITELLM_BASE_URL=http://litellm:4000"
    echo "LITELLM_API_KEY=${SECRET_VALUES[5]}"
    echo "OPENCLAW_HINDSIGHT_SHARED_URL=http://hindsight:8888/mcp/shared/"
    echo "OPENCLAW_HINDSIGHT_API_KEY=${SECRET_VALUES[6]}"
} > "${ENV_FILE}"

echo "==> Stack security contract: agent without credentials"

compose up -d --no-build openclaw-sandbox openclaw-gateway >/dev/null 2>&1
GATEWAY="$(compose ps -q openclaw-gateway)"
SANDBOX="$(compose ps -q openclaw-sandbox)"

HEALTHY=""
if [[ -n "${GATEWAY}" ]]; then
    for _ in $(seq 1 300); do
        if docker exec "${GATEWAY}" node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
            HEALTHY=yes
            break
        fi
        sleep 3
    done
fi
if [[ -n "${HEALTHY}" ]]; then
    _pass "stack_starts"
else
    _fail "stack_starts" "$(compose logs --tail 30 2>&1)"
fi

if [[ -n "${HEALTHY}" ]]; then
    EXPLAIN=$(docker exec "${GATEWAY}" node openclaw.mjs sandbox explain --json 2>/dev/null)
    # parse the JSON document out of the command output and check the policy
    POLICY=$(printf '%s' "${EXPLAIN}" | docker exec -i "${GATEWAY}" node -e '
        const text = require("fs").readFileSync(0, "utf8")
        const explain = JSON.parse(text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1))
        const allow = explain.sandbox.tools.allow
        const forbidden = ["secrets", "gateway", "web_fetch", "web_search", "browser", "nodes", "canvas"]
        const problems = []
        if (explain.sandbox.mode !== "all" || explain.sessionIsSandboxed === false) problems.push("sessions not sandboxed: " + explain.sandbox.mode)
        for (const tool of forbidden) if (allow.includes(tool)) problems.push("tool granted: " + tool)
        if (explain.elevated.enabled !== false) problems.push("elevated mode enabled")
        if (explain.elevated.allowedByConfig !== false) problems.push("elevated mode allowed by config")
        console.log(problems.length ? problems.join("; ") : "ok")
    ' 2>&1)
    if [[ "${POLICY}" == "ok" ]]; then
        _pass "agent_tool_policy"
    else
        _fail "agent_tool_policy" "${POLICY}"
    fi
fi

if [[ -n "${SANDBOX}" ]]; then
    SANDBOX_ENV=$(docker exec "${SANDBOX}" env 2>&1)
    SANDBOX_SECRET_FILES=$(docker exec "${SANDBOX}" sh -c 'ls /run/secrets 2>/dev/null' 2>&1)
    LEAKED=""
    for value in "${SECRET_VALUES[@]}"; do
        [[ "${SANDBOX_ENV}" == *"${value}"* ]] && LEAKED="${LEAKED} ${value}"
    done
    if [[ -z "${LEAKED}" && -z "${SANDBOX_SECRET_FILES}" ]]; then
        _pass "sandbox_holds_no_credential"
    else
        _fail "sandbox_holds_no_credential" "in the sandbox:${LEAKED} ${SANDBOX_SECRET_FILES}"
    fi
else
    _fail "sandbox_holds_no_credential" "sandbox container not running"
fi

echo ""
echo "==> Stack security contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
