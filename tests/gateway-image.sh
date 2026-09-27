#!/usr/bin/env bash
# Gateway image contract: the built image runs the OpenClaw release it ships,
# and that release accepts the configuration the entrypoint renders.
#
#   - the image builds on the official openclaw/openclaw:latest the build pulled
#   - for every group of environment variables the template reacts to, the
#     entrypoint renders a configuration that `openclaw config validate`
#     accepts — a key the current OpenClaw schema no longer knows fails here
#   - the gateway starts with the rendered configuration and answers /healthz
#
# The containers run without network: model discovery then fails fast with a
# warning, exactly as it does when a provider is unreachable.
#
# Needs the built image: `npm run build` (or `docker compose build
# openclaw-gateway`). Usage: tests/gateway-image.sh [<image>]

set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-mwaeckerlin/openclaw:gateway}"
# the base the build pulls; `pull: true` in docker-compose.yml keeps it current
BASE_IMAGE="openclaw/openclaw:latest"
NAME="openclaw-gateway-image-test-$$"
PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1; }
trap cleanup EXIT

BASE_ENV=(
    -e OPENCLAW_GATEWAY_TOKEN=test-token
    -e "OPENCLAW_SANDBOX_SSH_PRIVATE_KEY=-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----"
)

echo "==> Gateway image contract: ${IMAGE}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    _fail "image_present" "${IMAGE} is not built — run npm run build first"
else
    _pass "image_present"

    # the layers of the official image the build pulled must open the layer
    # list of the gateway image; a source label proves nothing, a copy built
    # from the upstream Dockerfile carries the same one. BuildKit keeps the
    # base it pulled in its own cache, so on a fresh runner the image store
    # does not hold it and it is pulled here for the comparison
    docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1 || docker pull --quiet "${BASE_IMAGE}" >/dev/null
    BASE_LAYERS=$(docker image inspect --format '{{join .RootFS.Layers " "}}' "${BASE_IMAGE}" 2>/dev/null)
    IMAGE_LAYERS=$(docker image inspect --format '{{join .RootFS.Layers " "}}' "${IMAGE}")
    if [[ -n "${BASE_LAYERS}" && "${IMAGE_LAYERS}" == "${BASE_LAYERS}"* ]]; then
        _pass "official_openclaw_base"
    else
        _fail "official_openclaw_base" "${IMAGE} is not built on the layers of ${BASE_IMAGE}"
    fi

    VERSION=$(docker run --rm --network none --entrypoint node "${IMAGE}" openclaw.mjs --version 2>&1)
    echo "        OpenClaw in the image: ${VERSION}"

    # validate: <name> <env…> — render with the entrypoint, validate with OpenClaw
    validate() {
        local name="$1"
        shift
        local out
        if out=$(docker run --rm --network none "${BASE_ENV[@]}" "$@" "${IMAGE}" node openclaw.mjs config validate 2>&1); then
            _pass "config_valid_${name}"
        else
            _fail "config_valid_${name}" "$(echo "${out}" | tail -n 15)"
        fi
    }

    validate defaults
    validate model_providers \
        -e OPENAI_API_KEY=sk-test \
        -e OPENROUTER_API_KEY=or-test \
        -e ANTHROPIC_API_KEY=an-test \
        -e GOOGLE_API_KEY=gg-test
    validate litellm \
        -e LITELLM_MASTER_KEY=llm-test \
        -e LITELLM_BASE_URL=http://litellm:4000
    validate chat_channels \
        -e OPENCLAW_TELEGRAM_BOT_TOKEN=123:tg \
        -e OPENCLAW_DISCORD_BOT_TOKEN=dc-test \
        -e OPENCLAW_SLACK_BOT_TOKEN=xoxb-test \
        -e OPENCLAW_SLACK_APP_TOKEN=xapp-test \
        -e OPENCLAW_WHATSAPP_ENABLED=true
    validate more_chat_channels \
        -e OPENCLAW_MATTERMOST_BOT_TOKEN=mm-test \
        -e OPENCLAW_MATTERMOST_BASE_URL=https://mattermost.example \
        -e OPENCLAW_MATRIX_HOMESERVER=https://matrix.example \
        -e OPENCLAW_MATRIX_ACCESS_TOKEN=mx-test \
        -e OPENCLAW_MSTEAMS_APP_ID=ms-id \
        -e OPENCLAW_MSTEAMS_APP_PASSWORD=ms-test \
        -e OPENCLAW_MSTEAMS_TENANT_ID=ms-tenant \
        -e OPENCLAW_IRC_ENABLED=true \
        -e OPENCLAW_IRC_HOST=irc.example \
        -e OPENCLAW_IRC_PORT=6697 \
        -e OPENCLAW_IRC_TLS=true \
        -e OPENCLAW_SIGNAL_ACCOUNT=+41000000000 \
        -e OPENCLAW_IMESSAGE_ENABLED=true \
        -e OPENCLAW_GOOGLECHAT_SERVICE_ACCOUNT_FILE=/run/secrets/googlechat.json
    validate speech_and_scheduling \
        -e OPENCLAW_TTS_PROVIDER=openai \
        -e OPENCLAW_TTS_MODEL_OVERRIDES_ENABLED=false \
        -e OPENCLAW_CRON_ENABLED=true \
        -e OPENCLAW_BASE_PATH=/openclaw \
        -e 'OPENCLAW_ALLOWED_ORIGINS_JSON=["https://openclaw.example"]'
    validate tools_and_skills \
        -e OPENCLAW_BRAVE_API_KEY=br-test \
        -e OPENCLAW_GITHUB_TOKEN=gh-test \
        -e OPENCLAW_GITEA_HOST=https://gitea.example \
        -e OPENCLAW_GITEA_TOKEN=gt-test \
        -e OPENCLAW_NOTION_API_KEY=nt-test \
        -e OPENCLAW_TRELLO_API_KEY=tr-test \
        -e OPENCLAW_ELEVENLABS_API_KEY=el-test

    docker run -d --name "${NAME}" --network none "${BASE_ENV[@]}" "${IMAGE}" >/dev/null
    HEALTHY=""
    for _ in $(seq 1 90); do
        if docker exec "${NAME}" node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
            HEALTHY=yes
            break
        fi
        if [[ "$(docker inspect --format '{{.State.Running}}' "${NAME}" 2>/dev/null)" != "true" ]]; then
            break
        fi
        sleep 2
    done
    # /healthz also answers after the gateway rejected keys of its
    # configuration or migrated retired ones away at startup (it then runs on
    # built-in defaults), so its log must report neither
    REJECTED=$(docker logs "${NAME}" 2>&1 | grep -iE 'config is invalid|unrecognized key|invalid config|legacy config keys')
    if [[ -n "${HEALTHY}" && -z "${REJECTED}" ]]; then
        _pass "gateway_answers_healthz"
    else
        _fail "gateway_answers_healthz" "$(docker logs --tail 30 "${NAME}" 2>&1)"
    fi
fi

echo ""
echo "==> Gateway image contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
