// Smoke test for architecture-spec.html. Run: node docs/design/architecture-spec-smoke.js (needs jsdom; JSDOM_PATH like docs/mockups/smoke-test.js)
// Checks the page loads, every TOC link has a section, and the operation table matches openapi.yaml.
const path = require('path'), fs = require('fs');
const base = process.env.JSDOM_PATH ? path.join(process.env.JSDOM_PATH, 'node_modules', 'jsdom') : 'jsdom';
const { JSDOM } = require(base);
const html = fs.readFileSync(path.join(__dirname, 'architecture-spec.html'), 'utf8');
const yaml = fs.readFileSync(path.join(__dirname, '..', '..', 'contracts', 'openapi.yaml'), 'utf8');
const errors = [];
const dom = new JSDOM(html, { runScripts: 'dangerously', url: 'http://localhost/', beforeParse(w) { w.addEventListener('error', e => errors.push(e.message)); } });
setTimeout(() => {
  const d = dom.window.document, r = [];
  const ids = [...d.querySelectorAll('#toc a')].map(a => a.getAttribute('href').slice(1));
  r.push(['21 sections (overview + 20)', d.querySelectorAll('main section').length === 21]);
  r.push(['every TOC link has a section', ids.every(id => d.getElementById(id))]);
  r.push(['overview is first', d.querySelector('main section').id === 'overview']);
  const paths = (yaml.match(/^  (\/v1\/[^:]+):/gm) || []).map(l => l.trim().slice(0, -1));
  const apiText = d.getElementById('api').textContent;
  const missing = paths.filter(p => !apiText.includes(p.replace(/^\/v1\/ai\/conversations\/\{id\}/, '.../{id}').replace('/v1/ai/conversations/{id}', '...')) && !apiText.includes(p));
  r.push(['every openapi path appears in section 6 (' + paths.length + ')', missing.length === 0]);
  const ver = (yaml.match(/^\s+version:\s*(\S+)/m) || [])[1];
  r.push(['header shows API version ' + ver, d.querySelector('header').textContent.includes('API ' + ver)]);
  r.push(['has diagrams (svg >= 5)', d.querySelectorAll('svg').length >= 5]);
  r.push(['no runtime errors', errors.length === 0]);
  console.log(r.map(([n, ok]) => (ok ? 'PASS ' : 'FAIL ') + n).join('\n') + (missing.length ? '\nmissing: ' + missing.join(', ') : '') + (errors.length ? '\n' + errors.join('\n') : ''));
  console.log(r.filter(x => x[1]).length + '/' + r.length + ' passed');
  process.exit(r.every(x => x[1]) ? 0 : 1);
}, 50);
