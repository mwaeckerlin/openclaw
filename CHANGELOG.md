# Changelog

- 2026-07-28 **1.1.1**
    - Docker-in-docker is now rootless: the sandbox's docker service runs the hardened mwaeckerlin/dockindock image instead of the foreign root-daemon docker:dind — a compromise of the inner daemon no longer yields a root process, and inner images persist on the daemon's real data path
        - no host configuration is needed for this (no AppArmor profile, no sysctl change)
        - inner images from the previous root daemon are not reused; they are simply pulled again on first use
    - The sandbox now builds on the shared base image mwaeckerlin/sandbox-base: the complete toolset, the hardened SSH configuration and the docker client are maintained and tested once for all agent sandboxes — the openclaw sandbox only adds its skills and entrypoint
    - Feature and test registers added (FEATURES.md, TESTS.md) with an automatic guard, plus a stack wiring contract test (only mwaeckerlin images deployed, docker host/port wiring, privileges, skills, ownership bootstrap)

- 2026-07-18 **1.1.0**
    - Security hardening based on a static security review
        - Gateway port is now bound to `127.0.0.1` by default; new `OPENCLAW_GATEWAY_BIND_ADDRESS` and honored `OPENCLAW_GATEWAY_PORT` for overrides
        - Telegram now defaults to `pairing` DM policy and mention-required groups, consistent with all other channels
        - Default gateway log level changed from `debug` to `info`; configurable via `OPENCLAW_LOGGING_LEVEL`
        - Secrets and environment values are JSON-escaped when rendered into the configuration and can no longer break or inject into it, nor be evaluated as template syntax
        - Device pairing generator now enforces owner-only permissions on `.env`; setup instructions create `.env` with owner-only permissions
        - Image builds now always try to pull newer base images so upstream security patches reach every rebuild
    - Fixed duplicate LiteLLM provider block in the configuration template
    - Fixed sandbox `/etc/environment` accumulating duplicate entries across restarts
    - Added unit tests for the configuration renderer (`npm test`)
    - Documented security trade-offs (Control UI relaxations, ACPX approve-all, DinD without TLS, channel policies) and fixed the secret-mapping documentation example
