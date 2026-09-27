# Tests

Register of all tests, grouped by kind and sorted by the [FEATURES.md](FEATURES.md) number each test covers. `npm test` runs everything; the guard `tests/docs-contract.sh` fails when a feature has no test entry here or when any test carries a skip, todo or only marker — tests are never skipped.

The sandbox toolset and SSH behaviour are tested end to end in the [mwaeckerlin/sandbox-base] project (this stack consumes that image); the rootless docker-in-docker daemon is tested end to end in the [mwaeckerlin/dockindock] project.

## Image tests

`npm run test:image` runs against the built gateway image (`npm run build` first).

- **F1** `tests/gateway-image.sh` › official_openclaw_base — the layers of the official `openclaw/openclaw:latest` the build pulled open the layer list of the gateway image; an image built on a copy fails.
- **F1** `tests/gateway-image.sh` › config_valid_defaults, config_valid_model_providers, config_valid_litellm, config_valid_chat_channels, config_valid_more_chat_channels, config_valid_speech_and_scheduling, config_valid_tools_and_skills — for each group of environment variables, the configuration the entrypoint renders passes `openclaw config validate` of the OpenClaw release in the image.
- **F1** `tests/gateway-image.sh` › gateway_answers_healthz — the gateway starts with the rendered configuration, its log reports neither rejected nor retired keys it had to migrate away, and it answers `/healthz`.

## Contract and data flow tests

- **F1** `tests/render-config.test.mjs` › config template rendering — the environment-driven OpenClaw configuration renders correctly from the template.
- **F4** `tests/render-config.test.mjs` › no proxy is trusted by default, so containers of the stack (the MCP gateway) reach the gateway directly; `OPENCLAW_TRUSTED_PROXIES_JSON` sets the real proxy.
- **F1** `tests/render-config.test.mjs` › every variable the template reads is passed to the gateway by docker-compose.yml.
- **F1** `tests/compose-contract.sh` › compose_renders, only_mwaeckerlin_images — the stack renders and deploys only mwaeckerlin images.
- **F2** `tests/compose-contract.sh` › sandbox_from_shared_base, only_dind_privileged — the sandbox builds on the shared base and runs unprivileged.
- **F2** `tests/compose-contract.sh` › skills_copied — the agent skills are installed into the sandbox image.
- **F3** `tests/compose-contract.sh` › dind_is_rootless_dockindock, docker_host_port_wired, dind_volume_on_data_root — the sandbox's `DOCKER_HOST` matches the rootless dind service and its port, storage sits on the daemon's real data path.
- **F4** `tests/compose-contract.sh` › skills_copied — MCP gateway and GitHub skills reach the sandbox; the service URLs are part of the rendered stack (compose_renders).
- **F5** `tests/compose-contract.sh` › ownership_bootstrap_present — the ownership bootstrap service is part of the stack.

## Workflow contract

- **F6** `tests/workflow-contract.sh` of `mwaeckerlin/scratch` — the reusable workflow selects exactly the images a repository publishes; this repository calls it from `.github/workflows/docker.yml`.

[mwaeckerlin/sandbox-base]: https://github.com/mwaeckerlin/sandbox-base
[mwaeckerlin/dockindock]: https://github.com/mwaeckerlin/dockindock
