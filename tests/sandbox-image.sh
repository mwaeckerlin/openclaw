#!/usr/bin/env bash
# Sandbox image contract: the sandbox starts on its workspace volume, every
# time, and installs the skills it ships into the workspaces.
#
#   - every skill the image ships lies in a directory of its own under
#     /app/skills with its SKILL.md, the MCP gateway and GitHub skills included
#   - the sandbox starts on a fresh volume, mounted as in the stack (the
#     workspace volume on the home directory, the media volume below it),
#     installs the skills into the workspaces and starts sshd; a second start
#     on the same, now filled, volumes does the same
#   - on a volume whose workspaces/skills is a link to the image's /app/skills,
#     the sandbox starts, writes the skills into a real directory on the
#     volume and leaves the image's skills untouched
#
# Needs the built image: `npm run build` (or `docker compose build
# openclaw-sandbox`). Usage: tests/sandbox-image.sh [<image>]

set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${1:-mwaeckerlin/openclaw:sandbox}"
PREFIX="openclaw-sandbox-image-test-$$"
HOME_DIR="/home/somebody"
MCP_SKILLS=(openclaw-mcp-gateway mcp-github)
PASS=0
FAIL=0
declare -a FAILED_NAMES
declare -a CONTAINERS
declare -a VOLUMES=("${PREFIX}-workspace" "${PREFIX}-media" "${PREFIX}-linked")

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

cleanup() {
    [[ ${#CONTAINERS[@]} -gt 0 ]] && docker rm -f "${CONTAINERS[@]}" >/dev/null 2>&1
    docker volume rm "${VOLUMES[@]}" >/dev/null 2>&1
}
trap cleanup EXIT

KEY_ENV=(-e "OPENCLAW_SANDBOX_SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2Uta2V5LWZvci10aGUtdGVzdC1vbmx5LTAwMDA sandbox-test")

# in_image: <command…> — run a command in a throwaway container of the image
in_image() { docker run --rm --network none --entrypoint sh "${IMAGE}" -c "$*"; }

# start_sandbox: <name> <workspace volume> [<media volume>] — start the
# sandbox and wait until sshd runs; fails when the entrypoint ends first
start_sandbox() {
    local name="$1" workspace="$2" media="${3:-}"
    CONTAINERS+=("${name}")
    docker run -d --name "${name}" --network none "${KEY_ENV[@]}" \
        -v "${workspace}:${HOME_DIR}" ${media:+-v "${media}:${HOME_DIR}/workspaces/media"} \
        "${IMAGE}" >/dev/null
    for _ in $(seq 1 60); do
        if [[ "$(docker inspect --format '{{.State.Running}}' "${name}" 2>/dev/null)" != "true" ]]; then
            return 1
        fi
        # the log is read whole before it is searched: under pipefail, a grep
        # that stops at its first hit fails the docker logs that still writes
        if [[ "$(docker logs "${name}" 2>&1)" == *"Starting SSH Daemon"* ]]; then
            sleep 2
            [[ "$(docker inspect --format '{{.State.Running}}' "${name}" 2>/dev/null)" == "true" ]]
            return
        fi
        sleep 1
    done
    return 1
}

# skills_installed: <container> — every skill of the image has its SKILL.md in
# the volume's workspaces/skills, which is a real directory
skills_installed() {
    docker exec "$1" bash -c '
        dir='"${HOME_DIR}"'/workspaces/skills
        [ -d "$dir" ] && [ ! -L "$dir" ] || { echo "$dir is no directory"; exit 1; }
        for skill in /app/skills/*/; do
            name=$(basename "$skill")
            [ -f "$dir/$name/SKILL.md" ] || { echo "$name missing in $dir"; exit 1; }
        done'
}

echo "==> Sandbox image contract: ${IMAGE}"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    _fail "image_present" "${IMAGE} is not built — run npm run build first"
else
    # every skill in a directory of its own; a SKILL.md directly in /app/skills
    # is one copied over the other
    SHIPPED=$(in_image 'for skill in /app/skills/*/; do [ -f "$skill/SKILL.md" ] && basename "$skill"; done; [ -e /app/skills/SKILL.md ] && echo STRAY')
    MISSING=""
    for skill in "${MCP_SKILLS[@]}"; do
        echo "${SHIPPED}" | grep -qx "${skill}" || MISSING="${MISSING} ${skill}"
    done
    if [[ -z "${MISSING}" && "${SHIPPED}" != *STRAY* ]]; then
        _pass "skills_in_image"
    else
        _fail "skills_in_image" "missing:${MISSING:- none}; shipped: $(echo "${SHIPPED}" | tr '\n' ' ')"
    fi

    # first and second start on the volumes as the stack mounts them
    if start_sandbox "${PREFIX}-first" "${PREFIX}-workspace" "${PREFIX}-media" \
        && OUT=$(skills_installed "${PREFIX}-first"); then
        _pass "first_start_installs_skills"
    else
        _fail "first_start_installs_skills" "${OUT:-} $(docker logs --tail 20 "${PREFIX}-first" 2>&1)"
    fi
    docker rm -f "${PREFIX}-first" >/dev/null 2>&1
    if start_sandbox "${PREFIX}-second" "${PREFIX}-workspace" "${PREFIX}-media" \
        && OUT=$(skills_installed "${PREFIX}-second"); then
        _pass "second_start_on_filled_volume"
    else
        _fail "second_start_on_filled_volume" "${OUT:-} $(docker logs --tail 20 "${PREFIX}-second" 2>&1)"
    fi
    docker rm -f "${PREFIX}-second" >/dev/null 2>&1

    # a volume whose skills directory is a link to the image's skills
    docker run --rm --network none -v "${PREFIX}-linked:${HOME_DIR}" --entrypoint sh "${IMAGE}" \
        -c "mkdir -p ${HOME_DIR}/workspaces && ln -s /app/skills ${HOME_DIR}/workspaces/skills" >/dev/null
    if start_sandbox "${PREFIX}-linked" "${PREFIX}-linked" \
        && OUT=$(skills_installed "${PREFIX}-linked") \
        && OUT=$(docker exec "${PREFIX}-linked" bash -c 'for skill in /app/skills/*/; do [ -f "$skill/SKILL.md" ] || { echo "image skill $skill emptied"; exit 1; }; done'); then
        _pass "linked_skills_directory"
    else
        _fail "linked_skills_directory" "${OUT:-} $(docker logs --tail 20 "${PREFIX}-linked" 2>&1)"
    fi
fi

echo ""
echo "==> Sandbox image contract results: ${PASS} passed, ${FAIL} failed"
if [[ ${FAIL} -gt 0 ]]; then
    echo "==> Failed contracts: ${FAILED_NAMES[*]}"
    exit 1
fi
