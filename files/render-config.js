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
  let template = fs.readFileSync(templateFile, 'utf8');
  const env = process.env;

  // Replace ${VAR} with env values (not Jinja2 syntax, handle before nunjucks)
  template = template.replace(/\$\{(\w+)\}/g, (_, v) => env[v] || '');

  // Configure nunjucks with custom filters
  const nunjucksEnv = new nunjucks.Environment(null, { autoescape: false });
  nunjucksEnv.addFilter('int', (val) => parseInt(val, 10) || 0);

  // Render Jinja2 template with nunjucks (env vars as context)
  const rendered = nunjucksEnv.renderString(template, env);

  // Remove sentinel entries and fix trailing commas
  let json = rendered;
  json = json.replace(/,\s*"_end"\s*:\s*true\s*/g, '');
  json = json.replace(/"\s*_end"\s*:\s*true\s*,?\s*/g, '');
  json = json.replace(/,\s*([}\]])/g, '$1');

  // Parse and post-process
  let config = JSON.parse(json);

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
