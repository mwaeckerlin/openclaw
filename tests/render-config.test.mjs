import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const renderScript = join(projectRoot, "files", "render-config.js");
const defaultTemplate = join(projectRoot, "files", "openclaw.json.j2");

const render = (template, env) => {
  const dir = mkdtempSync(join(tmpdir(), "openclaw-render-"));
  const templateFile = join(dir, "template.j2");
  const outputFile = join(dir, "openclaw.json");
  writeFileSync(templateFile, template);
  execFileSync("node", [renderScript, templateFile, outputFile], {
    env: { PATH: process.env.PATH, ...env },
    cwd: projectRoot,
  });
  return JSON.parse(readFileSync(outputFile, "utf8"));
};

const renderDefaultText = (env) => {
  const dir = mkdtempSync(join(tmpdir(), "openclaw-render-"));
  const outputFile = join(dir, "openclaw.json");
  execFileSync("node", [renderScript, defaultTemplate, outputFile], {
    env: { PATH: process.env.PATH, OPENCLAW_GATEWAY_TOKEN: "test-token", ...env },
    cwd: projectRoot,
  });
  return readFileSync(outputFile, "utf8");
};

const renderDefault = (env) => JSON.parse(renderDefaultText(env));

// every secret the template can carry, with a value that must never appear
// in the rendered file
const secrets = {
  OPENCLAW_GATEWAY_TOKEN: "secret-gateway-token",
  LITELLM_MASTER_KEY: "secret-litellm-master",
  OPENROUTER_API_KEY: "secret-openrouter",
  OPENAI_API_KEY: "secret-openai",
  ANTHROPIC_API_KEY: "secret-anthropic",
  GEMINI_API_KEY: "secret-gemini",
  OPENCLAW_WHISPER_API_KEY: "secret-whisper",
  OPENCLAW_TELEGRAM_BOT_TOKEN: "secret-telegram",
  OPENCLAW_DISCORD_BOT_TOKEN: "secret-discord",
  OPENCLAW_SLACK_BOT_TOKEN: "secret-slack-bot",
  OPENCLAW_SLACK_APP_TOKEN: "secret-slack-app",
  OPENCLAW_MATTERMOST_BOT_TOKEN: "secret-mattermost",
  OPENCLAW_MATRIX_ACCESS_TOKEN: "secret-matrix",
  OPENCLAW_MSTEAMS_APP_PASSWORD: "secret-msteams",
  OPENCLAW_IRC_ENABLED: "true",
  OPENCLAW_IRC_NICKSERV_PASSWORD: "secret-nickserv",
  OPENCLAW_NOTION_API_KEY: "secret-notion",
  OPENCLAW_TRELLO_API_KEY: "secret-trello",
  OPENCLAW_ELEVENLABS_API_KEY: "secret-elevenlabs",
  OPENCLAW_BRAVE_API_KEY: "secret-brave",
  OPENCLAW_GITHUB_TOKEN: "secret-github",
  OPENCLAW_GITEA_HOST: "https://gitea.example",
  OPENCLAW_GITEA_TOKEN: "secret-gitea",
};

test("no secret value is written into openclaw.json, only its placeholder", () => {
  const text = renderDefaultText(secrets);
  const leaked = Object.values(secrets).filter((value) => value.startsWith("secret-") && text.includes(value));
  assert.deepEqual(leaked, []);
  const config = JSON.parse(text);
  assert.equal(config.gateway.auth.token, "${OPENCLAW_GATEWAY_TOKEN}");
  assert.equal(config.channels.telegram.botToken, "${OPENCLAW_TELEGRAM_BOT_TOKEN}");
  assert.equal(config.models.providers.openai.apiKey, "${OPENAI_API_KEY}");
});

test("secret values containing JSON or template syntax never reach the configuration", () => {
  const secret = 'pa"ss\\w{{ 7 * 7 }}{% if true %}x{% endif %},}';
  const config = render('{ "token": "${MY_SECRET}", "_end": true }', { MY_SECRET: secret });
  assert.deepEqual(config, { token: "${MY_SECRET}" });
});

test("sentinel _end keys are removed at every nesting level", () => {
  const config = render(
    '{ "a": { "x": 1, "_end": true }, "b": [ { "_end": true } ], "_end": true }',
    {},
  );
  assert.deepEqual(config, { a: { x: 1 }, b: [{}] });
});

test("litellm provider is defined exactly once in the template", () => {
  const template = readFileSync(defaultTemplate, "utf8");
  const matches = template.match(/"litellm":\s*\{/g) ?? [];
  assert.equal(matches.length, 1);
});

test("default logging level is info, not debug", () => {
  const config = renderDefault({});
  assert.equal(config.logging.level, "info");
});

test("telegram channel defaults to pairing policy with mention required", () => {
  const config = renderDefault({ OPENCLAW_TELEGRAM_BOT_TOKEN: "tg-token" });
  assert.equal(config.channels.telegram.dmPolicy, "pairing");
  assert.equal(config.channels.telegram.groups["*"].requireMention, true);
});

test("no proxy is trusted by default, so containers of the stack reach the gateway directly", () => {
  // OpenClaw 2026.9 answers a client from a trusted proxy range without
  // forwarded headers with 403 proxy_attribution_required; the private
  // ranges cover every docker network, so the MCP gateway was refused
  assert.deepEqual(renderDefault({}).gateway.trustedProxies, []);
  const proxies = ["10.1.2.3/32"];
  assert.deepEqual(renderDefault({ OPENCLAW_TRUSTED_PROXIES_JSON: JSON.stringify(proxies) }).gateway.trustedProxies, proxies);
});

test("every variable the template reads is passed to the gateway by docker-compose.yml", () => {
  const template = readFileSync(defaultTemplate, "utf8");
  const tags = template.match(/\{\{[^}]*\}\}|\{%[^%]*%\}|\$\{\w+\}/g).join(" ");
  const read = new Set(tags.match(/\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b/g));
  const compose = readFileSync(join(projectRoot, "docker-compose.yml"), "utf8");
  const gateway = compose.slice(compose.indexOf("openclaw-gateway:"), compose.indexOf("\n  openclaw-sandbox:"));
  const passed = new Set(gateway.match(/^ {6}([A-Z][A-Z0-9_]+):/gm).map((line) => line.trim().slice(0, -1)));
  assert.deepEqual([...read].filter((name) => !passed.has(name)), []);
});

test("default template renders valid config with providers and gateway token", () => {
  const config = renderDefault({
    OPENAI_API_KEY: "sk-test",
    LITELLM_MASTER_KEY: "llm-key",
  });
  assert.equal(config.gateway.auth.token, "${OPENCLAW_GATEWAY_TOKEN}");
  assert.equal(config.models.providers.litellm.apiKey, "${LITELLM_MASTER_KEY}");
  assert.equal(config.models.providers.openai.apiKey, "${OPENAI_API_KEY}");
  assert.equal(JSON.stringify(config).includes("_end"), false);
});

test("litellm is enabled by its base URL alone and then carries no key", () => {
  // OpenClaw sends no provider request without an apiKey, so a fixed, public
  // placeholder stands there; the proxy in front replaces the header
  const config = renderDefault({ LITELLM_BASE_URL: "http://litellm-proxy:4000" });
  assert.deepEqual(Object.keys(config.models.providers), ["litellm"]);
  assert.equal(config.models.providers.litellm.baseUrl, "http://litellm-proxy:4000");
  assert.equal(config.models.providers.litellm.apiKey, "proxy-supplied");
  assert.equal(config.auth, undefined);
  assert.equal(config.agents.defaults.model.primary, "litellm/openrouter/~moonshotai/kimi-latest");
});

test("the agent has no tool to request a credential and no path out of the sandbox by default", () => {
  const config = renderDefault({});
  assert.deepEqual(config.tools.deny, ["secrets"]);
  assert.equal(config.tools.elevated.enabled, false);
  assert.equal(config.agents.defaults.sandbox.mode, "all");
});

test("a scoped LiteLLM key and the Hindsight key reach the configuration only as placeholders", () => {
  const text = renderDefaultText({
    LITELLM_BASE_URL: "http://litellm:4000",
    LITELLM_API_KEY: "secret-litellm-virtual",
    OPENCLAW_HINDSIGHT_SHARED_URL: "http://hindsight:8888/mcp/shared/",
    OPENCLAW_HINDSIGHT_OWN_URL: "http://hindsight:8888/mcp/openclaw/",
    OPENCLAW_HINDSIGHT_API_KEY: "secret-hindsight",
  });
  assert.equal(text.includes("secret-litellm-virtual") || text.includes("secret-hindsight"), false);
  const config = JSON.parse(text);
  assert.equal(config.models.providers.litellm.apiKey, "${LITELLM_API_KEY}");
  for (const server of Object.values(config.mcp.servers)) {
    assert.deepEqual(server.headers, { Authorization: "Bearer ${OPENCLAW_HINDSIGHT_API_KEY}" });
  }
});

test("the Hindsight banks become MCP servers from the environment", () => {
  const config = renderDefault({
    OPENCLAW_HINDSIGHT_SHARED_URL: "http://hindsight:8888/mcp/shared/",
    OPENCLAW_HINDSIGHT_OWN_URL: "http://hindsight:8888/mcp/openclaw/",
  });
  assert.deepEqual(config.mcp, {
    servers: {
      "hindsight-shared": { url: "http://hindsight:8888/mcp/shared/", transport: "streamable-http" },
      "hindsight-openclaw": { url: "http://hindsight:8888/mcp/openclaw/", transport: "streamable-http" },
    },
  });
  assert.equal(renderDefault({}).mcp, undefined);
  const own = renderDefault({ OPENCLAW_MCP_JSON: '{"servers":{}}', OPENCLAW_HINDSIGHT_SHARED_URL: "http://x/" });
  assert.deepEqual(own.mcp, { servers: {} });
});
