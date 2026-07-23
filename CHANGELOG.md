# Changelog

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
