#!/usr/bin/env node
const fs = require('fs');
const nunjucks = require('nunjucks');

const templateFile = process.argv[2];
const outputFile = process.argv[3];

if (!templateFile || !outputFile) {
  console.error('Usage: render-config.js <template-file> <output-file>');
  process.exit(1);
}

try {
  const template = fs.readFileSync(templateFile, 'utf8');
  const env = process.env;

  // Configure nunjucks with custom filters
  const nunjucksEnv = new nunjucks.Environment(null, { autoescape: false });
  nunjucksEnv.addFilter('int', (val) => parseInt(val, 10) || 0);

  // Render Jinja2 template with nunjucks (env vars as context). Secrets stay
  // ${VAR} placeholders inside JSON strings: OpenClaw resolves them from its
  // environment when it loads the configuration, so no token is ever written
  // in clear text into openclaw.json on the persistent volume, and a secret
  // never passes through the template engine or the JSON text
  const rendered = nunjucksEnv.renderString(template, env);

  // Parse and post-process
  let config = JSON.parse(rendered);

  // Remove "_end" sentinel keys structurally (they keep the rendered template
  // valid JSON without trailing commas); no regex on the JSON text, which would
  // corrupt string values containing ",}" or ",]"
  const stripEnd = (node) => {
    if (Array.isArray(node)) node.forEach(stripEnd);
    else if (node && typeof node === 'object') {
      delete node._end;
      Object.values(node).forEach(stripEnd);
    }
  };
  stripEnd(config);

  // Merge channels_* into single channels object
  const channels = {};
  for (const key of Object.keys(config)) {
    if (key.startsWith('channels_')) {
      Object.assign(channels, config[key]);
      delete config[key];
    }
  }
  if (Object.keys(channels).length > 0) {
    config.channels = channels;
  }

  // Merge plugins_* helper sections into plugins.entries (if present)
  const pluginEntryMaps = [];
  for (const key of Object.keys(config)) {
    if (key.startsWith('plugins_')) {
      const section = config[key];
      if (section && typeof section === 'object' && section.entries && typeof section.entries === 'object') {
        pluginEntryMaps.push(section.entries);
      }
      delete config[key];
    }
  }
  if (pluginEntryMaps.length > 0) {
    if (!config.plugins || typeof config.plugins !== 'object') {
      config.plugins = {};
    }
    if (!config.plugins.entries || typeof config.plugins.entries !== 'object') {
      config.plugins.entries = {};
    }
    for (const entries of pluginEntryMaps) {
      Object.assign(config.plugins.entries, entries);
    }
  }

  fs.writeFileSync(outputFile, JSON.stringify(config, null, 2));
  console.log(`Configuration rendered to ${outputFile}`);
} catch (error) {
  console.error('Failed to render template:', error.message);
  console.error(error.stack);
  process.exit(1);
}
