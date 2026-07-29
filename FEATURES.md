# Features

Numbered register of every end-user visible feature; a number is never
reused. Every feature is covered by tests listed in [TESTS.md](TESTS.md);
the guard `tests/docs-contract.sh` fails when a feature has no test.

- **F1 — OpenClaw agent gateway, fully configurable via environment.** The
  gateway service runs OpenClaw with messaging channels, model providers,
  tools and policies configured entirely through environment variables,
  rendered into the OpenClaw configuration at startup.
- **F2 — Isolated SSH sandbox with the full development toolset.** The
  agent works in a separate container (key-only SSH, unprivileged user)
  built on the shared [mwaeckerlin/sandbox-base] — compilers, language
  runtimes, media/LaTeX tools, database clients — with the OpenClaw agent
  skills preinstalled and synced into workspaces.
- **F3 — Docker-in-docker for the sandbox.** The sandbox can build and run
  containers against a dedicated rootless
  [mwaeckerlin/dockindock] daemon on an isolated network — a compromise of
  the inner daemon never yields root, and inner images persist across
  restarts.
- **F4 — MCP integrations.** The OpenClaw MCP gateway and the GitHub MCP
  service are wired into both the gateway and the sandbox (skills and
  service URLs).
- **F5 — Persistent state with correct ownership.** Gateway configuration
  and sandbox workspaces live on named volumes; ownership is bootstrapped
  automatically so the unprivileged users can write.

[mwaeckerlin/sandbox-base]: https://github.com/mwaeckerlin/sandbox-base
[mwaeckerlin/dockindock]: https://github.com/mwaeckerlin/dockindock
