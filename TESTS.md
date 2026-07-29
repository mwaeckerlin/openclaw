# Tests

Register of all tests, grouped by kind and sorted by the
[FEATURES.md](FEATURES.md) number each test covers. `npm test` runs
everything; the guard `tests/docs-contract.sh` fails when a feature has no
test entry here or when any test carries a skip/xfail marker — tests are
never skipped.

The sandbox toolset and SSH behaviour are tested end to end in the
[mwaeckerlin/sandbox-base] project (this stack consumes that image); the
rootless docker-in-docker daemon is tested end to end in the
[mwaeckerlin/dockindock] project.

## Contract-/Datenfluss-Tests

- **F1** `tests/render-config.test.mjs` › config template rendering — the environment-driven OpenClaw configuration renders correctly from the template.
- **F2** `tests/compose-contract.sh` › sandbox_from_shared_base, only_dind_privileged — the sandbox builds on the shared base and runs unprivileged.
- **F2** `tests/compose-contract.sh` › skills_copied — the agent skills are installed into the sandbox image.
- **F3** `tests/compose-contract.sh` › dind_is_rootless_dockindock, docker_host_port_wired, dind_volume_on_data_root — the sandbox's `DOCKER_HOST` matches the rootless dind service and its port, storage sits on the daemon's real data path.
- **F4** `tests/compose-contract.sh` › skills_copied — MCP gateway and GitHub skills reach the sandbox; the service URLs are part of the rendered stack (compose_renders).
- **F5** `tests/compose-contract.sh` › ownership_bootstrap_present — the ownership bootstrap service is part of the stack.
- **F1** `tests/compose-contract.sh` › compose_renders, only_mwaeckerlin_images — the stack renders and deploys only mwaeckerlin images.

[mwaeckerlin/sandbox-base]: https://github.com/mwaeckerlin/sandbox-base
[mwaeckerlin/dockindock]: https://github.com/mwaeckerlin/dockindock
