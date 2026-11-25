// Checks that an app config only references things that exist, so menus and buttons can move safely.
// Run: node contracts/validate-config.js [path-to-config.json]
// Checks: tab routes exist; every onTap/actions route and action exists; every action path exists in
// openapi.yaml with the same method; widget types are in the catalog; "data" refers to a known action;
// filter params are query parameters of GET /v1/opportunities; flags used are declared.
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const cfgPath = process.argv[2] || path.join(dir, 'app-config.sample.json');
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const schema = JSON.parse(fs.readFileSync(path.join(dir, 'app-config.schema.json'), 'utf8'));
const api = fs.readFileSync(path.join(dir, 'openapi.yaml'), 'utf8');

const errors = [];
const err = (where, msg) => errors.push(where + ': ' + msg);

// Parse "paths:" block of openapi.yaml: two-space path keys, four-space method keys.
const apiOps = new Set();
let inPaths = false, cur = null;
for (const line of api.split(/\r?\n/)) {
  if (/^paths:\s*$/.test(line)) { inPaths = true; continue; }
  if (inPaths && /^\S/.test(line)) inPaths = false;
  if (!inPaths) continue;
  const p = line.match(/^  (\/\S+):\s*$/); if (p) { cur = p[1]; continue; }
  const m = line.match(/^    (get|post|put|patch|delete):/); if (m && cur) apiOps.add(m[1].toUpperCase() + ' ' + cur);
}
const searchParams = new Set();
{ const block = api.split('/v1/opportunities:')[1].split(/\n  \/v1\//)[0];
  for (const m of block.matchAll(/name: (\w+), in: query/g)) searchParams.add(m[1]); }

const widgetTypes = new Set(schema.$defs.widget.properties.type.enum);
const routes = new Set(Object.keys(cfg.routes));
const actions = new Set(Object.keys(cfg.actions));
const flags = new Set(Object.keys(cfg.featureFlags || {}));

for (const t of cfg.tabs) {
  if (!routes.has(t.route)) err('tab ' + t.id, 'unknown route ' + t.route);
  for (const r of t.activeFor || []) if (!routes.has(r)) err('tab ' + t.id, 'activeFor unknown route ' + r);
  if (t.flag && !flags.has(t.flag)) err('tab ' + t.id, 'unknown flag ' + t.flag);
}
if (cfg.tabs.length > 5) err('tabs', 'more than 5 tabs');

const checkBinding = (where, b) => {
  if (!b) return;
  if (b.action && b.route) err(where, 'binding has both action and route');
  if (b.action && !actions.has(b.action)) err(where, 'unknown action ' + b.action);
  if (b.route && !routes.has(b.route)) err(where, 'unknown route ' + b.route);
  if (b.then && b.then.route && !routes.has(b.then.route)) err(where, 'then.route unknown ' + b.then.route);
  if (b.route && cfg.routes[b.route] && cfg.routes[b.route].params) {
    for (const p of cfg.routes[b.route].params) if (!b.params || !(p in b.params)) err(where, 'route ' + b.route + ' needs param ' + p);
  }
};
const walk = (where, w) => {
  if (!widgetTypes.has(w.type)) err(where, 'widget type not in catalog: ' + w.type);
  if (w.data && !actions.has(w.data)) err(where, 'data refers to unknown action ' + w.data);
  if (w.flag && !flags.has(w.flag)) err(where, 'unknown flag ' + w.flag);
  checkBinding(where + ' onTap', w.onTap);
  (w.actions || []).forEach((a, i) => checkBinding(where + ' actions[' + i + ']', a));
  (w.items || []).forEach((c, i) => walk(where + ' > ' + c.type + '[' + i + ']', c));
};
for (const [rid, r] of Object.entries(cfg.routes)) r.sections.forEach((w, i) => walk('route ' + rid + ' > ' + w.type + '[' + i + ']', w));

for (const [aid, a] of Object.entries(cfg.actions)) {
  if (!apiOps.has(a.method + ' ' + a.path)) err('action ' + aid, 'not in openapi.yaml: ' + a.method + ' ' + a.path);
  if (a.undoAction && !actions.has(a.undoAction)) err('action ' + aid, 'unknown undoAction ' + a.undoAction);
}
for (const f of cfg.filters) if (!searchParams.has(f.param)) err('filter ' + f.id, 'param not accepted by GET /v1/opportunities: ' + f.param);

// Every action should be reachable from somewhere, otherwise it is dead config (warning only).
const used = new Set();
JSON.stringify(cfg.routes, (k, v) => { if ((k === 'action' || k === 'data') && typeof v === 'string') used.add(v); if (k === 'undoAction') used.add(v); return v; });
Object.values(cfg.actions).forEach(a => a.undoAction && used.add(a.undoAction));
const unused = [...actions].filter(a => !used.has(a) && !['config.get', 'consent.accept', 'match.rank', 'settings.get', 'task.block'].includes(a));

console.log('config: ' + path.basename(cfgPath) + ' v' + cfg.configVersion);
console.log('tabs ' + cfg.tabs.length + ', routes ' + routes.size + ', actions ' + actions.size + ', api operations ' + apiOps.size + ', filters ' + cfg.filters.length);
if (unused.length) console.log('warning: actions not placed on any screen: ' + unused.join(', '));
if (errors.length) { console.log(errors.map(e => 'ERROR ' + e).join('\n')); console.log('RESULT: FAIL'); process.exit(1); }
console.log('RESULT: PASS');
