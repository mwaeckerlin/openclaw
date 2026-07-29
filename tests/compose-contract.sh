#!/usr/bin/env bash
# Compose contract: the deployment wiring the stack promises.
#
#   - the compose file renders
#   - only mwaeckerlin images are deployed (base-image policy; the foreign
#     root-daemon docker:dind was replaced by rootless dockindock)
#   - the dind service is mwaeckerlin/dockindock, its TCP port matches the
#     sandbox's DOCKER_HOST, and storage sits on the real data path
#   - exactly the dind service is privileged, nothing else
#
# Usage: tests/compose-contract.sh

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
declare -a FAILED_NAMES

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

echo "==> Compose contract: openclaw stack wiring"

if ! CONFIG=$(docker compose config 2>/dev/null); then
    _fail "compose_renders" "docker compose config failed"
else
    _pass "compose_renders"

    FOREIGN=$(echo "${CONFIG}" | grep -E '^\s+image: ' | grep -v 'mwaeckerlin/')
    if [[ -z "${FOREIGN}" ]]; then
        _pass "only_mwaeckerlin_images"
    else
        _fail "only_mwaeckerlin_images" "foreign deployment images: ${FOREIGN}"
    fi

    if echo "${CONFIG}" | grep -q 'image: mwaeckerlin/dockindock'; then
        _pass "dind_is_rootless_dockindock"
    else
        _fail "dind_is_rootless_dockindock" "dind service does not use mwaeckerlin/dockindock"
    fi

    if echo "${CONFIG}" | grep -q 'DOCKER_HOST: tcp://openclaw-dind:2375' \
        && echo "${CONFIG}" | grep -q 'DOCKER_TCP_PORT: "2375"'; then
        _pass "docker_host_port_wired"
    else
        _fail "docker_host_port_wired" "sandbox DOCKER_HOST and dind DOCKER_TCP_PORT do not match"
    fi

    if echo "${CONFIG}" | grep -q 'target: /docker-data'; then
        _pass "dind_volume_on_data_root"
    else
        _fail "dind_volume_on_data_root" "dind volume not mounted on /docker-data"
    fi

    PRIV=$(echo "${CONFIG}" | grep -c 'privileged: true')
    if [[ "${PRIV}" == "1" ]]; then
        _pass "only_dind_privileged"
    else
        _fail "only_dind_privileged" "expected exactly 1 privileged service, found ${PRIV}"
    fi

    if grep -q 'FROM mwaeckerlin/sandbox-base' Dockerfile.sandbox; then
        _pass "sandbox_from_shared_base"
    else
        _fail "sandbox_from_shared_base" "Dockerfile.sandbox does not build on mwaeckerlin/sandbox-base"
    fi

    if grep -q 'COPY --from=mcp_gateway_skills' Dockerfile.sandbox \
        && grep -q 'COPY --from=mcp_github_skills' Dockerfile.sandbox; then
        _pass "skills_copied"
    else
        _fail "skills_copied" "MCP skills not copied into the sandbox"
    fi

    if echo "${CONFIG}" | grep -q 'mwaeckerlin/allow-write-access'; then
        _pass "ownership_bootstrap_present"
    else
        _fail "ownership_bootstrap_present" "allow-write-access service missing"
    fi
fi

echo ""
echo "==> Compose contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
