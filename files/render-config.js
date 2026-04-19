#!/usr/bin/env node
const fs = require('fs');

const templateFile = process.argv[2];
const outputFile = process.argv[3];

if (!templateFile || !outputFile) {
  console.error('Usage: render-config.js <template-file> <output-file>');
  process.exit(1);
}

try {
  let template = fs.readFileSync(templateFile, 'utf8');
  const env = process.env;

  function getEnvValue(varName, defaultValue) {
    if (defaultValue === undefined) defaultValue = '';
    return env[varName] !== undefined ? env[varName] : defaultValue;
  }

  function evalCondition(condStr) {
    // VAR | default('...') | length > 0
    let m = condStr.match(/^(\w+)\s*\|\s*default\(['"]([^'"]*?)['"]\)\s*\|\s*length\s*>\s*0$/);
    if (m) return getEnvValue(m[1], m[2]).length > 0;

    // VAR != 'false'
    m = condStr.match(/^(\w+)\s*!=\s*['"]false['"]$/);
    if (m) return getEnvValue(m[1], 'true') !== 'false';

    // VAR (truthy check)
    m = condStr.match(/^(\w+)$/);
    if (m) {
      const v = getEnvValue(m[1]);
      return v.length > 0 && v !== '0' && v !== 'false';
    }

    return false;
  }

  // Process {% if %} blocks innermost-first (no nesting in our templates, but handle ordering)
  function processConditionals(text) {
    let changed = true;
    while (changed) {
      changed = false;

      // Find the first {% if ... %} and its matching {% endif %}
      const ifMatch = text.match(/\{%\s*if\s+([\s\S]*?)\s*%\}/);
      if (!ifMatch) break;

      const ifStart = ifMatch.index;
      const afterIf = ifStart + ifMatch[0].length;
      const condition = ifMatch[1];

      // Find matching endif - scan for nested ifs
      let depth = 1;
      let pos = afterIf;
      let elsePos = -1;
      while (depth > 0 && pos < text.length) {
        const nextIf = text.indexOf('{%', pos);
        if (nextIf === -1) break;

        const tagEnd = text.indexOf('%}', nextIf);
        if (tagEnd === -1) break;

        const tag = text.substring(nextIf, tagEnd + 2);
        if (/\{%\s*if\s/.test(tag)) {
          depth++;
        } else if (/\{%\s*endif\s*%\}/.test(tag)) {
          depth--;
          if (depth === 0) {
            // Found matching endif
            const endifEnd = tagEnd + 2;
            const body = text.substring(afterIf, nextIf);

            // Check for else at this level
            const elseRegex = /\{%\s*else\s*%\}/g;
            let elseMatch;
            let searchDepth = 0;
            let searchPos = afterIf;
            let foundElsePos = -1;
            let foundElseEnd = -1;

            // Re-scan for else at depth 0
            let scanPos = afterIf;
            let scanDepth = 0;
            while (scanPos < nextIf) {
              const nextTag = text.indexOf('{%', scanPos);
              if (nextTag === -1 || nextTag >= nextIf) break;
              const nextTagEnd = text.indexOf('%}', nextTag);
              if (nextTagEnd === -1) break;
              const scanTag = text.substring(nextTag, nextTagEnd + 2);
              if (/\{%\s*if\s/.test(scanTag)) {
                scanDepth++;
              } else if (/\{%\s*endif\s*%\}/.test(scanTag)) {
                scanDepth--;
              } else if (/\{%\s*else\s*%\}/.test(scanTag) && scanDepth === 0) {
                foundElsePos = nextTag;
                foundElseEnd = nextTagEnd + 2;
              }
              scanPos = nextTagEnd + 2;
            }

            const result = evalCondition(condition);
            let replacement;
            if (foundElsePos !== -1) {
              const ifContent = text.substring(afterIf, foundElsePos);
              const elseContent = text.substring(foundElseEnd, nextIf);
              replacement = result ? ifContent : elseContent;
            } else {
              const ifContent = text.substring(afterIf, nextIf);
              replacement = result ? ifContent : '';
            }

            text = text.substring(0, ifStart) + replacement + text.substring(endifEnd);
            changed = true;
            break;
          }
        }
        pos = tagEnd + 2;
      }
    }
    return text;
  }

  template = processConditionals(template);

  // Replace {{ VAR | default('...') }}
  template = template.replace(
    /\{\{\s*(\w+)\s*\|\s*default\(['"]([^'"]*?)['"]\)\s*\}\}/g,
    (_, v, d) => getEnvValue(v, d)
  );

  // Replace {{ VAR }}
  template = template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, v) => getEnvValue(v));

  // Replace ${VAR}
  template = template.replace(/\$\{(\w+)\}/g, (_, v) => getEnvValue(v));

  // Remove any remaining {% ... %} tags
  template = template.replace(/\{%[^%]*%\}/g, '');

  // Remove sentinel entries and fix trailing commas
  template = template.replace(/,\s*"_end"\s*:\s*true\s*/g, '');
  template = template.replace(/"\s*_end"\s*:\s*true\s*,?\s*/g, '');
  template = template.replace(/,\s*([}\]])/g, '$1');

  // Parse and merge channels_* into channels
  let config = JSON.parse(template);

  // Resolve __AUTO_MODEL__: LiteLLM model if LITELLM_MASTER_KEY set, else OpenAI model
  if (config.agents?.defaults?.model?.primary === '__AUTO_MODEL__') {
    if (env.LITELLM_MASTER_KEY) {
      config.agents.defaults.model.primary = 'litellm/openrouter/anthropic/claude-sonnet-4';
    } else {
      config.agents.defaults.model.primary = 'openai/gpt-4o';
    }
  }

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

  fs.writeFileSync(outputFile, JSON.stringify(config, null, 2));
  console.log(`Configuration rendered to ${outputFile}`);
} catch (error) {
  console.error('Failed to render template:', error.message);
  console.error(error.stack);
  process.exit(1);
}
