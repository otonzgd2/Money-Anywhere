// Copies the parts of contracts/fixtures/assistant-policy.json the mock needs into index.html.
// Run after editing the policy: node docs/mockups/sync-policy.js   (the smoke test fails if they differ)
const fs = require('fs'), path = require('path');
const policy = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'contracts', 'fixtures', 'assistant-policy.json'), 'utf8'));
const subset = { version: policy.version, rules: policy.rules, inScope: policy.inScope, redirect: policy.redirect };
const file = path.join(__dirname, 'index.html');
const html = fs.readFileSync(file, 'utf8');
const re = /\/\*POLICY:BEGIN\*\/[\s\S]*?\/\*POLICY:END\*\//;
if (!re.test(html)) throw new Error('POLICY markers not found in index.html');
fs.writeFileSync(file, html.replace(re, () => '/*POLICY:BEGIN*/const POLICY = ' + JSON.stringify(subset) + ';/*POLICY:END*/'));
console.log('synced policy ' + policy.version);
