// Contract test: calls every operation in openapi.yaml against the mock server and checks
// status codes, response bodies against the OpenAPI schemas, and the server-side trust rules.
// Run: node test-contract.js   (inside contracts/, after npm install)
const path = require('path');
const SwaggerParser = require('@apidevtools/swagger-parser');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const { createServer } = require('./mock-server');

(async () => {
  const api = await SwaggerParser.dereference(path.join(__dirname, 'openapi.yaml'));
  const ajv = new Ajv({ allErrors: true, strict: false }); addFormats(ajv);
  const ops = {};
  for (const [p, item] of Object.entries(api.paths)) for (const [m, op] of Object.entries(item)) if (op.operationId) ops[op.operationId] = { method: m.toUpperCase(), path: p, op };
  const called = new Set(), results = [];
  const check = (name, ok, extra) => results.push((ok ? 'PASS ' : 'FAIL ') + name + (ok || !extra ? '' : ' -> ' + extra));

  const server = createServer(); await new Promise(r => server.listen(0, r));
  const base = 'http://127.0.0.1:' + server.address().port;

  async function call(opId, { params = {}, query = {}, body, headers = {}, expect } = {}) {
    const o = ops[opId]; called.add(opId);
    const url = new URL(base + o.path.replace(/\{(\w+)\}/g, (_, k) => encodeURIComponent(params[k])));
    for (const [k, v] of Object.entries(query)) url.searchParams.set(k, Array.isArray(v) ? v.join(',') : String(v));
    const res = await fetch(url, { method: o.method, headers: { 'Content-Type': 'application/json', ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text(); const data = text ? JSON.parse(text) : undefined;
    const spec = o.op.responses[String(res.status)];
    const label = opId + ' ' + o.method + ' ' + o.path + ' -> ' + res.status;
    if (!spec) { check(label + ' (status declared in OpenAPI)', false, 'undeclared status'); return { status: res.status, data, headers: res.headers }; }
    const schema = spec.content && spec.content['application/json'] && spec.content['application/json'].schema;
    if (schema) { const ok = ajv.validate(schema, data); check(label + ' matches schema', ok, ajv.errorsText()); }
    else check(label + ' has no body', data === undefined, 'unexpected body');
    if (expect !== undefined) check(label + ' expected ' + expect, res.status === expect, 'got ' + res.status);
    return { status: res.status, data, headers: res.headers };
  }

  // Config
  const cfg = await call('getAppConfig', { query: { appVersion: '0.1.0' }, expect: 200 });
  await call('getAppConfig', { query: { appVersion: '0.1.0' }, headers: { 'If-None-Match': cfg.headers.get('etag') }, expect: 304 });
  const tax = await call('getTaxonomies', { expect: 200 });
  check('taxonomies has 10 categories and 4 map groups', tax.data.categories.length === 10 && tax.data.mapGroups.length === 4);

  // Profile
  await call('getProfile', { expect: 404 });
  await call('acceptConsent', { body: { version: '1', accepted: true }, expect: 204 });
  await call('putProfile', { body: { displayName: 'สุดา (สมมติ)', district: 'ปทุมวัน', skills: ['ขับรถยนต์', 'พิมพ์เอกสาร'], hoursPerWeek: '20-40', incomeGoalPerMonth: 5000, goals: ['หางาน'] }, expect: 200 });
  await call('getProfile', { expect: 200 });
  await call('getSettings', { expect: 200 });
  const st = await call('patchSettings', { body: { largeText: true }, expect: 200 });
  check('settings patch keeps other fields', st.data.largeText === true && st.data.reminders === true);

  // Intake
  let turn, n = 0;
  do { turn = await call('chatTurn', { body: { sessionId: 's1', message: n ? 'ทดสอบ' + n : undefined }, expect: 200 }); n++; } while (!turn.data.done && n < 10);
  check('intake finishes within 6 turns', turn.data.done && n <= 6, 'turns ' + n);

  // Opportunities
  const all = await call('searchOpportunities', { query: { radiusKm: 10 }, expect: 200 });
  check('suspicious hidden by default and counted', all.data.items.every(o => !o.suspicious) && all.data.hiddenSuspicious === 1);
  check('every item has a source URL', all.data.items.every(o => /^https?:\/\//.test(o.provenance.sourceUrl)));
  check('pins only for exact precision with coordinates', all.data.items.every(o => o.location.precision !== 'exact' || (typeof o.location.lat === 'number' && typeof o.location.distanceKm === 'number')));
  check('mock data is labelled', all.data.items.filter(o => o.provenance.provider === 'mock').every(o => o.provenance.dataStatus === 'mock'));
  const near = await call('searchOpportunities', { query: { radiusKm: 1 } });
  check('radius filter narrows located items', near.data.items.filter(o => o.location.precision === 'exact').every(o => o.location.distanceKm <= 1) && near.data.items.length < all.data.items.length);
  const money = await call('searchOpportunities', { query: { group: 'money', onlyMoney: true } });
  check('group + onlyMoney filter', money.data.items.length > 0 && money.data.items.every(o => o.mapGroup === 'money' && o.money.basis !== 'none'));
  const sus = await call('searchOpportunities', { query: { showSuspicious: true } });
  check('showSuspicious reveals flagged items with reasons', sus.data.items.some(o => o.suspicious && o.suspiciousReasons.length));
  const qtax = await call('searchOpportunities', { query: { q: 'ภาษี' } });
  check('text search', qtax.data.items.length === 1);
  const byMoney = await call('searchOpportunities', { query: { sort: 'money', radiusKm: 10 } });
  check('sort by money puts highest first', byMoney.data.items[0].money.max === Math.max(...byMoney.data.items.map(o => o.money.max || -1)));
  const page = await call('searchOpportunities', { query: { limit: 3, radiusKm: 10 } });
  check('pagination cursor', page.data.items.length === 3 && page.data.nextCursor === '3');
  await call('getOpportunity', { params: { id: 'mock_j1' }, expect: 200 });
  await call('getOpportunity', { params: { id: 'nope' }, expect: 404 });
  await call('reportOpportunity', { params: { id: 'mock_x1' }, body: { reason: 'suspicious' }, expect: 204 });

  // Matching
  const ids = all.data.items.map(o => o.id);
  const m = await call('rankMatches', { body: { opportunityIds: [...ids, 'invented_id', 'mock_x1'] }, expect: 200 });
  check('AI ranking only returns requested, non-suspicious ids', m.data.ranked.every(r => ids.includes(r.opportunityId)) && !m.data.ranked.some(r => r.opportunityId === 'invented_id' || r.opportunityId === 'mock_x1'));
  check('AI ranking reasons contain no money figures', m.data.ranked.every(r => !/\d{2,}\s*บาท|฿/.test(r.reason)));
  check('AI invocation is recorded', !!m.data.aiInvocationId);

  // Planner
  const pl = await call('getPlanOptions', { expect: 200 });
  check('net = gross - cost for every plan with numbers', pl.data.filter(p => p.grossPerMonth).every(p => p.netPerMonth[0] === p.grossPerMonth[0] - p.costPerMonth[1] && p.netPerMonth[1] === p.grossPerMonth[1] - p.costPerMonth[0]));
  check('plans without numbers say why', pl.data.filter(p => !p.grossPerMonth).every(p => p.unknownReason));

  // Tasks
  const t = await call('createTask', { body: { opportunityId: 'mock_j1' }, expect: 201 });
  const id = t.data.id;
  await call('listTasks', { expect: 200 });
  await call('getTask', { params: { id }, expect: 200 });
  const c1 = await call('completeStep', { params: { id }, expect: 200 });
  check('complete step increments', c1.data.doneCount === 1 && c1.data.reportedBy === 'user');
  const u1 = await call('undoTaskEvent', { params: { id }, expect: 200 });
  check('undo reverts last step', u1.data.doneCount === 0);
  const b1 = await call('blockTask', { params: { id }, body: { reason: 'not_understood' }, expect: 200 });
  check('block sets status', b1.data.status === 'blocked');
  await call('snoozeTask', { params: { id }, body: { until: 'tomorrow' }, expect: 204 });
  await call('taskHelp', { params: { id }, expect: 200 });

  // Sources
  await call('listSources', { expect: 200 });
  await call('refreshSource', { params: { provider: 'unknown' }, expect: 404 });

  // My data and delete
  await call('getMyData', { expect: 200 });
  await call('deleteMyData', { expect: 204 });
  await call('getProfile', { expect: 404 });
  const after = await call('listTasks');
  check('delete clears tasks', after.data.length === 0);
  // refreshSource 202 is exercised last because it starts network calls
  await call('refreshSource', { params: { provider: 'mock' }, expect: 202 });

  const missing = Object.keys(ops).filter(k => !called.has(k));
  check('every OpenAPI operation exercised (' + called.size + '/' + Object.keys(ops).length + ')', !missing.length, missing.join(','));
  server.close();
  const fails = results.filter(r => r.startsWith('FAIL'));
  console.log(results.join('\n'));
  console.log((results.length - fails.length) + '/' + results.length + ' checks passed');
  console.log(fails.length ? 'RESULT: FAIL' : 'RESULT: PASS');
  process.exit(fails.length ? 1 : 0);
})().catch(e => { console.log('RESULT: FAIL ' + e.stack); process.exit(1); });
