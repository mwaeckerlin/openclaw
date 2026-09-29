# Tests

Register of all tests, grouped by kind and sorted by the [FEATURES.md](FEATURES.md) number each test covers. `npm test` runs everything; the guard `tests/docs-contract.sh` fails when a feature has no test entry here or when any test carries a skip, todo or only marker — tests are never skipped.

The sandbox toolset and SSH behaviour are tested end to end in the [mwaeckerlin/sandbox-base] project (this stack consumes that image); the rootless docker-in-docker daemon is tested end to end in the [mwaeckerlin/dockindock] project; the removal of tokens from everything the MCP bridge returns to the sandbox, log lines included, is tested in the [mwaeckerlin/openclaw-mcp-gateway] project (F10 there).

## Stack tests

`npm run test:stack` starts gateway and sandbox with test credentials under a compose project of its own and removes it again (`npm run build` first).

- **F8** `tests/stack-security.sh` › stack_starts, agent_tool_policy — in the running stack, `openclaw sandbox explain` shows sandboxed sessions whose tool policy grants none of `secrets`, `gateway`, `web_fetch`, `web_search`, `browser`, `nodes`, `canvas`, and elevated mode switched off and not allowed by the configuration.
- **F8** `tests/stack-security.sh` › sandbox_holds_no_credential — the sandbox container holds none of the gateway's test credentials in its environment and no Docker secret file.

## Delegation tests

`npm run test:opencode` runs against the built sandbox image (`npm run build` first).

- **F9** `tests/opencode-delegation.sh` › sandbox_has_opencode_client, task_delegated_and_answered — the sandbox image carries the OpenCode client and `opencode-delegate`, which hands a task to an OpenCode server (its model the recording endpoint of `tests/openai-stub.cjs`), prints the answer and the session id, and continues that session with a follow-up.
- **F9** `tests/opencode-delegation.sh` › password_server_refuses_sandbox — a server with `OPENCODE_SERVER_PASSWORD` refuses the sandbox, which holds no password: `opencode-delegate` ends with exit 5 and the message about HTTP 401, never a parser error, while the server answers a client that has the password.
- **F9** `tests/opencode-delegation.sh` › unreachable_server_reported, stalled_server_ends_the_wait — an address nobody answers on ends with exit 4 and its message; a server that takes the connection and never answers ends the wait after `OPENCLAW_OPENCODE_TIMEOUT` seconds (3 in the test) with exit 4 and the message.

## Image tests

`npm run test:image` runs against the built gateway image (`npm run build` first).

- **F1** `tests/gateway-image.sh` › official_openclaw_base — the layers of the official `openclaw/openclaw:latest` the build pulled open the layer list of the gateway image; an image built on a copy fails.
- **F1** `tests/gateway-image.sh` › config_valid_defaults, config_valid_model_providers, config_valid_litellm, config_valid_chat_channels, config_valid_more_chat_channels, config_valid_speech_and_scheduling, config_valid_tools_and_skills — for each group of environment variables, the configuration the entrypoint renders passes `openclaw config validate` of the OpenClaw release in the image.
- **F1** `tests/gateway-image.sh` › gateway_answers_healthz — the gateway starts with the rendered configuration, its log reports neither rejected nor retired keys it had to migrate away, and it answers `/healthz`.
- **F5** `tests/gateway-image.sh` › fresh_volume_writable — on a fresh named volume, the gateway writes its configuration.
- **F7** `tests/gateway-image.sh` › config_valid_hindsight_and_litellm_without_key, config_valid_hindsight_and_litellm_with_scoped_keys — the configuration with both Hindsight banks as MCP servers, with and without their key, and LiteLLM by its base URL alone or with a scoped key passes `openclaw config validate`.
- **F8** `tests/gateway-image.sh` › litellm_called_without_key — with `LITELLM_BASE_URL` alone, a model call reaches a recording OpenAI-compatible endpoint and carries only the public placeholder `Bearer proxy-supplied`, model discovery carries no header at all.
- **F8** `tests/gateway-image.sh` › no_token_in_stored_config, placeholder_token_resolved — `openclaw.json` on the volume holds `${OPENCLAW_GATEWAY_TOKEN}` and never the token, and the running gateway accepts the token it resolved from its environment and refuses a wrong one.
- **F8** `tests/gateway-image.sh` › credentials_from_docker_secrets — the gateway takes its token and the scoped LiteLLM key from Docker secret files in `/run/secrets`, accepts that token, and writes neither into `openclaw.json`.

## Contract and data flow tests

- **F1** `tests/render-config.test.mjs` › config template rendering — the environment-driven OpenClaw configuration renders correctly from the template.
- **F4** `tests/render-config.test.mjs` › no proxy is trusted by default, so containers of the stack (the MCP gateway) reach the gateway directly; `OPENCLAW_TRUSTED_PROXIES_JSON` sets the real proxy.
- **F1** `tests/render-config.test.mjs` › every variable the template reads is passed to the gateway by docker-compose.yml.
- **F7** `tests/render-config.test.mjs` › the Hindsight banks become MCP servers from the environment; `OPENCLAW_MCP_JSON` still replaces the whole section.
- **F8** `tests/render-config.test.mjs` › no secret value is written into openclaw.json, only its placeholder; secret values containing JSON or template syntax never reach the configuration; litellm is enabled by its base URL alone and then carries no key; a scoped LiteLLM key and the Hindsight key reach the configuration only as placeholders; the agent has no tool to request a credential and no path out of the sandbox by default.
- **F1** `tests/compose-contract.sh` › compose_renders, only_mwaeckerlin_images — the stack renders and deploys only mwaeckerlin images.
- **F2** `tests/compose-contract.sh` › sandbox_from_shared_base, only_dind_privileged — the sandbox builds on the shared base and runs unprivileged.
- **F2** `tests/compose-contract.sh` › skills_copied — the agent skills are installed into the sandbox image.
- **F3** `tests/compose-contract.sh` › dind_is_rootless_dockindock, docker_host_port_wired, dind_volume_on_data_root — the sandbox's `DOCKER_HOST` matches the rootless dind service and its port, storage sits on the daemon's real data path.
- **F4** `tests/compose-contract.sh` › skills_copied — MCP gateway and GitHub skills reach the sandbox; the service URLs are part of the rendered stack (compose_renders).
- **F5** `tests/compose-contract.sh` › no_foreign_owner_on_config_volume — no service hands the gateway's config volume to another user.

## Workflow contract

- **F6** `tests/workflow-contract.sh` of `mwaeckerlin/scratch` — the reusable workflow selects exactly the images a repository publishes; this repository calls it from `.github/workflows/docker.yml`.

[mwaeckerlin/sandbox-base]: https://github.com/mwaeckerlin/sandbox-base
[mwaeckerlin/dockindock]: https://github.com/mwaeckerlin/dockindock
[mwaeckerlin/openclaw-mcp-gateway]: https://github.com/mwaeckerlin/openclaw-mcp-gateway
