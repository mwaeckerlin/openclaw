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

const renderDefault = (env) => {
  const dir = mkdtempSync(join(tmpdir(), "openclaw-render-"));
  const outputFile = join(dir, "openclaw.json");
  execFileSync("node", [renderScript, defaultTemplate, outputFile], {
    env: { PATH: process.env.PATH, OPENCLAW_GATEWAY_TOKEN: "test-token", ...env },
    cwd: projectRoot,
  });
  return JSON.parse(readFileSync(outputFile, "utf8"));
};

test("secret values with JSON special characters survive substitution", () => {
  const secret = 'pa"ss\\word';
  const config = render('{ "token": "${MY_SECRET}" }', { MY_SECRET: secret });
  assert.equal(config.token, secret);
});

test("secret values containing template syntax are not evaluated", () => {
  const secret = "{{ 7 * 7 }}{% if true %}x{% endif %}";
  const config = render('{ "token": "${MY_SECRET}" }', { MY_SECRET: secret });
  assert.equal(config.token, secret);
});

test("secret values containing comma-brace sequences are preserved", () => {
  const secret = "ab,}cd,]ef";
  const config = render('{ "token": "${MY_SECRET}", "_end": true }', {
    MY_SECRET: secret,
  });
  assert.equal(config.token, secret);
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
  assert.equal(config.gateway.auth.token, "test-token");
  assert.equal(config.models.providers.litellm.apiKey, "llm-key");
  assert.equal(config.models.providers.openai.apiKey, "sk-test");
  assert.equal(JSON.stringify(config).includes("_end"), false);
});
