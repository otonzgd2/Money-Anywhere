// Contract test: calls every operation in openapi.yaml against the mock server and checks status codes,
// response bodies against the OpenAPI schemas, the cross-cutting conventions, and the server-side trust rules.
// Also runs the AI adapter against a fake LLM to prove the guardrails. Run: node test-contract.js
const http = require('http');
const path = require('path');
const SwaggerParser = require('@apidevtools/swagger-parser');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const { createServer } = require('./mock-server');
const { createAi } = require('./adapters/ai');

const listen = s => new Promise(r => s.listen(0, '127.0.0.1', () => r('http://127.0.0.1:' + s.address().port)));

(async () => {
  const api = await SwaggerParser.dereference(path.join(__dirname, 'openapi.yaml'));
  const ajv = new Ajv({ allErrors: true, strict: false }); addFormats(ajv);
  const ops = {};
  for (const [p, item] of Object.entries(api.paths)) for (const [m, op] of Object.entries(item)) if (op.operationId) ops[op.operationId] = { method: m.toUpperCase(), path: p, op };
  const called = new Set(), results = [];
  const check = (name, ok, extra) => results.push((ok ? 'PASS ' : 'FAIL ') + name + (ok || !extra ? '' : ' -> ' + extra));

  async function client(base, defaults = {}) {
    return async function call(opId, { params = {}, query = {}, body, headers = {}, expect } = {}) {
      const o = ops[opId]; called.add(opId);
      const url = new URL(base + o.path.replace(/\{(\w+)\}/g, (_, k) => encodeURIComponent(params[k])));
      for (const [k, v] of Object.entries(query)) url.searchParams.set(k, Array.isArray(v) ? v.join(',') : String(v));
      const res = await fetch(url, { method: o.method, headers: { 'Content-Type': 'application/json', ...defaults, ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
      const text = await res.text(); const data = text ? JSON.parse(text) : undefined;
      const label = opId + ' ' + res.status;
      const spec = o.op.responses[String(res.status)];
      if (!spec) check(label + ' status declared', false, 'undeclared ' + res.status + ' ' + text.slice(0, 120));
      else {
        const schema = spec.content && spec.content['application/json'] && spec.content['application/json'].schema;
        if (schema) { if (!ajv.validate(schema, data)) check(label + ' matches schema', false, ajv.errorsText()); }
        else if (data !== undefined) check(label + ' has no body', false, 'unexpected body');
      }
      if (!res.headers.get('x-request-id')) check(label + ' has X-Request-Id', false);
      if (data && data.code && data.requestId !== res.headers.get('x-request-id')) check(label + ' error requestId matches header', false);
      if (expect !== undefined && res.status !== expect) check(label + ' expected ' + expect, false, text.slice(0, 160));
      return { status: res.status, data, headers: res.headers };
    };
  }

  const server = createServer({ integrationKey: 'test-key' });
  const base = await listen(server);
  const call = await client(base, { 'X-Device-Id': 'device-aaaa-1111' });
  const other = await client(base, { 'X-Device-Id': 'device-bbbb-2222' });
  const noDevice = await client(base);
  const partner = await client(base, { 'X-Api-Key': 'test-key' });

  // Conventions
  const miss = await noDevice('getProfile', { expect: 400 });
  check('missing X-Device-Id is rejected with MISSING_DEVICE', miss.data && miss.data.code === 'MISSING_DEVICE');

  // Config
  const cfg = await call('getAppConfig', { query: { appVersion: '0.1.0' }, expect: 200 });
  await call('getAppConfig', { query: { appVersion: '0.1.0' }, headers: { 'If-None-Match': cfg.headers.get('etag') }, expect: 304 });
  const tax = await call('getTaxonomies', { expect: 200 });
  check('taxonomies: 10 categories, 4 map groups, districts', tax.data.categories.length === 10 && tax.data.mapGroups.length === 4 && tax.data.districts.length > 0);

  // Me
  await call('getProfile', { expect: 404 });
  await call('createConsent', { body: { version: '1', accepted: true }, expect: 201 });
  await call('createConsent', { body: { version: 1 }, expect: 400 });
  const prof = await call('putProfile', { body: { displayName: 'สุดา (สมมติ)', district: 'ปทุมวัน', skills: ['ขับรถยนต์', 'พิมพ์เอกสาร'], hoursPerWeek: '20-40', incomeGoalPerMonth: 5000, goals: ['หางาน'] }, expect: 200 });
  check('district is geocoded to a search point', typeof prof.data.lat === 'number');
  await call('putProfile', { body: [], expect: 422 });
  await call('getProfile', { expect: 200 });
  await call('getSettings', { expect: 200 });
  const st = await call('patchSettings', { body: { largeText: true }, expect: 200 });
  check('settings patch keeps other fields', st.data.largeText === true && st.data.reminders === true);

  // Intake
  let t = await call('createIntakeSession', { expect: 201 }); let n = 0;
  while (!t.data.done && n < 10) { t = await call('postIntakeMessage', { params: { id: t.data.sessionId }, body: { text: ['หางาน', 'บางกะปิ', 'ขับรถยนต์', '10-20', '5000'][n] || 'x' }, expect: 200 }); n++; }
  check('intake finishes in 5 answers and geocodes the district', t.data.done && n === 5 && typeof t.data.profileDraft.lat === 'number');
  await call('postIntakeMessage', { params: { id: 'nope' }, body: { text: 'x' }, expect: 404 });
  await call('postIntakeMessage', { params: { id: t.data.sessionId }, body: {}, expect: 422 });

  // Opportunities
  const all = await call('searchOpportunities', { query: { radiusKm: 10 }, expect: 200 });
  check('suspicious hidden by default and counted', all.data.items.every(o => !o.suspicious) && all.data.hiddenSuspicious === 1);
  check('every item has a source URL and a data status', all.data.items.every(o => /^https?:\/\//.test(o.provenance.sourceUrl) && o.provenance.dataStatus));
  check('pins only for exact precision with coordinates', all.data.items.every(o => o.location.precision !== 'exact' || (typeof o.location.lat === 'number' && typeof o.location.distanceKm === 'number')));
  check('X-Total-Count header', all.headers.get('x-total-count') === String(all.data.items.length));
  const near = await call('searchOpportunities', { query: { radiusKm: 1 } });
  check('radius filter narrows located items', near.data.items.filter(o => o.location.precision === 'exact').every(o => o.location.distanceKm <= 1) && near.data.items.length < all.data.items.length);
  const money = await call('searchOpportunities', { query: { group: 'money', onlyMoney: true } });
  check('group + onlyMoney', money.data.items.length > 0 && money.data.items.every(o => o.mapGroup === 'money' && o.money.basis !== 'none'));
  const cat = await call('searchOpportunities', { query: { category: 'welfare' } });
  check('category filter', cat.data.items.length > 0 && cat.data.items.every(o => o.category === 'welfare'));
  const sus = await call('searchOpportunities', { query: { showSuspicious: true } });
  check('showSuspicious reveals flagged items with reasons', sus.data.items.some(o => o.suspicious && o.suspiciousReasons.length));
  const byMoney = await call('searchOpportunities', { query: { sort: 'money', radiusKm: 10 } });
  check('sort by money puts highest first', byMoney.data.items[0].money.max === Math.max(...byMoney.data.items.map(o => o.money.max ?? -1)));
  await call('searchOpportunities', { query: { sort: 'bogus' }, expect: 400 });
  const p1 = await call('searchOpportunities', { query: { limit: 3, radiusKm: 10 } });
  const p2 = await call('searchOpportunities', { query: { limit: 3, radiusKm: 10, cursor: p1.data.nextCursor } });
  check('cursor pagination returns the next page', p1.data.items.length === 3 && p2.data.items.length === 3 && p1.data.items[0].id !== p2.data.items[0].id);
  await call('getOpportunity', { params: { id: 'mock_j1' }, expect: 200 });
  await call('getOpportunity', { params: { id: 'nope' }, expect: 404 });
  await call('reportOpportunity', { params: { id: 'mock_x1' }, body: { reason: 'suspicious' }, expect: 202 });
  await call('reportOpportunity', { params: { id: 'mock_x1' }, body: { reason: 'spam?' }, expect: 400 });

  // AI (rules adapter in this server)
  const ids = all.data.items.map(o => o.id);
  const rk = await call('createRanking', { body: { opportunityIds: [...ids, 'invented_id', 'mock_x1'] }, expect: 200 });
  check('ranking only returns requested, non-suspicious ids', rk.data.ranked.every(r => ids.includes(r.opportunityId)) && rk.data.ranked.length === ids.length);
  check('ranking without a provider says fallback_rules', rk.data.aiStatus === 'fallback_rules' && !!rk.data.aiInvocationId);
  await call('createRanking', { body: { opportunityIds: [] }, expect: 400 });
  const ex = await call('createExplanation', { body: { subjectType: 'opportunity', subjectId: 'mock_w1' }, expect: 200 });
  check('explanation returns text', ex.data.text.length > 10);
  await call('createExplanation', { body: { subjectType: 'task_step', subjectId: 'nope' }, expect: 404 });

  // Planner
  const pl = await call('getPlanOptions', { expect: 200 });
  check('net = gross - cost for every plan with numbers', pl.data.items.filter(p => p.grossPerMonth).every(p => p.netPerMonth[0] === p.grossPerMonth[0] - p.costPerMonth[1] && p.netPerMonth[1] === p.grossPerMonth[1] - p.costPerMonth[0]));
  check('plans without numbers say why', pl.data.items.filter(p => !p.grossPerMonth).every(p => p.unknownReason));
  const plf = await call('getPlanOptions', { query: { opportunityIds: ['mock_j1', 'mock_w1'] } });
  check('plan filter by opportunity', plf.data.items.length === 2);

  // Tasks
  const task = await call('createTask', { body: { opportunityId: 'mock_j1' }, expect: 201 });
  const again = await call('createTask', { body: { opportunityId: 'mock_j1' }, expect: 201 });
  check('saving the same opportunity twice does not duplicate', again.data.id === task.data.id);
  await call('createTask', { body: { opportunityId: 'nope' }, expect: 404 });
  const id = task.data.id;
  await call('listTasks', { expect: 200 });
  await call('getTask', { params: { id }, expect: 200 });
  const undoEmpty = await call('createTaskEvent', { params: { id }, body: { type: 'undo' }, expect: 409 });
  check('undo with nothing to undo is a conflict', undoEmpty.data.code === 'CONFLICT');
  const k = { 'Idempotency-Key': 'tap-1' };
  const c1 = await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' }, headers: k, expect: 201 });
  const c2 = await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' }, headers: k, expect: 201 });
  check('double tap with the same Idempotency-Key applies once', c1.data.doneCount === 1 && c2.data.doneCount === 1);
  const u1 = await call('createTaskEvent', { params: { id }, body: { type: 'undo' }, expect: 201 });
  check('undo reverts the last step', u1.data.doneCount === 0);
  const b1 = await call('createTaskEvent', { params: { id }, body: { type: 'block', reason: 'not_understood' }, expect: 201 });
  check('block sets status and reason', b1.data.status === 'blocked' && b1.data.blockReason === 'not_understood');
  const help = await call('createExplanation', { body: { subjectType: 'task_step', subjectId: id }, expect: 200 });
  check('step explanation mentions the current step', help.data.text.includes(task.data.steps[0]));
  const s1 = await call('createTaskEvent', { params: { id }, body: { type: 'snooze', until: 'tomorrow' }, expect: 201 });
  check('snooze schedules a reminder', s1.data.status === 'snoozed' && server.ports.notifier.list('device-aaaa-1111').length === 1);
  const r1 = await call('createTaskEvent', { params: { id }, body: { type: 'resume' }, expect: 201 });
  check('resume clears the reminder', r1.data.status === 'active' && server.ports.notifier.list('device-aaaa-1111').length === 0);
  await call('createTaskEvent', { params: { id }, body: { type: 'fly' }, expect: 422 });
  for (let i = 0; i < task.data.steps.length; i++) await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' } });
  const fin = await call('getTask', { params: { id } });
  check('all steps done = finished, reported by user', fin.data.status === 'finished' && fin.data.reportedBy === 'user');
  await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' }, expect: 409 });
  const hist = await call('listTaskEvents', { params: { id }, expect: 200 });
  check('history keeps every event and marks undone ones', hist.data.items.length >= 6 && hist.data.items.some(e => e.undone));
  const iso = await other('listTasks', { expect: 200 });
  check('devices are isolated', iso.data.items.length === 0);
  await other('getTask', { params: { id }, expect: 404 });
  const t2 = await call('createTask', { body: { opportunityId: 'mock_w1' } });
  await call('deleteTask', { params: { id: t2.data.id }, expect: 204 });
  await call('deleteTask', { params: { id: t2.data.id }, expect: 404 });

  // Sources
  const srcs = await call('listSources', { expect: 200 });
  check('sources say pull, push or static', srcs.data.items.every(s => ['pull', 'push', 'static'].includes(s.direction)));
  await call('refreshSource', { params: { provider: 'mock' }, expect: 404 });

  // Integrations (inbound)
  await call('upsertOpportunitiesBatch', { body: { provider: 'curated', items: [] }, expect: 401 });
  const batch = await partner('upsertOpportunitiesBatch', { body: { provider: 'curated', dataStatus: 'curated', attribution: 'ทีมคัดเอง', items: [
    { externalId: 'c1', title: 'งานช่วยร้านกาแฟ (curated ทดสอบ)', category: 'job_part', mapGroup: 'job', money: { basis: 'listing', min: 350, max: 400, unit: 'บาท/วัน' }, location: { precision: 'exact', text: 'ทดสอบ', lat: 13.7466, lng: 100.5347 }, sourceUrl: 'https://example.org/curated/c1' },
    { externalId: 'c2', title: 'ไม่มีลิงก์', category: 'job_part', mapGroup: 'job', money: { basis: 'none' } },
    { externalId: 'c3', title: 'exact ไม่มีพิกัด', category: 'job_part', mapGroup: 'job', money: { basis: 'none' }, location: { precision: 'exact' }, sourceUrl: 'https://example.org/c3' }
  ] }, expect: 200 });
  check('batch accepts valid rows and rejects rows without link or coordinates', batch.data.accepted === 1 && batch.data.rejected.length === 2);
  const found = await call('searchOpportunities', { query: { q: 'ร้านกาแฟ' } });
  check('ingested item is searchable with curated status', found.data.items.length === 1 && found.data.items[0].provenance.dataStatus === 'curated');
  await partner('receiveWebhook', { params: { provider: 'curated' }, body: { event: 'opportunity.closed', externalId: 'c1' }, expect: 202 });
  const gone = await call('searchOpportunities', { query: { q: 'ร้านกาแฟ' } });
  check('webhook closed removes the item', gone.data.items.length === 0);
  await partner('receiveWebhook', { params: { provider: 'nobody' }, body: { event: 'opportunity.closed', externalId: 'x' }, expect: 404 });
  await partner('receiveWebhook', { params: { provider: 'curated' }, body: { event: 'bad' }, expect: 422 });

  // My data and delete
  const exp = await call('exportMe', { expect: 200 });
  check('export includes profile, tasks and consents', exp.data.tasks.length === 1 && exp.data.consents.length === 1 && exp.data.profile.displayName);
  await call('deleteMe', { expect: 204 });
  await call('getProfile', { expect: 404 });
  const after = await call('listTasks');
  check('delete clears tasks', after.data.items.length === 0);
  await call('refreshSource', { params: { provider: 'lever' }, expect: 202 });
  server.close();

  // AI adapter against a fake LLM: invented ids, money figures, then a provider failure.
  let mode = 'bad-content';
  const fake = http.createServer((req, res) => {
    let b = ''; req.on('data', c => b += c); req.on('end', () => {
      if (mode === 'down') { res.writeHead(500); return res.end(); }
      const msg = JSON.parse(b).messages[1].content;
      const content = msg.includes('candidates')
        ? JSON.stringify({ ranked: [{ opportunityId: 'invented_by_ai', fit: 'high', reason: 'ได้แน่ 9,999 บาท' }, { opportunityId: 'mock_j1', fit: 'super', reason: 'ได้ ฿500 ต่อวัน ใกล้บ้าน' }] })
        : JSON.stringify({ text: 'ได้เงินแน่ 3,000 บาท ทำตามขั้นตอน' });
      res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ choices: [{ message: { content } }] }));
    });
  });
  const fakeBase = await listen(fake);
  const s2 = createServer({ ai: createAi({ baseUrl: fakeBase, apiKey: 'fake', timeoutMs: 2000 }) });
  const call2 = await client(await listen(s2), { 'X-Device-Id': 'device-cccc-3333' });
  const r2 = await call2('createRanking', { body: { opportunityIds: ['mock_j1', 'mock_j2'] }, expect: 200 });
  check('AI provider: ok status when the provider answers', r2.data.aiStatus === 'ok');
  check('AI provider: invented id dropped', !r2.data.ranked.some(r => r.opportunityId === 'invented_by_ai'));
  check('AI provider: money figures stripped from reasons', r2.data.ranked.every(r => !/฿|\d[\d,]*\s?บาท/.test(r.reason)));
  check('AI provider: invalid fit coerced, skipped candidates kept', r2.data.ranked.every(r => ['high', 'good', 'fair'].includes(r.fit)) && r2.data.ranked.length === 2);
  const e2 = await call2('createExplanation', { body: { subjectType: 'opportunity', subjectId: 'mock_j1' }, expect: 200 });
  check('AI provider: money stripped from explanation', !/\d[\d,]*\s?บาท/.test(e2.data.text));
  mode = 'down';
  const r3 = await call2('createRanking', { body: { opportunityIds: ['mock_j1'] }, expect: 200 });
  check('AI provider down: falls back to rules', r3.data.aiStatus === 'fallback_rules' && r3.data.ranked.length === 1);
  s2.close(); fake.close();

  const missing = Object.keys(ops).filter(k => !called.has(k));
  check('every OpenAPI operation exercised (' + called.size + '/' + Object.keys(ops).length + ')', !missing.length, missing.join(','));
  const fails = results.filter(r => r.startsWith('FAIL'));
  console.log(results.join('\n'));
  console.log((results.length - fails.length) + '/' + results.length + ' checks passed (schema, status and header checks run on every call and only report failures)');
  console.log(fails.length ? 'RESULT: FAIL' : 'RESULT: PASS');
  process.exit(fails.length ? 1 : 0);
})().catch(e => { console.log('RESULT: FAIL ' + e.stack); process.exit(1); });
