// Contract test: calls every operation in openapi.yaml against the mock server and checks status codes,
// response bodies against the OpenAPI schemas, conventions, consent (PDPA) enforcement, the money engine,
// the AI agent guardrails, and the hidden government mode. Run: node test-contract.js
const http = require('http');
const path = require('path');
const SwaggerParser = require('@apidevtools/swagger-parser');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');
const { createServer } = require('./mock-server');
const { createAi } = require('./adapters/ai');
const { createAgent } = require('./adapters/agent');

const listen = s => new Promise(r => s.listen(0, '127.0.0.1', () => r('http://127.0.0.1:' + s.address().port)));
const NOTICE = require('./fixtures/reference.json').privacyNotice.version;

(async () => {
  const api = await SwaggerParser.dereference(path.join(__dirname, 'openapi.yaml'));
  const ajv = new Ajv({ allErrors: true, strict: false }); addFormats(ajv);
  const ops = {};
  for (const [p, item] of Object.entries(api.paths)) for (const [m, op] of Object.entries(item)) if (op.operationId) ops[op.operationId] = { method: m.toUpperCase(), path: p, op };
  const called = new Set(), results = [];
  const check = (name, ok, extra) => results.push((ok ? 'PASS ' : 'FAIL ') + name + (ok || !extra ? '' : ' -> ' + extra));

  function client(base, defaults = {}) {
    return async function call(opId, { params = {}, query = {}, body, headers = {}, expect } = {}) {
      const o = ops[opId]; if (!o) throw new Error('unknown op ' + opId); called.add(opId);
      const url = new URL(base + o.path.replace(/\{(\w+)\}/g, (_, k) => encodeURIComponent(params[k])));
      for (const [k, v] of Object.entries(query)) url.searchParams.set(k, Array.isArray(v) ? v.join(',') : String(v));
      const res = await fetch(url, { method: o.method, headers: { 'Content-Type': 'application/json', ...defaults, ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
      const text = await res.text(); const data = text ? JSON.parse(text) : undefined;
      const label = opId + ' ' + res.status, spec = o.op.responses[String(res.status)];
      if (!spec) check(label + ' status declared', false, 'undeclared ' + res.status + ' ' + text.slice(0, 140));
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
  const consentBody = (p = {}) => ({ noticeVersion: NOTICE, ageConfirmed: true, purposes: { core: true, location: false, ai: true, reminders: true, ...p } });

  // ================= Server 1: default (gov mode hidden, rules AI) =================
  const server = createServer({ integrationKey: 'test-key' });
  const base = await listen(server);
  const call = client(base, { 'X-Device-Id': 'device-aaaa-1111' });
  const other = client(base, { 'X-Device-Id': 'device-bbbb-2222' });
  const demo = client(base, { 'X-Device-Id': 'device-dddd-4444' });
  const noDevice = client(base);
  const partner = client(base, { 'X-Api-Key': 'test-key' });

  // System and conventions
  const miss = await noDevice('getProfile', { expect: 400 });
  check('missing X-Device-Id is rejected with MISSING_DEVICE', miss.data && miss.data.code === 'MISSING_DEVICE');
  const health = await call('getHealth', { expect: 200 });
  check('health reports commit and version (AC-05)', health.data.commit && health.data.version === '0.3.0');
  const cfg = await call('getAppConfig', { query: { appVersion: '0.1.0' }, expect: 200 });
  check('config carries noticeVersion and gov flag off', cfg.data.noticeVersion === NOTICE && cfg.data.featureFlags.govConnected === false);
  await call('getAppConfig', { query: { appVersion: '0.1.0' }, headers: { 'If-None-Match': cfg.headers.get('etag') }, expect: 304 });
  const tax = await call('getTaxonomies', { expect: 200 });
  check('taxonomies include fact questions', tax.data.categories.length === 10 && tax.data.facts.ageBand.options.length === 5);

  // Privacy (PDPA)
  const notice = await call('getPrivacyNotice', { expect: 200 });
  check('notice hides the gov purpose when the mode is off', notice.data.purposes.length === 4 && !notice.data.purposes.some(p => p.id === 'gov'));
  const c0 = await call('getConsents', { expect: 200 });
  check('no consent yet means renewal needed', c0.data.needsRenewal === true && c0.data.items.length === 0);
  const blocked = await call('putProfile', { body: { district: 'ปทุมวัน' }, expect: 403 });
  check('saving data without consent is refused', blocked.data.code === 'CONSENT_REQUIRED' && blocked.data.missingFields[0] === 'core');
  await call('createConsent', { body: { purposes: null }, expect: 400 });
  await call('createConsent', { body: { ...consentBody(), noticeVersion: 'old' }, expect: 422 });
  await call('createConsent', { body: { ...consentBody(), ageConfirmed: false }, expect: 422 });
  await call('createConsent', { body: consentBody({ core: false }), expect: 422 });
  const c1 = await call('createConsent', { body: consentBody({ gov: true }), expect: 201 });
  check('gov purpose is ignored while the mode is off', c1.data.purposes.gov === undefined && c1.data.purposes.ai === true);
  const c2 = await call('getConsents', { expect: 200 });
  check('consent recorded and current', c2.data.needsRenewal === false && c2.data.current.id === c1.data.id);

  // Me
  const prof = await call('putProfile', { body: { displayName: 'สุดา (สมมติ)', district: 'ปทุมวัน', skills: ['ขับรถยนต์', 'พิมพ์เอกสาร'], hoursPerWeek: '20-40', incomeGoalPerMonth: 5000, goals: ['หางาน'] }, expect: 200 });
  check('district is geocoded to a search point', typeof prof.data.lat === 'number');
  await call('putProfile', { body: [], expect: 422 });
  await call('getProfile', { expect: 200 });
  await call('getSettings', { expect: 200 });
  const st = await call('patchSettings', { body: { largeText: true, reminders: false }, expect: 200 });
  check('settings only holds display settings (reminders live in consent)', st.data.largeText === true && !('reminders' in st.data));
  await call('getFacts', { expect: 200 });
  const badFacts = await call('patchFacts', { body: { ageBand: '200', unknownThing: 1 }, expect: 422 });
  check('fact validation lists every problem', badFacts.data.missingFields.length === 2);
  await call('patchFacts', { body: { ageBand: 'ต่ำกว่า 60', govPension: false, work: 'เพิ่งตกงาน', ss33: true, wage: 12000, unpaidDays: 5, dailyWage: 400 }, expect: 200 });

  // Money: where is my money
  const mo = await call('getMoneyOverview', { expect: 200 });
  const byId = Object.fromEntries(mo.data.items.map(i => [i.id, i]));
  check('unemployment likely, computed from wage', byId.unemployment.status === 'likely' && byId.unemployment.amount.value === 6000 && byId.unemployment.amount.basis === 'calc');
  check('unpaid wages computed from days x daily wage', byId.unpaid_wages.amount.value === 2000);
  check('old-age allowance unlikely with a reason', byId.old_age.status === 'unlikely' && byId.old_age.reasons.some(r => r.ok === false));
  check('tax refund asks exactly the missing question', byId.tax_refund.status === 'need' && byId.tax_refund.nextQuestion.fact === 'taxWithheld');
  check('summary sums likely money only', mo.data.summary.monthly === 6000 && mo.data.summary.once === 2000 && mo.data.summary.allVerified === false);
  check('gov link reported as disabled', mo.data.govLink === 'disabled');
  await call('patchFacts', { body: { taxWithheld: true } });
  const tr = await call('getMoneyRoute', { params: { id: 'tax_refund' }, expect: 200 });
  check('answer re-evaluates: tax refund needs a real-amount check, no invented number', tr.data.status === 'check' && tr.data.amount.basis === 'none' && tr.data.amount.value === undefined);
  await call('patchMoneyRoute', { params: { id: 'unemployment' }, body: { documentsReady: [0, 9] }, expect: 422 });
  await call('patchMoneyRoute', { params: { id: 'nope' }, body: { documentsReady: [0] }, expect: 404 });
  const docs = await call('patchMoneyRoute', { params: { id: 'unemployment' }, body: { documentsReady: [0, 1, 2] }, expect: 200 });
  check('documents ticked', docs.data.documents.every(d => d.ready));
  const claim = await call('createTask', { body: { moneyId: 'unemployment' }, expect: 201 });
  check('starting a claim creates steps and skips the ready documents step', claim.data.moneyId === 'unemployment' && claim.data.doneCount === 1 && claim.data.steps.length === 4);
  const owed = await call('getMoneyRoute', { params: { id: 'unpaid_wages' } });
  check('letter to employer is pre-filled with the amount', owed.data.letterTemplate.includes('2,000'));
  await call('getMoneyRoute', { params: { id: 'nope' }, expect: 404 });

  // Intake
  let t = await call('createIntakeSession', { expect: 201 }); let n = 0;
  while (!t.data.done && n < 10) { t = await call('postIntakeMessage', { params: { id: t.data.sessionId }, body: { text: ['อยากหางานค่ะ', 'บางกะปิ', 'ขับรถยนต์', '10-20', '5,000 บาท'][n] || 'x' }, expect: 200 }); n++; }
  check('intake maps free text to options and geocodes', t.data.done && n === 5 && t.data.profileDraft.goals[0] === 'หางาน' && typeof t.data.profileDraft.lat === 'number' && t.data.profileDraft.incomeGoalPerMonth === 5000);
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
  const sus = await call('searchOpportunities', { query: { showSuspicious: true } });
  check('showSuspicious reveals flagged items with reasons', sus.data.items.some(o => o.suspicious && o.suspiciousReasons.length));
  const none = await call('searchOpportunities', { query: { q: 'ไม่มีแน่นอน', group: 'sell', radiusKm: 1 } });
  check('no results come with suggestions (FR-08)', none.data.items.length === 0 && ['expand_radius', 'clear_query', 'all_groups'].every(k => none.data.suggestions.some(s => s.type === k)));
  await call('searchOpportunities', { query: { sort: 'bogus' }, expect: 400 });
  const p1 = await call('searchOpportunities', { query: { limit: 3, radiusKm: 10 } });
  const p2 = await call('searchOpportunities', { query: { limit: 3, radiusKm: 10, cursor: p1.data.nextCursor } });
  check('cursor pagination returns the next page', p1.data.items.length === 3 && p2.data.items.length === 3 && p1.data.items[0].id !== p2.data.items[0].id);
  await call('getOpportunity', { params: { id: 'mock_j1' }, expect: 200 });
  await call('getOpportunity', { params: { id: 'nope' }, expect: 404 });
  await call('reportOpportunity', { params: { id: 'mock_x1' }, body: { reason: 'suspicious' }, expect: 202 });
  await call('reportOpportunity', { params: { id: 'mock_x1' }, body: { reason: 'spam?' }, expect: 400 });

  // AI one-shot (rules adapter)
  const ids = all.data.items.map(o => o.id);
  const rk = await call('createRanking', { body: { opportunityIds: [...ids, 'invented_id', 'mock_x1'] }, expect: 200 });
  check('ranking only returns requested, non-suspicious ids', rk.data.ranked.every(r => ids.includes(r.opportunityId)) && rk.data.ranked.length === ids.length);
  check('ranking without a provider says fallback_rules', rk.data.aiStatus === 'fallback_rules');
  await call('createRanking', { body: { opportunityIds: [] }, expect: 400 });
  const exm = await call('createExplanation', { body: { subjectType: 'money', subjectId: 'unemployment' }, expect: 200 });
  check('money explanation returns text', exm.data.text.includes('ประกันสังคม'));
  await call('createExplanation', { body: { subjectType: 'task_step', subjectId: 'nope' }, expect: 404 });

  // AI assistant (rules agent)
  const conv = await call('createConversation', { expect: 201 });
  const cid = conv.data.conversationId;
  const a1 = await call('postConversationMessage', { params: { id: cid }, body: { text: 'เงินฉันอยู่ไหน' }, expect: 200 });
  check('assistant answers from the money tool with real totals', a1.data.toolCalls.some(x => x.tool === 'get_money_overview') && a1.data.reply.includes('6000'));
  const a2 = await call('postConversationMessage', { params: { id: cid }, body: { text: 'หางานใกล้บ้าน' }, expect: 200 });
  check('a write is proposed, not done', a2.data.pendingActions.length === 1 && a2.data.pendingActions[0].tool === 'create_task');
  const before = (await call('listTasks')).data.items.length;
  const d1 = await call('decideConversationAction', { params: { id: cid, actionId: a2.data.pendingActions[0].id }, body: { decision: 'confirm' }, expect: 200 });
  const after1 = (await call('listTasks')).data.items.length;
  check('confirming runs the action through the normal service', d1.data.status === 'done' && after1 === before + 1);
  await call('decideConversationAction', { params: { id: cid, actionId: a2.data.pendingActions[0].id }, body: { decision: 'confirm' }, expect: 404 });
  const a3 = await call('postConversationMessage', { params: { id: cid }, body: { text: 'ฉันไม่สะดวกเดินทางไกล' }, expect: 200 });
  check('assistant remembers a preference visibly', a3.data.memoryAdded.length === 1 && a3.data.memoryAdded[0].source === 'ai');
  const a4 = await call('postConversationMessage', { params: { id: cid }, body: { text: 'เตือนฉันพรุ่งนี้' }, expect: 200 });
  const rej = await call('decideConversationAction', { params: { id: cid, actionId: a4.data.pendingActions[0].id }, body: { decision: 'reject' }, expect: 200 });
  check('rejecting leaves data unchanged', rej.data.status === 'rejected');
  await call('decideConversationAction', { params: { id: cid, actionId: 'x' }, body: { decision: 'maybe' }, expect: 404 });
  await call('postConversationMessage', { params: { id: cid }, body: { text: '' }, expect: 422 });
  await call('postConversationMessage', { params: { id: 'nope' }, body: { text: 'x' }, expect: 404 });

  // Memory
  const mem = await call('listMemory', { expect: 200 });
  check('memory lists what the assistant saved', mem.data.items.some(m => m.text.includes('ไม่สะดวก')));
  const added = await call('addMemory', { body: { text: 'ชอบงานช่วงเช้า' }, expect: 201 });
  await call('addMemory', { body: { text: ' ' }, expect: 422 });
  await call('deleteMemory', { params: { id: added.data.id }, expect: 204 });
  await call('deleteMemory', { params: { id: added.data.id }, expect: 404 });

  // Planner
  const pl = await call('getPlanOptions', { expect: 200 });
  const pack = pl.data.items.find(p => p.opportunityId === 'mock_j1');
  check('plan uses the posted daily wage and my free hours', pack.grossPerMonth[0] === Math.round(400 * (30 / 6) * 4.33) && pack.assumptions[0].includes('30'));
  check('net = gross - cost for every plan with numbers', pl.data.items.filter(p => p.grossPerMonth).every(p => p.netPerMonth[0] === p.grossPerMonth[0] - p.costPerMonth[1] && p.netPerMonth[1] === p.grossPerMonth[1] - p.costPerMonth[0]));
  check('plans without numbers say why', pl.data.items.filter(p => !p.grossPerMonth).every(p => p.unknownReason));
  const ideas = await call('getPlanIdeas', { expect: 200 });
  check('ideas match my skills and are labelled estimates', ideas.data.items.length >= 2 && ideas.data.items.every(i => i.numberSource === 'estimate' && i.matchedSkills.length));

  // Tasks
  const task = await call('createTask', { body: { opportunityId: 'mock_j1' }, expect: 201 });
  const again = await call('createTask', { body: { opportunityId: 'mock_j1' }, expect: 201 });
  check('saving the same opportunity twice does not duplicate', again.data.id === task.data.id);
  await call('createTask', { body: { opportunityId: 'nope' }, expect: 404 });
  const id = task.data.id;
  await call('getTask', { params: { id }, expect: 200 });
  await call('createTaskEvent', { params: { id }, body: { type: 'undo' }, expect: 409 });
  const k = { 'Idempotency-Key': 'tap-1' };
  const e1 = await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' }, headers: k, expect: 201 });
  const e2 = await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' }, headers: k, expect: 201 });
  check('double tap with the same Idempotency-Key applies once', e1.data.doneCount === 1 && e2.data.doneCount === 1);
  const u1 = await call('createTaskEvent', { params: { id }, body: { type: 'undo' }, expect: 201 });
  check('undo reverts the last step', u1.data.doneCount === 0);
  const b1 = await call('createTaskEvent', { params: { id }, body: { type: 'block', reason: 'not_understood' }, expect: 201 });
  check('block sets status and reason', b1.data.status === 'blocked' && b1.data.blockReason === 'not_understood');
  const help = await call('createExplanation', { body: { subjectType: 'task_step', subjectId: id }, expect: 200 });
  check('step explanation mentions the current step', help.data.text.includes(task.data.steps[0]));
  const s1 = await call('createTaskEvent', { params: { id }, body: { type: 'snooze', until: 'tomorrow' }, expect: 201 });
  check('snooze schedules a reminder when reminders are consented', s1.data.status === 'snoozed' && server.ports.notifier.list('device-aaaa-1111').length === 1);
  const r1 = await call('createTaskEvent', { params: { id }, body: { type: 'resume' }, expect: 201 });
  check('resume clears the reminder', r1.data.status === 'active' && server.ports.notifier.list('device-aaaa-1111').length === 0);
  await call('createTaskEvent', { params: { id }, body: { type: 'fly' }, expect: 422 });
  await call('createTaskEvent', { params: { id }, body: { type: 'report_outcome', result: 'maybe' }, expect: 422 });
  const out = await call('createTaskEvent', { params: { id }, body: { type: 'report_outcome', result: 'received', amountReported: 3200 }, expect: 201 });
  check('outcome is recorded as user-reported and finishes the task', out.data.status === 'finished' && out.data.outcome.reportedBy === 'user' && out.data.outcome.amountReported === 3200);
  await call('createTaskEvent', { params: { id }, body: { type: 'complete_step' }, expect: 409 });
  const hist = await call('listTaskEvents', { params: { id }, expect: 200 });
  check('history keeps every event and marks undone ones', hist.data.items.length >= 6 && hist.data.items.some(e => e.undone));
  const iso = await other('listTasks', { expect: 200 });
  check('devices are isolated', iso.data.items.length === 0);
  await other('getTask', { params: { id }, expect: 404 });
  await other('createTask', { body: { opportunityId: 'mock_j1' }, expect: 403 });
  const t2 = await call('createTask', { body: { opportunityId: 'mock_w1' } });
  await call('deleteTask', { params: { id: t2.data.id }, expect: 204 });
  await call('deleteTask', { params: { id: t2.data.id }, expect: 404 });

  // Consent withdrawal takes effect immediately
  const sn = (await call('listTasks')).data.items.find(x => x.status === 'active');
  await call('createTaskEvent', { params: { id: sn.id }, body: { type: 'snooze', until: 'next_week' } });
  await call('createConsent', { body: consentBody({ ai: false, reminders: false }), expect: 201 });
  const mem2 = await call('listMemory');
  check('withdrawing AI deletes what the AI remembered', mem2.data.items.every(m => m.source !== 'ai'));
  await call('postConversationMessage', { params: { id: cid }, body: { text: 'เงินฉันอยู่ไหน' }, expect: 403 });
  await call('createConversation', { expect: 403 });
  const rk2 = await call('createRanking', { body: { opportunityIds: ids } });
  check('no AI consent: rules are used and said so', rk2.data.aiStatus === 'skipped_no_consent');
  check('withdrawing reminders cancels scheduled reminders', server.ports.notifier.list('device-aaaa-1111').length === 0);
  const ideas2 = await call('getPlanIdeas');
  check('ideas without AI consent say so', ideas2.data.aiStatus === 'skipped_no_consent');
  const gl = await call('getGovLink', { expect: 404 });
  check('gov endpoints are hidden when the mode is off', gl.data.code === 'FEATURE_DISABLED');
  await call('startGovLink', { expect: 404 });
  await call('finishGovLink', { body: { state: 'x', code: 'y' }, expect: 404 });
  await call('deleteGovLink', { expect: 404 });

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

  // Demo personas (AC-01)
  const dp = await demo('loadDemoPersona', { params: { id: 'p1' }, expect: 200 });
  const dm = await demo('getMoneyOverview');
  check('demo persona loads with consent and shows old-age allowance at the sample rate', dp.data.dataStatus === 'mock' && dm.data.items.find(i => i.id === 'old_age').amount.value === 600 && dp.data.taskCount === 1);
  await demo('loadDemoPersona', { params: { id: 'nobody' }, expect: 404 });

  // Export and delete
  const exp = await call('exportMe', { expect: 200 });
  check('export includes facts, consents history and says what is not stored', exp.data.facts.wage === 12000 && exp.data.consents.length === 2 && exp.data.notStored.length > 0);
  await call('deleteMe', { expect: 204 });
  await call('getProfile', { expect: 404 });
  check('delete clears tasks and consent', (await call('listTasks')).data.items.length === 0 && (await call('getConsents')).data.items.length === 0);
  await call('refreshSource', { params: { provider: 'lever' }, expect: 202 });
  server.close();

  // ================= Server 2: gov mode on + fake LLM for AI and the agent =================
  let mode = 'ok';
  const fake = http.createServer((req, res) => {
    let b = ''; req.on('data', c => b += c); req.on('end', () => {
      if (mode === 'down') { res.writeHead(500); return res.end(); }
      const body = JSON.parse(b), msgs = body.messages, last = msgs[msgs.length - 1];
      let message;
      if (body.tools) {
        const toolsSeen = msgs.filter(m => m.role === 'tool').length;
        if (last.role === 'user') message = { content: '', tool_calls: [{ id: 'c1', type: 'function', function: { name: 'get_money_overview', arguments: '{}' } }] };
        else if (toolsSeen === 1) message = { content: '', tool_calls: [{ id: 'c2', type: 'function', function: { name: 'create_task', arguments: '{"moneyId":"old_age"}' } }, { id: 'c3', type: 'function', function: { name: 'delete_everything', arguments: '{}' } }, { id: 'c4', type: 'function', function: { name: 'remember', arguments: '{"text":"อยากได้เงินเร็ว"}' } }] };
        else message = { content: 'คุณได้ 600 บาท/เดือน และอาจได้อีก 9,999 บาท' };
      } else if (msgs[0].content.includes('แปลงคำตอบ')) message = { content: JSON.stringify({ value: 'หางาน' }) };
      else if (last.content.includes('candidates')) message = { content: JSON.stringify({ ranked: [{ opportunityId: 'invented_by_ai', fit: 'high', reason: 'ได้แน่ 9,999 บาท' }, { opportunityId: 'mock_j1', fit: 'super', reason: 'ได้ ฿500 ต่อวัน ใกล้บ้าน' }] }) };
      else message = { content: JSON.stringify({ text: 'ได้เงินแน่ 3,000 บาท ทำตามขั้นตอน' }) };
      res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ choices: [{ message }] }));
    });
  });
  const fakeBase = await listen(fake);
  const aiOpts = { baseUrl: fakeBase, apiKey: 'fake', timeoutMs: 2000 };
  const s2 = createServer({ govConnected: true, ai: createAi(aiOpts), agent: createAgent(aiOpts) });
  const base2 = await listen(s2);
  const g = client(base2, { 'X-Device-Id': 'device-eeee-5555' });
  const gNo = client(base2, { 'X-Device-Id': 'device-ffff-6666' });
  const n2 = await g('getPrivacyNotice');
  check('notice includes the gov purpose when the mode is on', n2.data.purposes.some(p => p.id === 'gov'));
  await gNo('createConsent', { body: consentBody({ gov: false }) });
  await gNo('startGovLink', { expect: 403 });
  await g('createConsent', { body: consentBody({ gov: true }), expect: 201 });
  const gs = await g('getGovLink', { expect: 200 });
  check('gov link starts not connected and is marked mock', gs.data.status === 'not_connected' && gs.data.mock === true);
  const start = await g('startGovLink', { expect: 201 });
  check('start returns an auth URL', /^https:\/\//.test(start.data.authUrl));
  await g('finishGovLink', { body: { state: 'wrong', code: 'demo' }, expect: 422 });
  const fin = await g('finishGovLink', { body: { state: start.data.state, code: 'demo' }, expect: 200 });
  check('callback connects', fin.data.status === 'connected');
  const gm = await g('getMoneyOverview');
  const gi = Object.fromEntries(gm.data.items.map(i => [i.id, i]));
  check('connected: government data shows as verified and labelled mock', gi.old_age.status === 'verified' && gi.old_age.dataStatus === 'mock' && gi.tax_refund.amount.value === 1850 && gm.data.summary.allVerified === true);
  await g('createConsent', { body: consentBody({ gov: false }) });
  check('withdrawing gov consent disconnects', (await g('getGovLink')).data.status === 'not_connected');
  await g('createConsent', { body: consentBody({ gov: true }) });
  await g('deleteGovLink', { expect: 204 });

  await g('putProfile', { body: { district: 'ปทุมวัน', skills: ['ทำอาหาร'], goals: ['หางาน'] } });
  const it = await g('createIntakeSession', { expect: 201 });
  const it1 = await g('postIntakeMessage', { params: { id: it.data.sessionId }, body: { text: 'อยากได้งานทำค่ะ' }, expect: 200 });
  check('AI normalises a free-text answer to a valid option', it1.data.aiStatus === 'ok' && it1.data.profileDraft.goals[0] === 'หางาน');
  const r2 = await g('createRanking', { body: { opportunityIds: ['mock_j1', 'mock_j2'] }, expect: 200 });
  check('AI provider: ok status when the provider answers', r2.data.aiStatus === 'ok');
  check('AI provider: invented id dropped', !r2.data.ranked.some(r => r.opportunityId === 'invented_by_ai'));
  check('AI provider: money figures stripped from reasons', r2.data.ranked.every(r => !/฿|\d[\d,]*\s?บาท/.test(r.reason)));
  check('AI provider: invalid fit coerced, skipped candidates kept', r2.data.ranked.every(r => ['high', 'good', 'fair'].includes(r.fit)) && r2.data.ranked.length === 2);
  const e3 = await g('createExplanation', { body: { subjectType: 'opportunity', subjectId: 'mock_j1' }, expect: 200 });
  check('AI provider: money stripped from explanation', !/\d[\d,]*\s?บาท/.test(e3.data.text));

  await g('patchFacts', { body: { ageBand: '60-69', govPension: false } });
  const gc = await g('createConversation', { expect: 201 });
  const at = await g('postConversationMessage', { params: { id: gc.data.conversationId }, body: { text: 'ช่วยดูเงินของฉันหน่อย' }, expect: 200 });
  check('agent (LLM): used the read tool', at.data.aiStatus === 'ok' && at.data.toolCalls.some(x => x.tool === 'get_money_overview'));
  check('agent (LLM): write tool became a pending action, forbidden tool ignored', at.data.pendingActions.length === 1 && at.data.pendingActions[0].tool === 'create_task');
  check('agent (LLM): tasks unchanged until confirmed', (await g('listTasks')).data.items.length === 0);
  check('agent (LLM): money from tools kept, invented money removed', at.data.reply.includes('600') && !at.data.reply.includes('9,999'));
  check('agent (LLM): memory note saved visibly', at.data.memoryAdded.length === 1);
  mode = 'down';
  const r3 = await g('createRanking', { body: { opportunityIds: ['mock_j1'] }, expect: 200 });
  check('AI provider down: falls back to rules', r3.data.aiStatus === 'fallback_rules' && r3.data.ranked.length === 1);
  const at2 = await g('postConversationMessage', { params: { id: gc.data.conversationId }, body: { text: 'เงินฉันอยู่ไหน' }, expect: 200 });
  check('agent provider down: falls back to the rules agent', at2.data.aiStatus === 'fallback_rules' && at2.data.reply.length > 0);
  s2.close(); fake.close();

  const missing = Object.keys(ops).filter(x => !called.has(x));
  check('every OpenAPI operation exercised (' + called.size + '/' + Object.keys(ops).length + ')', !missing.length, missing.join(','));
  const fails = results.filter(r => r.startsWith('FAIL'));
  console.log(results.join('\n'));
  console.log((results.length - fails.length) + '/' + results.length + ' checks passed (schema, status and header checks run on every call and only report failures)');
  console.log(fails.length ? 'RESULT: FAIL' : 'RESULT: PASS');
  process.exit(fails.length ? 1 : 0);
})().catch(e => { console.log('RESULT: FAIL ' + e.stack); process.exit(1); });
