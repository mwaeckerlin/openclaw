# Changelog

- 2026-09-26 **1.1.2**
    - The image is published for amd64 and arm64 under one tag, built and published automatically on every change and every week
    - The gateway now runs the current OpenClaw release: it builds on the official `openclaw/openclaw` image instead of a third-party copy that had stopped at the release of June 2026
    - The configuration follows the settings of the current OpenClaw release
        - speech output settings, the inbound message delay and the audio transcription model moved to where OpenClaw expects them now; the existing variables keep working
        - the variables of settings OpenClaw retired are gone: the loop detection thresholds, `OPENCLAW_COMMANDS_OWNER_DISPLAY`, `OPENCLAW_CONTROL_UI_ALLOW_INSECURE_AUTH`, `OPENCLAW_CONTROL_UI_DISABLE_DEVICE_AUTH` and `OPENCLAW_TAILSCALE_RESET_ON_EXIT`
        - the BlueBubbles channel and its variables are gone, because OpenClaw removed it; iMessage runs through the iMessage channel (`OPENCLAW_IMESSAGE_*`)
        - WhatsApp message splitting and the Google Chat direct message policy are written where OpenClaw expects them now
        - no proxy is trusted by default any more: OpenClaw refused the MCP gateway and every other container connecting directly, because the former default trusted all docker networks as proxies; behind a reverse proxy its address is set in `OPENCLAW_TRUSTED_PROXIES_JSON`
        - a browser opening the Control UI for the first time now has to be approved once as a device (`openclaw devices approve`), because OpenClaw no longer allows switching that off
        - the section variables follow the configuration sections of OpenClaw: `OPENCLAW_CLI_JSON`, `OPENCLAW_AUDIO_JSON`, `OPENCLAW_MEDIA_JSON`, `OPENCLAW_WEB_JSON` and `OPENCLAW_CANVAS_HOST_JSON` are gone with their sections, new are among others `OPENCLAW_TTS_JSON`, `OPENCLAW_SECURITY_JSON` and `OPENCLAW_PROXY_JSON`
    - Every image build is tested against the OpenClaw release it ships: OpenClaw itself validates the configuration rendered for each group of settings, and the gateway has to start and answer its health check
    - README corrected: docker-in-docker runs rootless, the port 18790 no longer exists, test and publishing instructions added

- 2026-07-28 **1.1.1**
    - Docker-in-docker is now rootless: the sandbox's docker service runs the hardened mwaeckerlin/dockindock image instead of the foreign root-daemon docker:dind — a compromise of the inner daemon no longer yields a root process, and inner images persist on the daemon's real data path
        - no host configuration is needed for this (no AppArmor profile, no sysctl change)
        - inner images from the previous root daemon are not reused; they are simply pulled again on first use
    - The sandbox now builds on the shared base image mwaeckerlin/sandbox-base: the complete toolset, the hardened SSH configuration and the docker client are maintained and tested once for all agent sandboxes — the openclaw sandbox only adds its skills and entrypoint
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
