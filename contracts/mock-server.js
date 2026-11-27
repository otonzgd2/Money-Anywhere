// Demo server that implements every operation in openapi.yaml (ADR-001: this grows into the Demo backend).
// Run: node mock-server.js   PORT=8080 by default. All variables are listed in ../.env.example.
//   LIVE=1            pull Greenhouse/Lever on start and every SOURCE_REFRESH_HOURS
//   AI_BASE_URL, AI_API_KEY, AI_MODEL   OpenAI-compatible provider (otherwise rules)
//   AI_DAILY_LIMIT    AI calls per device per day before falling back to rules (0 = no limit)
//   AI_LOG_FILE       JSON lines log of AI calls (no prompt text)
//   DATA_FILE         JSON file that keeps device data across restarts (contract tests use memory)
//   RETENTION_DAYS    devices not seen for this many days are archived or deleted (0 = off, Owner sets later)
//   RETENTION_MODE    archive (default: move profile + activity to ARCHIVE_FILE) or delete
//   ARCHIVE_FILE      JSON lines archive (default DATA_FILE + .archive.jsonl)
//   GOV_CONNECTED=1   show the hidden government (ThaID) mode, mock adapter only
//   DEMO_MODE=0       disable /v1/demo endpoints
//   INTEGRATION_KEY   key for /v1/integrations (defaults to "dev-only-key" locally)
//   GIT_COMMIT        commit reported by /v1/health (falls back to git rev-parse)
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');
const { URL } = require('url');
const { createAi } = require('./adapters/ai');
const { createAgent } = require('./adapters/agent');
const { taxDemoPersonas } = require('./adapters/demo-tax');
const sources = require('./adapters/sources');
const { createGeocoder } = require('./adapters/geocoder');
const { createNotifier } = require('./adapters/notifier');
const { createMoney } = require('./adapters/money');
const { createGovMock } = require('./adapters/gov');
const { createStore, packDevice, readDevices, archiveRecord, LAYOUT } = require('./adapters/store');
const { createJobs } = require('./adapters/jobs');
const { createGuard, toFact } = require('./adapters/guard');

const DIR = __dirname;
const readJson = f => JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8'));
const nowIso = () => new Date().toISOString();
const daysAgo = d => d ? Math.max(0, Math.round((Date.now() - new Date(d)) / 864e5)) : undefined;
const HOURS = { 'ไม่เกิน 10': 8, '10-20': 15, '20-40': 30, 'เต็มเวลา': 40 };
let COMMIT = process.env.GIT_COMMIT;
if (!COMMIT) { try { COMMIT = execSync('git rev-parse --short HEAD', { cwd: DIR, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { COMMIT = 'unknown'; } }

function km(a, b) {
  const R = 6371, t = x => x * Math.PI / 180, dLat = t(b.lat - a.lat), dLng = t(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(t(a.lat)) * Math.cos(t(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function createServer(opts = {}) {
  const ref = readJson('fixtures/reference.json');
  const fx = readJson('fixtures/opportunities.json');
  const NOTICE = ref.privacyNotice;
  const govOn = opts.govConnected !== undefined ? opts.govConnected : process.env.GOV_CONNECTED === '1';
  const demoOn = opts.demo !== undefined ? opts.demo : process.env.DEMO_MODE !== '0';
  const demoPersonas = { ...ref.demoPersonas, ...taxDemoPersonas };
  const ai = opts.ai || createAi(opts.aiOptions || {});
  const agent = opts.agent || createAgent(opts.aiOptions || {});
  const geo = createGeocoder(ref.taxonomies.districts);
  const notifier = createNotifier({ debug: opts.debug });
  const money = createMoney(ref);
  const govAdapter = createGovMock(ref.govMock, ref.thaid);
  const integrationKey = opts.integrationKey || process.env.INTEGRATION_KEY || 'dev-only-key';
  const store = opts.store || createStore({ file: opts.dataFile });
  const envNum = (v, dflt) => v !== undefined ? +v : dflt;
  const aiDailyLimit = opts.aiDailyLimit !== undefined ? opts.aiDailyLimit : envNum(process.env.AI_DAILY_LIMIT, 50);
  const aiLogFile = opts.aiLogFile !== undefined ? opts.aiLogFile : process.env.AI_LOG_FILE;
  const retentionDays = opts.retentionDays !== undefined ? opts.retentionDays : envNum(process.env.RETENTION_DAYS, 0);
  const retentionMode = (opts.retentionMode || process.env.RETENTION_MODE || 'archive') === 'delete' ? 'delete' : 'archive';
  const refreshHours = envNum(process.env.SOURCE_REFRESH_HOURS, 6);
  const reportHide = opts.reportHideThreshold || 3;
  const rulesAi = createAi({ baseUrl: '', apiKey: '' }), rulesAgent = createAgent({ baseUrl: '', apiKey: '' });
  const guard = createGuard(readJson('fixtures/assistant-policy.json'));
  const startedAt = nowIso();
  const scam = text => ref.scamRules.filter(s => new RegExp(s.pattern).test(text)).map(s => s.reason);
  const purposeIds = NOTICE.purposes.filter(p => !p.feature || (p.feature === 'govConnected' && govOn)).map(p => p.id);

  // ---- shared catalogue ----
  const opps = new Map();
  const fresh = o => ({ ...o, provenance: { ...o.provenance, ageDays: daysAgo(o.provenance.updatedAt) } });
  const reports = [], hiddenByReports = new Set();
  // A10: the same listing from two sources is kept once (first source wins). Key = title + organisation, ignoring
  // spacing, punctuation and bracketed notes.
  const norm = s => String(s || '').toLowerCase().replace(/\(.*?\)/g, '').replace(/[^\p{L}\p{M}\p{N}]+/gu, '');
  const dupKey = o => norm(o.title) + '|' + norm(o.organization);
  function upsert(provider, dataStatus, attribution, input) {
    const id = provider + '_' + input.externalId, key = dupKey(input);
    const dup = [...opps.values()].find(o => o.provenance.provider !== provider && o.id !== id && dupKey(o) === key);
    if (dup) return { id: dup.id, merged: true };
    const reasons = scam(input.title + ' ' + (input.conditions || []).join(' ') + ' ' + (input.suspiciousText || ''));
    if (hiddenByReports.has(id)) reasons.push('ผู้ใช้หลายคนแจ้งว่าน่าสงสัย ซ่อนไว้รอทีมตรวจ');
    opps.set(id, {
      id, title: input.title, organization: input.organization, category: input.category, mapGroup: input.mapGroup,
      location: input.location || { precision: 'none' }, money: input.money, conditions: input.conditions || [],
      provenance: { provider, dataStatus, sourceUrl: input.sourceUrl, updatedAt: input.updatedAt, expiresAt: input.expiresAt, fetchedAt: nowIso(), ageDays: daysAgo(input.updatedAt), attribution },
      suspicious: reasons.length > 0, suspiciousReasons: reasons, checklistTemplateId: input.category,
      skills: Array.isArray(input.skills) && input.skills.length ? input.skills : undefined, forOlder: input.forOlder || undefined
    });
    return { id, merged: false };
  }
  fx.items.forEach(r => upsert('mock', 'mock', 'DEMO / MOCK', {
    externalId: r.id.replace(/^mock_/, ''), title: r.title, organization: r.organization, category: r.category, mapGroup: r.mapGroup,
    location: r.dxKm === undefined ? { precision: 'none' } : { precision: 'exact', text: 'ที่อยู่ตัวอย่าง (สมมติ)', lat: +(fx.center.lat - r.dyKm * 0.009).toFixed(6), lng: +(fx.center.lng + r.dxKm * 0.00926).toFixed(6) },
    money: r.money, conditions: r.conditions, sourceUrl: 'https://example.org/demo/' + r.id, updatedAt: new Date(Date.now() - r.ageDays * 864e5).toISOString(), suspiciousText: r.suspiciousText, skills: r.skills
  }));
  // Broad DEMO catalogue standing in for government and private APIs we cannot connect to yet
  // (fixtures/opportunities-mock.json, generated). On with MOCK_CATALOGUE=1 (the Demo .env); contract tests turn
  // it on for one server only, so counts in the other tests stay stable.
  const moreMock = opts.moreMock !== undefined ? opts.moreMock : process.env.MOCK_CATALOGUE === '1';
  if (moreMock && fs.existsSync(path.join(__dirname, 'fixtures/opportunities-mock.json'))) {
    readJson('fixtures/opportunities-mock.json').items.forEach(r => upsert(r.provider, 'mock', 'DEMO / MOCK (' + r.provider + ')', {
      ...r, sourceUrl: 'https://example.org/mock/' + r.provider + '/' + r.externalId, updatedAt: new Date(Date.now() - r.ageDays * 864e5).toISOString()
    }));
  }
  // Official services with real links (job centre, job fairs, free training), checked by hand. Not mock.
  (fx.official || []).forEach(r => upsert('official', 'curated', 'เว็บไซต์หน่วยงานราชการ (ตรวจลิงก์ ' + r.checkedAt + ')', {
    externalId: r.id, title: r.title, organization: r.organization, category: r.category, mapGroup: r.mapGroup,
    location: { precision: 'none', text: 'ออนไลน์ หรือสำนักงานใกล้บ้าน' }, money: r.money, conditions: r.conditions, sourceUrl: r.sourceUrl, updatedAt: new Date(r.checkedAt).toISOString()
  }));
  const srcState = ref.sources.map(s => ({ provider: s.provider, name: s.name, kind: s.kind, attribution: s.attribution,
    direction: s.url ? 'pull' : s.provider === 'curated' ? 'push' : 'static', state: s.url ? 'idle' : 'static',
    itemCount: [...opps.values()].filter(o => o.provenance.provider === s.provider).length }));
  async function refresh(which) {
    await Promise.all(sources.providers.filter(p => which === 'all' || p === which).map(async p => {
      const st = srcState.find(s => s.provider === p); st.state = 'loading';
      try {
        const r = await sources.pull(p, opts.fetch);
        for (const [k, o] of opps) if (o.provenance.provider === p) opps.delete(k);
        r.items.forEach(i => upsert(p, 'live', st.attribution, i));
        Object.assign(st, { state: 'ok', itemCount: r.items.length, lastFetchedAt: nowIso(), error: undefined });
      } catch (e) { Object.assign(st, { state: 'failed', error: e.name === 'AbortError' ? 'timeout' : e.message }); }
    }));
  }
  if (opts.live) refresh('all');

  // ---- per-device state ----
  const devices = new Map();
  const dev = id => {
    if (!devices.has(id)) devices.set(id, { profile: null, facts: {}, settings: { largeText: false }, consents: [], tasks: [], events: [], sessions: {}, idem: new Map(), memory: [], conversations: {}, gov: { status: 'not_connected' }, docsReady: {}, seq: 1, lastSeenAt: nowIso() });
    return devices.get(id);
  };

  // ---- persistence (B1): load once, save after every successful write ----
  // Layout v2: each device is split into collections (identity / profile / activity / runtime), see adapters/store.js.
  const snapshot = () => ({ version: LAYOUT, savedAt: nowIso(), devices: [...devices].map(([id, d]) => packDevice(id, d)), ingested: [...opps.values()].filter(o => !['mock', 'live'].includes(o.provenance.dataStatus)),
    reports, hiddenByReports: [...hiddenByReports], reminders: notifier.all() });
  const persist = () => { try { store.save(snapshot()); } catch (e) { console.error('store: save failed: ' + e.message); } };
  const saved = store.load();
  if (saved) {
    readDevices(saved).forEach(([id, d]) => devices.set(id, d));
    (saved.ingested || []).forEach(o => opps.set(o.id, o));
    reports.push(...(saved.reports || [])); (saved.hiddenByReports || []).forEach(x => hiddenByReports.add(x));
    notifier.restore(saved.reminders);
    for (const o of saved.ingested || []) if (!srcState.some(s => s.provider === o.provenance.provider))
      srcState.push({ provider: o.provenance.provider, name: o.provenance.provider, kind: 'ส่งเข้าผ่าน Integrations', attribution: o.provenance.attribution, direction: 'push', state: 'ok' });
    srcState.forEach(s => { s.itemCount = [...opps.values()].filter(o => o.provenance.provider === s.provider).length; });
  }

  // ---- AI budget (B4) and call log (B5) ----
  const hashDevice = id => crypto.createHash('sha256').update(String(id)).digest('hex').slice(0, 12);
  function aiFor(d) {
    if ((ai.provider === 'rules' && agent.provider === 'rules') || !(aiDailyLimit > 0)) return { ai, agent };
    const day = nowIso().slice(0, 10);
    if (!d.aiUse || d.aiUse.day !== day) d.aiUse = { day, n: 0 };
    if (d.aiUse.n >= aiDailyLimit) return { ai: rulesAi, agent: rulesAgent, limited: true };
    d.aiUse.n++; return { ai, agent };
  }
  function logAi(device, kind, out) {
    if (!aiLogFile || !out) return;
    try {
      fs.mkdirSync(path.dirname(path.resolve(aiLogFile)), { recursive: true });
      fs.appendFileSync(aiLogFile, JSON.stringify({ at: nowIso(), kind, device: hashDevice(device), provider: kind === 'agent' ? agent.provider : ai.provider, aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId }) + '\n');
    } catch (e) { console.error('ai log: ' + e.message); }
  }
  const curConsent = d => d.consents[d.consents.length - 1];
  const has = (d, p) => { const c = curConsent(d); return !!(c && c.noticeVersion === NOTICE.version && c.purposes[p] === true); };
  const E = (status, code, message, extra = {}) => [status, { code, message, status, retryable: status >= 500, ...extra }];
  const need = (d, p) => has(d, p) ? null : E(403, 'CONSENT_REQUIRED', 'ต้องได้รับความยินยอมเรื่องนี้ก่อน', { missingFields: [p] });
  const govData = d => d.gov.status === 'connected' && has(d, 'gov') ? d.gov.data : null;
  const govIdentity = d => d.gov.status === 'connected' && has(d, 'gov') ? d.gov.identity || null : null;
  // ThaID identity fills the profile and age only where the person has not answered yet; remember what was filled
  // so a disconnect can take it back (data from the government must not stay after the link is removed).
  function applyIdentity(d, id) {
    if (!id) return {};
    const applied = {}, p = d.profile ? { ...d.profile } : {};
    if (!p.displayName) { p.displayName = id.derived.displayName; applied.displayName = { value: p.displayName }; }
    if (!p.district) { const g = geo.geocode(id.derived.district); if (g) { p.district = id.derived.district; p.lat = g.lat; p.lng = g.lng; applied.district = { value: p.district }; } }
    if (Object.keys(applied).length) d.profile = p;
    if (d.facts.ageBand !== id.derived.ageBand) { applied.ageBand = { value: id.derived.ageBand, prev: d.facts.ageBand }; d.facts = { ...d.facts, ageBand: id.derived.ageBand }; }
    return applied;
  }
  function dropGov(d) {
    const a = (d.gov && d.gov.applied) || {}, p = d.profile;
    if (p && a.displayName && p.displayName === a.displayName.value) delete p.displayName;
    if (p && a.district && p.district === a.district.value) { delete p.district; delete p.lat; delete p.lng; }
    if (a.ageBand && d.facts.ageBand === a.ageBand.value) { const f = { ...d.facts }; if (a.ageBand.prev === undefined) delete f.ageBand; else f.ageBand = a.ageBand.prev; d.facts = f; }
    d.gov = { status: 'not_connected' };
  }
  const govOut = d => ({ status: d.gov.status, provider: govAdapter.provider, mock: true, connectedAt: d.gov.connectedAt, ...(govIdentity(d) ? { identity: { ...d.gov.identity, applied: Object.keys(d.gov.applied || {}) } } : {}) });
  const taskOut = t => ({ id: t.id, opportunityId: t.opportunityId, moneyId: t.moneyId, title: t.title, steps: t.steps, doneCount: t.doneCount, status: t.status, reportedBy: 'user', dueText: t.dueText, blockReason: t.blockReason, outcome: t.outcome });
  const searchPoint = (d, q) => q.has('lat') && q.has('lng') ? { lat: +q.get('lat'), lng: +q.get('lng') }
    : d && d.profile && typeof d.profile.lat === 'number' ? { lat: d.profile.lat, lng: d.profile.lng } : { lat: fx.center.lat, lng: fx.center.lng };

  // ---- shared services (used by HTTP routes and by the AI agent) ----
  function search(d, q) {
    const c = searchPoint(d, q), r = q.has('radiusKm') ? +q.get('radiusKm') : 5, group = q.get('group') || 'all', cat = q.get('category'), text = (q.get('q') || '').trim();
    const onlyMoney = q.get('onlyMoney') === 'true', showSus = q.get('showSuspicious') === 'true', sort = q.get('sort') || 'near';
    const key = { near: o => o.location.distanceKm ?? 1e9, money: o => -(o.money.max ?? -1), fresh: o => o.provenance.ageDays ?? 1e9 }[sort];
    if (!key) return null;
    let xs = [...opps.values()].map(fresh).map(o => o.location.precision === 'exact' ? { ...o, location: { ...o.location, distanceKm: +km(c, o.location).toFixed(2) } } : o)
      .filter(o => group === 'all' || o.mapGroup === group).filter(o => !cat || o.category === cat)
      .filter(o => !text || (o.title + ' ' + (o.organization || '')).includes(text))
      .filter(o => !onlyMoney || o.money.basis !== 'none')
      .filter(o => o.location.precision !== 'exact' || o.location.distanceKm <= r)
      .filter(o => o.provenance.linkStatus !== 'broken')
      .filter(o => !o.provenance.expiresAt || new Date(o.provenance.expiresAt) > new Date());
    const hidden = showSus ? 0 : xs.filter(o => o.suspicious).length;
    if (!showSus) xs = xs.filter(o => !o.suspicious);
    const suggestions = [];
    if (!xs.length) {
      if (r < 10) suggestions.push({ type: 'expand_radius', label: 'ขยายระยะเป็น 10 กม.', radiusKm: 10 });
      if (text) suggestions.push({ type: 'clear_query', label: 'ล้างคำค้น' });
      if (group !== 'all') suggestions.push({ type: 'all_groups', label: 'ดูทุกหมวด' });
      if (onlyMoney) suggestions.push({ type: 'include_unknown_money', label: 'รวมรายการที่ไม่ระบุเงิน' });
    }
    return { xs: xs.sort((a, b) => key(a) - key(b)), hidden, suggestions };
  }
  const svc = {
    createTask(d, body) {
      const gate = need(d, 'core'); if (gate) return gate;
      if (body && body.moneyId) {
        const steps = money.claimSteps(body.moneyId); if (!steps) return E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้');
        const ex = d.tasks.find(t => t.moneyId === body.moneyId); if (ex) return [201, taskOut(ex)];
        const p = money.programs.find(x => x.id === body.moneyId), ready = d.docsReady[body.moneyId] || [];
        const t = { id: 't' + d.seq++, moneyId: body.moneyId, title: p.title, steps, doneCount: ready.length === p.docs.length ? 1 : 0, status: 'active' };
        d.tasks.push(t); return [201, taskOut(t)];
      }
      const o = body && opps.get(body.opportunityId); if (!o) return E(404, 'NOT_FOUND', 'ไม่พบโอกาสที่จะบันทึก');
      const ex = d.tasks.find(t => t.opportunityId === o.id); if (ex) return [201, taskOut(ex)];
      const steps = ref.checklists[o.checklistTemplateId] || ['ติดต่อผู้ประกาศ', 'ดำเนินการตามขั้นตอนที่ต้นทาง'];
      const t = { id: 't' + d.seq++, opportunityId: o.id, title: o.title, steps, doneCount: 0, status: 'active' };
      d.tasks.push(t); return [201, taskOut(t)];
    },
    taskEvent(d, device, id, body, key) {
      const gate = need(d, 'core'); if (gate) return gate;
      const t = d.tasks.find(x => x.id === id); if (!t) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้');
      const types = ['complete_step', 'undo', 'block', 'snooze', 'resume', 'report_outcome'];
      if (!body || !types.includes(body.type)) return E(422, 'VALIDATION', 'type ไม่ถูกต้อง');
      if (key && d.idem.has(key)) return d.idem.get(key);
      const before = { doneCount: t.doneCount, status: t.status, dueText: t.dueText, blockReason: t.blockReason, outcome: t.outcome };
      if (body.type === 'complete_step') {
        if (t.status === 'finished') return E(409, 'CONFLICT', 'งานนี้ครบทุกขั้นแล้ว');
        t.doneCount++; t.status = t.doneCount >= t.steps.length ? 'finished' : 'active'; t.blockReason = undefined;
      } else if (body.type === 'undo') {
        const last = [...d.events].reverse().find(e => e.taskId === t.id && !e.undone && e.type !== 'undo');
        if (!last) return E(409, 'CONFLICT', 'ไม่มีอะไรให้เลิกทำ');
        Object.assign(t, last.before); last.undone = true;
      } else if (body.type === 'block') { t.status = 'blocked'; t.blockReason = body.reason || 'other'; }
      else if (body.type === 'snooze') {
        const until = body.until || 'tomorrow';
        if (until === 'never') { notifier.cancel(device, t.id); t.dueText = undefined; }
        else {
          const days = { tomorrow: 1, in_3_days: 3, next_week: 7 }[until]; if (!days) return E(422, 'VALIDATION', 'until ไม่ถูกต้อง');
          t.status = 'snoozed'; t.dueText = { tomorrow: 'เตือนพรุ่งนี้', in_3_days: 'เตือนอีก 3 วัน', next_week: 'เตือนสัปดาห์หน้า' }[until];
          if (has(d, 'reminders')) notifier.schedule(device, t.id, new Date(Date.now() + days * 864e5).toISOString());
        }
      } else if (body.type === 'resume') { t.status = t.doneCount >= t.steps.length ? 'finished' : 'active'; t.blockReason = undefined; t.dueText = undefined; notifier.cancel(device, t.id); }
      else if (body.type === 'report_outcome') {
        if (!['received', 'not_received', 'rejected', 'other'].includes(body.result)) return E(422, 'VALIDATION', 'result ไม่ถูกต้อง');
        if (body.amountReported !== undefined && (typeof body.amountReported !== 'number' || body.amountReported < 0)) return E(422, 'VALIDATION', 'amountReported ต้องเป็นตัวเลข');
        t.outcome = { result: body.result, amountReported: body.amountReported, reportedBy: 'user', at: nowIso() };
        if (body.result === 'received') { t.doneCount = t.steps.length; t.status = 'finished'; }
      }
      d.events.push({ id: 'ev' + d.seq++, taskId: t.id, type: body.type, before, at: nowIso() });
      const result = [201, taskOut(t)]; if (key) d.idem.set(key, result); return result;
    },
    patchFacts(d, body) {
      const gate = need(d, 'core'); if (gate) return gate;
      const { errors, clean } = money.validateFacts(body);
      if (errors.length) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง', { missingFields: errors });
      for (const [k, v] of Object.entries(clean)) v === undefined ? delete d.facts[k] : d.facts[k] = v;
      return [200, d.facts];
    }
  };

  // ---- agent tools: what the AI may see and do for this one user ----
  function agentTools(d, device) {
    return {
      get_money_overview: { mode: 'read', description: 'สรุปเงินที่ผู้ใช้อาจได้ และสถานะแต่ละรายการ', parameters: { type: 'object', properties: {} }, run: () => money.list(d.facts, govData(d)) },
      get_money_route: { mode: 'read', description: 'ขั้นตอนรับเงินของรายการหนึ่ง', parameters: { type: 'object', properties: { moneyId: { type: 'string' } }, required: ['moneyId'] }, run: a => money.route(a.moneyId, d.facts, govData(d), d.docsReady[a.moneyId]) || { error: 'not found' } },
      search_opportunities: { mode: 'read', description: 'ค้นหาโอกาสใกล้ผู้ใช้', parameters: { type: 'object', properties: { q: { type: 'string' }, group: { type: 'string' }, limit: { type: 'integer' } } },
        run: a => { const q = new URLSearchParams(); if (a.q) q.set('q', a.q); if (a.group) q.set('group', a.group); const r = search(d, q); return { items: r.xs.slice(0, Math.min(5, a.limit || 3)).map(o => ({ id: o.id, title: o.title, money: o.money, distanceKm: o.location.distanceKm, dataStatus: o.provenance.dataStatus })) }; } },
      plan_income_goal: { mode: 'read', description: 'วางแผนให้ได้รายได้ต่อเดือนตามเป้าที่ผู้ใช้บอก (บาท) จากเงินสวัสดิการที่น่าจะได้ งาน และทักษะของผู้ใช้ ใช้ตัวเลขจากผลนี้เท่านั้น',
        parameters: { type: 'object', properties: { target: { type: 'integer', description: 'บาทต่อเดือน' } }, required: ['target'] }, run: a => goalPlan(d, Math.max(1, Math.min(1000000, Math.round(+a.target || 0)))) },
      list_tasks: { mode: 'read', description: 'งานในแผนของผู้ใช้', parameters: { type: 'object', properties: {} }, run: () => ({ items: d.tasks.map(taskOut) }) },
      get_profile: { mode: 'read', description: 'โปรไฟล์ของผู้ใช้ (ไม่มีชื่อ)', parameters: { type: 'object', properties: {} }, run: () => { const { displayName, ...p } = d.profile || {}; return p; } },
      create_task: { mode: 'confirm', description: 'บันทึกโอกาสหรือรายการเงินเข้าแผน (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { opportunityId: { type: 'string' }, moneyId: { type: 'string' } } },
        label: a => 'บันทึกเข้าแผนของฉัน: ' + ((a.moneyId && (money.programs.find(p => p.id === a.moneyId) || {}).title) || (opps.get(a.opportunityId) || {}).title || 'รายการนี้'), exec: a => svc.createTask(d, a) },
      snooze_task: { mode: 'confirm', description: 'ตั้งเตือนงานภายหลัง (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { taskId: { type: 'string' }, until: { type: 'string', enum: ['tomorrow', 'in_3_days', 'next_week'] } }, required: ['taskId'] },
        label: a => 'เตือนงานนี้ ' + ({ tomorrow: 'พรุ่งนี้', in_3_days: 'อีก 3 วัน', next_week: 'สัปดาห์หน้า' }[a.until] || 'พรุ่งนี้'), exec: a => svc.taskEvent(d, device, a.taskId, { type: 'snooze', until: a.until || 'tomorrow' }) },
      complete_step: { mode: 'confirm', description: 'บันทึกว่าทำขั้นปัจจุบันเสร็จ (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { taskId: { type: 'string' } }, required: ['taskId'] },
        label: () => 'บันทึกว่าทำขั้นนี้เสร็จแล้ว', exec: a => svc.taskEvent(d, device, a.taskId, { type: 'complete_step' }) },
      update_facts: { mode: 'confirm', description: 'บันทึกข้อมูลสถานการณ์ที่ผู้ใช้บอก (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { facts: { type: 'object' } }, required: ['facts'] },
        label: a => 'บันทึกคำตอบ: ' + Object.entries(a.facts || {}).map(([k, v]) => ((ref.facts[k] || {}).short || k) + ' = ' + (v === true ? 'ใช่' : v === false ? 'ไม่ใช่' : v)).join(', '), exec: a => svc.patchFacts(d, a.facts) },
      remember: { mode: 'memory', description: 'จำความชอบหรือข้อจำกัดสั้นๆ ของผู้ใช้', parameters: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } }
    };
  }

  const R = [];
  const on = (method, pattern, fn, o = {}) => R.push({ method, re: new RegExp('^' + pattern.replace(/\{(\w+)\}/g, '(?<$1>[^/]+)') + '$'), fn, ...o });

  // System + config + privacy
  on('GET', '/v1/health', () => [200, { status: 'ok', version: readJson('package.json').version, commit: COMMIT, startedAt, ai: { provider: ai.provider, agent: agent.provider }, features: { govConnected: govOn, demo: demoOn }, sources: srcState.map(s => ({ provider: s.provider, state: s.state })),
    store: store.kind, storeLayout: LAYOUT, retention: { days: retentionDays, mode: retentionMode }, notifier: notifier.kind, aiDailyLimit, jobs: jobs.state }], { public: true });
  on('GET', '/v1/app-config', ({ req }) => {
    const cfg = readJson('app-config.sample.json');
    cfg.featureFlags = { ...cfg.featureFlags, govConnected: govOn, demo: demoOn }; cfg.noticeVersion = NOTICE.version;
    const tag = '"' + cfg.configVersion + '-' + NOTICE.version + (govOn ? '-gov' : '') + (demoOn ? '-demo' : '') + '"';
    return req.headers['if-none-match'] === tag ? [304] : [200, cfg, { ETag: tag, 'Cache-Control': 'no-cache' }];
  }, { public: true });
  on('GET', '/v1/taxonomies', () => [200, { ...ref.taxonomies, facts: ref.facts }], { public: true });
  on('GET', '/v1/privacy/notice', () => [200, { version: NOTICE.version, note: NOTICE.note, sections: NOTICE.sections, purposes: NOTICE.purposes.filter(p => purposeIds.includes(p.id)).map(({ feature, ...p }) => p) }], { public: true });

  // Me
  on('DELETE', '/v1/me', ({ device }) => { devices.delete(device); notifier.cancel(device); return [204]; });
  on('GET', '/v1/me/profile', ({ d }) => d.profile ? [200, { ...d.profile, ...(govIdentity(d) ? { fromGov: Object.keys(d.gov.applied || {}) } : {}) }] : E(404, 'NOT_FOUND', 'ยังไม่มีโปรไฟล์'));
  on('PUT', '/v1/me/profile', ({ d, body }) => {
    const gate = need(d, 'core'); if (gate) return gate;
    if (!body || typeof body !== 'object' || Array.isArray(body)) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง');
    const allowed = ['displayName', 'district', 'lat', 'lng', 'skills', 'hoursPerWeek', 'incomeGoalPerMonth', 'goals', 'constraints'];
    const p = Object.fromEntries(Object.entries(body).filter(([k]) => allowed.includes(k)));
    if (p.district && typeof p.lat !== 'number') { const g = geo.geocode(p.district); if (g) { p.lat = g.lat; p.lng = g.lng; } }
    d.profile = p; return [200, p];
  });
  on('POST', '/v1/me/consents', ({ d, device, body }) => {
    if (!body || typeof body.purposes !== 'object' || body.purposes === null) return E(400, 'VALIDATION', 'ต้องมี noticeVersion, ageConfirmed และ purposes');
    if (body.noticeVersion !== NOTICE.version) return E(422, 'VALIDATION', 'ประกาศที่ยอมรับไม่ใช่ฉบับปัจจุบัน', { missingFields: ['noticeVersion'] });
    if (body.ageConfirmed !== true) return E(422, 'VALIDATION', 'ต้องยืนยันอายุ 20 ปีขึ้นไป หรือผู้ปกครองยินยอม', { missingFields: ['ageConfirmed'] });
    if (body.purposes.core !== true) return E(422, 'VALIDATION', 'ข้อจำเป็นต้องยินยอม ถ้าไม่ต้องการ ให้ลบข้อมูลทั้งหมด', { missingFields: ['purposes.core'] });
    const prev = curConsent(d);
    const purposes = Object.fromEntries(purposeIds.map(id => [id, body.purposes[id] === true]));
    const c = { id: 'c' + d.seq++, noticeVersion: body.noticeVersion, ageConfirmed: true, purposes, at: nowIso() };
    d.consents.push(c);
    // Withdrawals take effect immediately.
    if (prev && prev.purposes.ai && !purposes.ai) { d.memory = d.memory.filter(m => m.source !== 'ai'); d.conversations = {}; }
    if (!purposes.reminders) notifier.cancel(device);
    if (!purposes.gov && d.gov.status !== 'not_connected') dropGov(d);
    return [201, c];
  });
  on('GET', '/v1/me/consents', ({ d }) => { const c = curConsent(d); return [200, { current: c, noticeVersion: NOTICE.version, needsRenewal: !c || c.noticeVersion !== NOTICE.version, items: d.consents }]; });
  on('GET', '/v1/me/settings', ({ d }) => [200, d.settings]);
  on('PATCH', '/v1/me/settings', ({ d, body }) => {
    d.settings = { ...d.settings, ...Object.fromEntries(Object.entries(body || {}).filter(([k, v]) => k === 'largeText' && typeof v === 'boolean')) };
    return [200, d.settings];
  });
  on('GET', '/v1/me/facts', ({ d }) => [200, d.facts]);
  on('PATCH', '/v1/me/facts', ({ d, body }) => svc.patchFacts(d, body));
  on('GET', '/v1/me/memory', ({ d }) => [200, { items: d.memory }]);
  on('POST', '/v1/me/memory', ({ d, body }) => {
    const gate = need(d, 'core'); if (gate) return gate;
    const text = body && typeof body.text === 'string' ? body.text.trim().slice(0, 200) : '';
    if (!text) return E(422, 'VALIDATION', 'ต้องมีข้อความ');
    const m = { id: 'm' + d.seq++, text, source: 'user', at: nowIso() }; d.memory.push(m); return [201, m];
  });
  on('DELETE', '/v1/me/memory/{id}', ({ d, p }) => { const i = d.memory.findIndex(m => m.id === p.id); if (i < 0) return E(404, 'NOT_FOUND', 'ไม่พบบันทึกนี้'); d.memory.splice(i, 1); return [204]; });
  on('GET', '/v1/me/export', ({ d }) => [200, { profile: d.profile || {}, facts: d.facts, settings: d.settings, tasks: d.tasks.map(taskOut), consents: d.consents, memory: d.memory,
    govLink: { status: d.gov.status, provider: d.gov.provider, connectedAt: d.gov.connectedAt, ...(d.gov.identity ? { identity: d.gov.identity } : {}) },
    storedFields: ['profile', 'facts', 'settings', 'tasks', 'consents', 'memory', 'govLink'], notStored: ['ประวัติแชทกับ AI (เก็บเฉพาะระหว่างคุย)', 'เลขบัตรประชาชน', 'รหัสผ่าน OTP PIN'] }]);

  // Government connection (hidden mode)
  const govGate = () => govOn ? null : E(404, 'FEATURE_DISABLED', 'โหมดเชื่อมรัฐยังไม่เปิดใช้');
  on('GET', '/v1/me/gov-link', ({ d }) => govGate() || [200, govOut(d)]);
  on('POST', '/v1/me/gov-link', ({ d, device }) => { const g = govGate() || need(d, 'gov'); if (g) return g; const s = govAdapter.start(device); d.gov = { status: 'pending' }; return [201, { status: s.status, provider: govAdapter.provider, mock: true, authUrl: s.authUrl, state: s.state }]; });
  on('POST', '/v1/me/gov-link/callback', ({ d, device, body }) => {
    const g = govGate() || need(d, 'gov'); if (g) return g;
    const r = govAdapter.finish(device, body && body.state, body && body.code, d.facts, d.profile || {}); if (!r) return E(422, 'VALIDATION', 'state หรือ code ไม่ถูกต้อง');
    d.gov = r; d.gov.applied = applyIdentity(d, r.identity); return [200, govOut(d)];
  });
  on('DELETE', '/v1/me/gov-link', ({ d }) => { const g = govGate(); if (g) return g; dropGov(d); return [204]; });

  // Intake
  const turn = (sid, s) => {
    const Q = ref.intake;
    if (s.i >= Q.length) return { sessionId: sid, aiStatus: s.aiStatus, done: true, question: 'สรุปข้อมูลแล้ว ถูกต้องไหมคะ', profileDraft: s.draft };
    return { sessionId: sid, aiStatus: s.aiStatus, done: false, question: Q[s.i].question, quickReplies: Q[s.i].quickReplies, profileDraft: s.draft };
  };
  on('POST', '/v1/intake/sessions', ({ d }) => { const g = need(d, 'core'); if (g) return g; const sid = 's' + d.seq++; d.sessions[sid] = { i: 0, draft: {}, aiStatus: has(d, 'ai') ? 'fallback_rules' : 'skipped_no_consent' }; return [201, turn(sid, d.sessions[sid])]; });
  on('POST', '/v1/intake/sessions/{id}/messages', async ({ d, device, p, body }) => {
    const s = d.sessions[p.id]; if (!s) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    if (!body || typeof body.text !== 'string' || !body.text.trim()) return E(422, 'VALIDATION', 'ต้องมีข้อความ');
    const Q = ref.intake; if (s.i >= Q.length) return [200, turn(p.id, s)];
    const q = Q[s.i], k = q.key, field = { question: q.question, options: ['goals', 'hoursPerWeek'].includes(k) ? q.quickReplies : undefined, number: k === 'incomeGoalPerMonth' };
    let v = body.text.trim();
    if (has(d, 'ai')) { const r = await aiFor(d).ai.extract(field, v); logAi(device, 'extract', r); v = r.value; s.aiStatus = r.aiStatus; } else v = require('./adapters/ai').rulesExtract(field, v);
    s.draft[k] = k === 'skills' || k === 'goals' ? [String(v)] : v;
    if (k === 'district') { const g = geo.geocode(v); if (g) { s.draft.lat = g.lat; s.draft.lng = g.lng; } }
    s.i++; return [200, turn(p.id, s)];
  });

  // Opportunities
  on('GET', '/v1/opportunities', ({ d, q }) => {
    const res = search(d, q); if (!res) return E(400, 'VALIDATION', 'sort ไม่ถูกต้อง');
    const limit = Math.min(100, Math.max(1, +(q.get('limit') || 30)));
    const start = q.get('cursor') ? +Buffer.from(q.get('cursor'), 'base64url').toString() || 0 : 0;
    const warn = srcState.filter(s => s.state === 'failed').map(s => s.provider);
    return [200, { items: res.xs.slice(start, start + limit), nextCursor: start + limit < res.xs.length ? Buffer.from(String(start + limit)).toString('base64url') : undefined,
      hiddenSuspicious: res.hidden, suggestions: res.suggestions.length ? res.suggestions : undefined, sourceWarnings: warn.length ? warn : undefined }, { 'X-Total-Count': String(res.xs.length) }];
  });
  on('GET', '/v1/opportunities/{id}', ({ p }) => opps.has(p.id) ? [200, fresh(opps.get(p.id))] : E(404, 'NOT_FOUND', 'ไม่พบรายการนี้'), { public: true });
  on('POST', '/v1/opportunities/{id}/reports', ({ device, p, body }) => {
    if (!opps.has(p.id)) return E(404, 'NOT_FOUND', 'ไม่พบรายการนี้');
    if (!body || !['suspicious', 'wrong_info', 'expired', 'other'].includes(body.reason)) return E(400, 'VALIDATION', 'reason ไม่ถูกต้อง');
    reports.push({ device: hashDevice(device), id: p.id, reason: body.reason, note: body.note, at: nowIso() });
    // A13: enough different devices saying "suspicious" hides the item until the team reviews it.
    const n = new Set(reports.filter(r => r.id === p.id && r.reason === 'suspicious').map(r => r.device)).size, o = opps.get(p.id);
    if (n >= reportHide && !hiddenByReports.has(p.id)) { hiddenByReports.add(p.id); o.suspicious = true; o.suspiciousReasons = [...o.suspiciousReasons, 'ผู้ใช้หลายคนแจ้งว่าน่าสงสัย ซ่อนไว้รอทีมตรวจ']; }
    return [202];
  });

  // Money
  on('GET', '/v1/money', ({ d }) => [200, { ...money.list(d.facts, govData(d)), govLink: govOn ? d.gov.status : 'disabled' }]);
  // Check money from answers without storing anything (before consent). Same engine, no device state.
  on('POST', '/v1/money/preview', ({ body }) => {
    const { errors, clean } = money.validateFacts(body && body.facts);
    if (errors.length) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง', { missingFields: errors });
    const facts = Object.fromEntries(Object.entries(clean).filter(([, v]) => v !== undefined));
    const r = money.list(facts, null), next = r.items.find(i => i.status === 'need' && i.nextQuestion);
    return [200, { ...r, nextQuestion: next ? { ...next.nextQuestion, moneyId: next.id } : undefined, stored: false }];
  }, { public: true });
  on('GET', '/v1/money/{id}', ({ d, p }) => { const r = money.route(p.id, d.facts, govData(d), d.docsReady[p.id]); return r ? [200, r] : E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้'); });
  on('PATCH', '/v1/money/{id}', ({ d, p, body }) => {
    const g = need(d, 'core'); if (g) return g;
    const prog = money.programs.find(x => x.id === p.id); if (!prog) return E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้');
    const ready = body && Array.isArray(body.documentsReady) ? body.documentsReady : null;
    if (!ready || ready.some(i => !Number.isInteger(i) || i < 0 || i >= prog.docs.length)) return E(422, 'VALIDATION', 'documentsReady ต้องเป็นลำดับเอกสารที่มีจริง');
    d.docsReady[p.id] = [...new Set(ready)]; return [200, money.route(p.id, d.facts, govData(d), d.docsReady[p.id])];
  });

  // AI one-shot
  on('POST', '/v1/ai/rankings', async ({ d, device, body }) => {
    const ids = body && Array.isArray(body.opportunityIds) ? body.opportunityIds : [];
    if (!ids.length) return E(400, 'VALIDATION', 'ต้องมี opportunityIds อย่างน้อย 1 รายการ');
    const candidates = [...new Set(ids)].slice(0, 50).map(id => opps.get(id)).filter(o => o && !o.suspicious);
    if (!has(d, 'ai')) { const r = require('./adapters/ai').rulesRank(d.profile, candidates); return [200, { aiStatus: 'skipped_no_consent', ranked: r }]; }
    const out = await aiFor(d).ai.rank(d.profile, candidates); logAi(device, 'rank', out);
    return [200, { aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId, ranked: out.ranked }];
  });
  on('POST', '/v1/ai/explanations', async ({ d, device, body }) => {
    if (!body || !['task_step', 'opportunity', 'money'].includes(body.subjectType) || !body.subjectId) return E(400, 'VALIDATION', 'ต้องมี subjectType และ subjectId');
    let subject;
    if (body.subjectType === 'task_step') { const t = d.tasks.find(x => x.id === body.subjectId); if (!t) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); subject = { type: 'task_step', title: t.title, step: t.steps[Math.min(t.doneCount, t.steps.length - 1)] }; }
    else if (body.subjectType === 'opportunity') { const o = opps.get(body.subjectId); if (!o) return E(404, 'NOT_FOUND', 'ไม่พบรายการนี้'); subject = { type: 'opportunity', opportunity: { title: o.title, conditions: o.conditions, category: o.category } }; }
    else { const r = money.route(body.subjectId, d.facts, govData(d)); if (!r) return E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้'); subject = { type: 'opportunity', opportunity: { title: r.title, conditions: r.reasons.map(x => x.text), category: 'money' } }; }
    if (!has(d, 'ai')) return [200, { aiStatus: 'skipped_no_consent', text: (await createAi({ baseUrl: '', apiKey: '' }).explain(subject)).text }];
    const out = await aiFor(d).ai.explain(subject); logAi(device, 'explain', out);
    return [200, { aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId, text: out.text }];
  });

  // AI assistant (agent)
  // Guided checklist: the next missing fact, in program order, from the money engine itself.
  // Facts the person already gave (anywhere in the app) are never asked again; skipped ones wait until the end.
  // After an answer, finish the same program first ("has a child under 6" -> "family income"), so a likely
  // benefit is not left half-asked while other programs' questions come in between.
  const nextStep = (d, skipped = [], prefer) => {
    const open = money.list(d.facts, govData(d)).items.filter(i => i.status === 'need' && i.nextQuestion && !skipped.includes(i.nextQuestion.fact));
    const it = open.find(i => i.id === prefer) || open[0];
    return it ? { ...it.nextQuestion, moneyId: it.id } : null;
  };
  const ANSWER_START = /^(ใช่|ไม่|มี|เคย|ได้|ทำ|ยัง|เป็น|อายุ)/;
  // Answered from data, never by the model: next steps, contacts, and "what money should I get" (the model
  // listed every program, including ones the person has not qualified for).
  const DIRECT_RE = /ลิงก์|ลิงค์|link|เว็บ|ติดต่อ|เบอร์|โทร|ช่องทาง|ทำไง|ต้องทำ|ทำอะไรต่อ|ขั้นตอน|บริบท|ควรได้|ได้อะไร|สิทธิ์อะไร|เงินอะไร|จากรัฐ/i;
  const stepQuick = s => s && s.options ? [...s.options, guard.skipQuickReply] : undefined;
  on('POST', '/v1/ai/conversations', ({ d, body }) => {
    const g = need(d, 'ai'); if (g) return g;
    const id = 'conv' + d.seq++, guided = !body || body.mode !== 'free';
    const step = guided ? nextStep(d) : null;
    d.conversations[id] = { history: [], pending: {}, expect: step, skipped: [] };
    return [201, { conversationId: id, greeting: 'สวัสดีค่ะ ถามเรื่องเงินของคุณได้เลย' + (step ? '\nเริ่มจากข้อนี้: ' + step.question : ''),
      quickReplies: stepQuick(step) || ['เงินฉันอยู่ไหน', 'เอกสารที่ยังขาด', 'หางานใกล้บ้าน'], step: step || undefined }];
  });
  on('POST', '/v1/ai/conversations/{id}/messages', async ({ d, device, p, body }) => {
    const g = need(d, 'ai'); if (g) return g;
    const c = d.conversations[p.id]; if (!c) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    if (!body || typeof body.text !== 'string' || !body.text.trim()) return E(422, 'VALIDATION', 'ต้องมีข้อความ');
    const text = body.text.trim().slice(0, 1000), tools = agentTools(d, device);
    const turn = (reply, kind, extra = {}) => [200, { aiStatus: 'guarded', reply, toolCalls: [], pendingActions: [], memoryAdded: [], guard: { kind, policyVersion: guard.version },
      step: c.expect || undefined, quickReplies: stepQuick(c.expect) || ['เงินฉันอยู่ไหน', 'เอกสารที่ยังขาด', 'หางานใกล้บ้าน'], ...extra }];
    let v = guard.check(text, c.expect);
    // "อยากได้เดือนละ 10,000": the goal plan, computed from data (not the model), before any answer parsing.
    const { goalTarget } = require('./adapters/agent');
    if (['unclear', 'in_scope', 'answer'].includes(v.kind) && !(c.expect && c.expect.options && c.expect.options.includes(text)) && goalTarget(text)) {
      const r = await rulesAgent.respond({ text, tools });
      c.goal = goalTarget(text);
      return turn(r.reply + (c.expect ? '\n\nเพื่อให้แผนแม่นขึ้น ตอบข้อนี้ต่อ: ' + c.expect.question : ''), 'in_scope', { toolCalls: r.toolCalls.map(t => ({ tool: t.tool })), quickReplies: stepQuick(c.expect) || r.quickReplies });
    }
    // A free-text reply to the current question ("อายุ 65") may still be an answer: normalise it, keep it only if valid.
    if (v.kind === 'unclear' && c.expect) {
      const r = await aiFor(d).ai.extract({ question: c.expect.question, options: c.expect.options, number: c.expect.type === 'number' }, text);
      // Only text that looks like an answer counts (a number, a yes/no word, or the option itself). The model must not
      // turn "แนะนำร้านกาแฟหน่อย" into a stored fact just because it was forced to pick an option.
      const looksLikeAnswer = /\d/.test(text) || ANSWER_START.test(text) || (r.value !== undefined && text.includes(String(r.value)));
      if (looksLikeAnswer && ((c.expect.options && c.expect.options.includes(r.value)) || (c.expect.type === 'number' && typeof r.value === 'number'))) v = { kind: 'answer', value: String(r.value) };
    }
    if (v.kind === 'explain') {
      const q = c.expect;
      return turn('ข้อนี้ถามว่า: ' + q.question + (q.help ? '\n' + q.help : '') + (q.options ? '\nตอบได้: ' + q.options.join(' / ') : '\nตอบเป็นตัวเลข') + '\nไม่แน่ใจ กด "' + guard.skipQuickReply + '" ได้', 'explain');
    }
    if (v.kind === 'skip') {
      c.skipped = [...(c.skipped || []), c.expect.fact];
      c.expect = nextStep(d, c.skipped);
      return turn('ได้ค่ะ ข้ามข้อนี้ไปก่อน' + (c.expect ? '\nข้อต่อไป: ' + c.expect.question : '\nไม่มีคำถามอื่นแล้ว ถามเรื่องเงินของคุณต่อได้เลย'), 'skip');
    }
    if (v.kind === 'answer') {
      // The person picked an option the app offered: this is their own entry, not an AI write.
      const [st, res] = svc.patchFacts(d, { [c.expect.fact]: toFact(c.expect, v.value || text) });
      if (st >= 400) return turn('คำตอบนี้ใช้ไม่ได้ ลองเลือกจากตัวเลือกอีกครั้ง\n' + c.expect.question, 'answer');
      c.expect = nextStep(d, c.skipped || [], c.expect.moneyId);
      if (c.expect) return turn('บันทึกแล้ว\nข้อต่อไป: ' + c.expect.question, 'answer');
      const sum = await require('./adapters/agent').rulesAgent({ text: 'เงินฉันอยู่ไหน', tools });
      return turn('บันทึกแล้ว ตอบครบแล้ว\n' + sum.reply + '\nขั้นต่อไป: เตรียมเอกสาร แล้วไปยื่นตามช่องทางในแอป', 'answer', { toolCalls: sum.toolCalls.map(t => ({ tool: t.tool })), quickReplies: ['เอกสารที่ยังขาด', 'ไปรับเงินยังไง', 'หางานใกล้บ้าน'] });
    }
    // No keyword matched but nothing was refused either ("ขอลิงก์ติดต่อหน่อย"): with a real model, let it judge under
    // the scope prompt (it declines off-topic text). Without a model, redirect as before.
    let scopeByAi = v.kind === 'unclear' && agent.provider !== 'rules';
    if (scopeByAi) {
      // Short yes/no check first; off-topic text gets the fixed refusal, never the model's own words.
      const k = await aiFor(d).ai.extract({ question: 'ข้อความของผู้ใช้เกี่ยวกับเรื่องเหล่านี้ไหม: ' + guard.scope, options: ['เกี่ยว', 'ไม่เกี่ยว'] }, text);
      if (k.value !== 'เกี่ยว') { scopeByAi = false; v = { kind: 'off_topic', reply: guard.offTopicReply }; }
    }
    if (v.kind !== 'in_scope' && !scopeByAi) {
      // Refused or unclear: never sent to the model, never added to history or memory.
      return turn(v.reply + '\n' + (c.expect ? 'กลับมาที่คำถาม: ' + c.expect.question : guard.redirect), v.kind);
    }
    // "What do I do / give me the link or phone": answered from the published route data, never from the model,
    // so it cannot list programs the person does not qualify for or invent a contact.
    if (DIRECT_RE.test(text)) {
      const r = await rulesAgent.respond({ text, tools });
      const pa = r.pending.filter(x => tools[x.tool] && tools[x.tool].mode === 'confirm').map(x => { const aid = 'pa' + d.seq++; c.pending[aid] = x; return { id: aid, tool: x.tool, label: x.label }; });
      return turn(r.reply + (c.expect ? '\nกลับมาที่คำถาม: ' + c.expect.question : ''), 'in_scope', { toolCalls: r.toolCalls.map(t => ({ tool: t.tool })), pendingActions: pa, quickReplies: stepQuick(c.expect) || r.quickReplies });
    }
    const out = await aiFor(d).agent.respond({ text, history: c.history, memory: d.memory.map(m => m.text), profile: d.profile || {}, tools,
      systemPrompt: guard.systemPrompt(c.expect ? 'ถามข้อนี้: ' + c.expect.question : 'ช่วยต่อตามเช็คลิสต์') });
    const pendingActions = out.pending.filter(x => tools[x.tool] && tools[x.tool].mode === 'confirm').map(x => { const aid = 'pa' + d.seq++; c.pending[aid] = x; return { id: aid, tool: x.tool, label: x.label }; });
    logAi(device, 'agent', out);
    const memoryAdded = out.memory.map(text => { const m = { id: 'm' + d.seq++, text: text.slice(0, 200), source: 'ai', at: nowIso() }; d.memory.push(m); return m; });
    c.history.push({ role: 'user', content: body.text }, { role: 'assistant', content: out.reply });
    return [200, { aiStatus: out.aiStatus, aiInvocationId: 'agent-' + crypto.randomUUID().slice(0, 8), reply: out.reply + (c.expect ? '\nกลับมาที่คำถาม: ' + c.expect.question : ''),
      toolCalls: out.toolCalls.map(t => ({ tool: t.tool })), pendingActions, memoryAdded, quickReplies: stepQuick(c.expect) || out.quickReplies,
      guard: { kind: scopeByAi ? 'ai_scope' : 'in_scope', policyVersion: guard.version }, step: c.expect || undefined }];
  });
  on('POST', '/v1/ai/conversations/{id}/actions/{actionId}', ({ d, device, p, body }) => {
    const g = need(d, 'ai'); if (g) return g;
    const c = d.conversations[p.id]; if (!c) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    const a = c.pending[p.actionId]; if (!a) return E(404, 'NOT_FOUND', 'ไม่พบคำขอนี้ หรือทำไปแล้ว');
    if (!body || !['confirm', 'reject'].includes(body.decision)) return E(422, 'VALIDATION', 'decision ต้องเป็น confirm หรือ reject');
    delete c.pending[p.actionId];
    if (body.decision === 'reject') return [200, { status: 'rejected' }];
    const [st, result] = agentTools(d, device)[a.tool].exec(a.args);
    return st < 300 ? [200, { status: 'done', result }] : [st, result];
  });

  // Planner
  const hoursOf = d => HOURS[(d && d.profile && d.profile.hoursPerWeek) || ''];
  on('GET', '/v1/plans/options', ({ d, q }) => [200, { items: planOptions(d, (q.get('opportunityIds') || '').split(',').filter(Boolean)) }]);
  on('GET', '/v1/plans/goal', ({ d, q }) => {
    const t = q.has('target') ? +q.get('target') : d.profile && d.profile.incomeGoalPerMonth;
    if (!(t > 0) || t > 1000000) return E(400, 'VALIDATION', 'ต้องมี target เป็นจำนวนเงินต่อเดือน (บาท) หรือบันทึกเป้ารายได้ในโปรไฟล์');
    return [200, goalPlan(d, Math.round(t))];
  });
  // "I want X baht this month": benefits the person likely qualifies for (sourced rates) + the best-fitting
  // earning options for their skills and free time, until the low end reaches the goal. Ranges, never a promise.
  function goalPlan(d, target) {
    const skills = (d.profile && d.profile.skills) || [], h = hoursOf(d);
    const mList = money.list(d.facts, govData(d)).items;
    const benefits = mList.filter(i => ['likely', 'verified'].includes(i.status) && i.kind === 'monthly' && typeof i.amount.value === 'number')
      .map(i => ({ kind: 'benefit', id: i.id, title: i.title, net: [i.amount.value, i.amount.value], numberSource: 'official', dataStatus: i.dataStatus,
        why: i.status === 'verified' ? 'ยืนยันจากหน่วยงาน' : 'เงินสวัสดิการที่น่าจะมีสิทธิ์ ยังไม่ยืนยัน', action: { type: 'money_route', id: i.id } }));
    const ideas = ref.skillIdeas.map(i => ({ kind: 'skill', id: i.id, title: i.title, net: [i.grossPerMonth[0] - i.costPerMonth[1], i.grossPerMonth[1] - i.costPerMonth[0]],
      numberSource: 'estimate', dataStatus: 'mock', requires: i.skills, matched: i.skills.filter(s => skills.includes(s)), assumptions: i.assumptions, why: 'ประมาณการ ยังไม่มีผู้ซื้อยืนยัน', action: { type: 'idea', id: i.id } }));
    const jobs = jobOptions(d);
    // Skill matches first, then (for people 60+) jobs that accept older workers, then the higher low end.
    // Free time limits how many earning options fit.
    const older = d.facts.ageBand && d.facts.ageBand !== 'ต่ำกว่า 60';
    // Only options the person can do: no special skill needed, or at least one of their skills matches.
    const pool = [...ideas, ...jobs].filter(x => !(x.requires || []).length || x.matched.length)
      .filter((x, i, a) => a.findIndex(y => y.title === x.title) === i)
      .sort((a, b) => (b.matched.length > 0) - (a.matched.length > 0) || (older ? (!!b.forOlder) - (!!a.forOlder) : 0) || b.net[0] - a.net[0]);
    const room = h === undefined ? 2 : h >= 40 ? 3 : h >= 15 ? 2 : 1;
    const parts = [...benefits];
    let low = benefits.reduce((s, x) => s + x.net[0], 0);
    for (const x of pool) { if (low >= target || parts.length - benefits.length >= room) break; parts.push(x); low += x.net[0]; }
    parts.forEach(x => { delete x.requires; delete x.forOlder; });
    const total = [parts.reduce((s, x) => s + x.net[0], 0), parts.reduce((s, x) => s + x.net[1], 0)];
    const missing = [];
    if (!Object.keys(d.facts).length) missing.push({ id: 'money_check', text: 'ยังไม่ได้เช็คเงินที่ควรได้จากรัฐ อาจมีเงินเพิ่ม' });
    else if (mList.some(i => i.status === 'need')) missing.push({ id: 'money_check', text: 'ยังมีคำถามเรื่องเงินจากรัฐที่ยังไม่ได้ตอบ อาจมีเงินเพิ่ม' });
    if (!skills.length) missing.push({ id: 'skills', text: 'ยังไม่รู้ทักษะของคุณ บอกทักษะแล้วแผนจะตรงตัวขึ้น' });
    if (h === undefined) missing.push({ id: 'hours', text: 'ยังไม่รู้เวลาว่างต่อสัปดาห์ จึงคิดไว้ไม่เกิน 2 ทาง' });
    return { target, parts, total, gap: Math.max(0, target - total[0]), reach: total[0] >= target ? 'likely' : total[1] >= target ? 'maybe' : 'short',
      missing, hoursPerWeek: h, note: 'เป็นการวางแผนจากเกณฑ์ที่ประกาศ ค่าจ้างในประกาศ และประมาณการ ไม่ใช่รายได้ที่รับประกัน งานและลูกค้าต้องหาเองตามขั้นในแผน' };
  }
  // Monthly range for every job listing that states a wage, from the person's free time (default 20 h/week).
  // A full-time monthly job only fits with 30+ free hours. Travel cost is not deducted (said in assumptions).
  function jobOptions(d) {
    const h = hoursOf(d), hw = h === undefined ? 20 : h, skills = (d.profile && d.profile.skills) || [];
    const best = new Map();
    for (const o of opps.values()) {
      if (o.mapGroup !== 'job' || o.suspicious || o.money.basis !== 'listing' || typeof o.money.min !== 'number') continue;
      const unit = o.money.unit || '';
      let f, basis;
      if (/เดือน/.test(unit)) { if (hw < 30 && o.category === 'job_full') continue; f = 1; basis = 'ค่าจ้างรายเดือนตามประกาศ'; }
      else if (/วัน/.test(unit)) { const days = Math.min(6, Math.max(1, Math.round(hw / 8))); f = days * 4.33; basis = days + ' วัน/สัปดาห์ ตามเวลาว่าง ' + hw + ' ชม.'; }
      else if (/ชั่วโมง/.test(unit)) { f = hw * 4.33; basis = hw + ' ชม./สัปดาห์ ตามเวลาว่าง'; }
      else continue;
      const net = [Math.round(o.money.min * f), Math.round((o.money.max || o.money.min) * f)];
      const x = { kind: 'job', id: o.id, title: o.title, net, numberSource: 'listing', dataStatus: o.provenance.dataStatus, forOlder: o.forOlder, requires: o.skills,
        matched: (o.skills || []).filter(s => skills.includes(s)), assumptions: [basis, 'ยังไม่หักค่าเดินทางและค่าใช้จ่าย' + (/ก่อนหัก/.test(unit) ? ' (' + unit + ')' : '')],
        why: 'ค่าจ้างตามประกาศ' + (o.provenance.dataStatus === 'mock' ? ' (ประกาศตัวอย่าง)' : '') + ' · ' + (o.organization || ''), action: { type: 'opportunity', id: o.id } };
      const k = norm(o.title), prev = best.get(k);
      if (!prev || x.matched.length > prev.matched.length || (x.matched.length === prev.matched.length && x.net[0] > prev.net[0])) best.set(k, x);
    }
    return [...best.values()];
  }
  function planOptions(d, want = []) {
    const h = hoursOf(d);
    return ref.plans.filter(p => !want.length || want.includes(p.opportunityId)).map(p => {
      let x = { ...p }; const o = p.opportunityId && opps.get(p.opportunityId);
      if (h && o && o.money.basis === 'listing' && /วัน|ชั่วโมง/.test(o.money.unit || '')) {
        const units = /ชั่วโมง/.test(o.money.unit) ? h * 4.33 : (h / 6) * 4.33;
        x.grossPerMonth = [Math.round(o.money.min * units), Math.round(o.money.max * units)];
        x.assumptions = ['คิดจากเวลาว่างของคุณ ' + h + ' ชม./สัปดาห์', ...(p.assumptions || []).filter(a => !/วัน\/สัปดาห์/.test(a))];
      }
      return x.grossPerMonth ? { ...x, netPerMonth: [x.grossPerMonth[0] - x.costPerMonth[1], x.grossPerMonth[1] - x.costPerMonth[0]] } : x;
    });
  }
  on('GET', '/v1/plans/ideas', async ({ d }) => {
    const skills = (d.profile && d.profile.skills) || [];
    const pool = ref.skillIdeas.filter(i => !skills.length || i.skills.some(s => skills.includes(s)));
    const ideas = (pool.length ? pool : ref.skillIdeas);
    let order = ideas.map(i => i.id), aiStatus = 'fallback_rules';
    if (has(d, 'ai') && ai.provider !== 'rules') {
      const r = await aiFor(d).ai.rank(d.profile, ideas.map(i => ({ id: i.id, title: i.title, category: 'skill', mapGroup: 'skill', money: { basis: 'listing' }, conditions: i.assumptions, provenance: {} })));
      order = r.ranked.map(x => x.opportunityId); aiStatus = r.aiStatus;
    } else if (!has(d, 'ai')) aiStatus = 'skipped_no_consent';
    return [200, { aiStatus, items: order.map(id => ideas.find(i => i.id === id)).filter(Boolean).map(i => ({ id: i.id, title: i.title, track: 'C', grossPerMonth: i.grossPerMonth, costPerMonth: i.costPerMonth,
      netPerMonth: [i.grossPerMonth[0] - i.costPerMonth[1], i.grossPerMonth[1] - i.costPerMonth[0]], payDays: i.payDays, effort: i.effort, risk: i.risk, numberSource: 'estimate', assumptions: i.assumptions, matchedSkills: i.skills.filter(s => skills.includes(s)) })) }];
  });

  // Tasks
  const findTask = (d, id) => d.tasks.find(t => t.id === id);
  on('GET', '/v1/tasks', ({ d, q }) => [200, { items: d.tasks.filter(t => !q.get('status') || t.status === q.get('status')).map(taskOut) }]);
  on('POST', '/v1/tasks', ({ d, body }) => svc.createTask(d, body));
  on('GET', '/v1/tasks/{id}', ({ d, p }) => { const t = findTask(d, p.id); return t ? [200, taskOut(t)] : E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); });
  on('DELETE', '/v1/tasks/{id}', ({ d, device, p }) => { const i = d.tasks.findIndex(t => t.id === p.id); if (i < 0) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); d.tasks.splice(i, 1); notifier.cancel(device, p.id); return [204]; });
  on('GET', '/v1/tasks/{id}/events', ({ d, p }) => findTask(d, p.id) ? [200, { items: d.events.filter(e => e.taskId === p.id).map(e => ({ id: e.id, type: e.type, at: e.at, undone: !!e.undone })) }] : E(404, 'NOT_FOUND', 'ไม่พบงานนี้'));
  on('POST', '/v1/tasks/{id}/events', ({ d, device, p, body, req }) => svc.taskEvent(d, device, p.id, body, req.headers['idempotency-key']));

  // Sources
  on('GET', '/v1/sources', () => [200, { items: srcState }], { public: true });
  on('POST', '/v1/sources/{provider}/refresh', ({ p }) => {
    if (p.provider !== 'all' && !sources.providers.includes(p.provider)) return E(404, 'NOT_FOUND', 'แหล่งนี้ไม่รองรับการดึง');
    refresh(p.provider); return [202];
  }, { public: true });

  // Integrations (inbound)
  const validInput = i => i && i.externalId && i.title && i.category && i.mapGroup && i.money && ['official', 'listing', 'none'].includes(i.money.basis) && /^https?:\/\//.test(i.sourceUrl || '')
    && (!i.location || i.location.precision !== 'exact' || (typeof i.location.lat === 'number' && typeof i.location.lng === 'number'));
  on('POST', '/v1/integrations/opportunities/batch', ({ body }) => {
    if (!body || !body.provider || !Array.isArray(body.items)) return E(422, 'VALIDATION', 'ต้องมี provider และ items');
    if (body.items.length > 500) return E(422, 'VALIDATION', 'ส่งได้ครั้งละไม่เกิน 500 รายการ');
    const status = ['live', 'curated', 'open_data'].includes(body.dataStatus) ? body.dataStatus : 'curated';
    const rejected = [], mergedInto = []; let accepted = 0;
    body.items.forEach((it, index) => {
      if (!validInput(it)) return rejected.push({ index, reason: 'ข้อมูลไม่ครบ หรือไม่มีลิงก์ต้นทาง หรือ exact ไม่มีพิกัด' });
      const r = upsert(body.provider, status, body.attribution || body.provider, it);
      r.merged ? mergedInto.push({ index, existingId: r.id }) : accepted++;
    });
    let st = srcState.find(s => s.provider === body.provider);
    if (!st) srcState.push(st = { provider: body.provider, name: body.provider, kind: 'ส่งเข้าผ่าน Integrations', attribution: body.attribution || body.provider, direction: 'push', state: 'ok' });
    Object.assign(st, { state: 'ok', lastFetchedAt: nowIso(), itemCount: [...opps.values()].filter(o => o.provenance.provider === body.provider).length });
    return [200, { accepted, rejected, merged: mergedInto }];
  }, { integration: true });
  on('POST', '/v1/integrations/webhooks/{provider}', ({ p, body }) => {
    if (!srcState.some(s => s.provider === p.provider)) return E(404, 'NOT_FOUND', 'ไม่รู้จักผู้ให้ข้อมูลนี้');
    if (!body || !['opportunity.closed', 'opportunity.updated'].includes(body.event) || !body.externalId) return E(422, 'VALIDATION', 'event หรือ externalId ไม่ถูกต้อง');
    const id = p.provider + '_' + body.externalId;
    if (body.event === 'opportunity.closed') opps.delete(id);
    else { if (!validInput({ ...body.data, externalId: body.externalId })) return E(422, 'VALIDATION', 'data ไม่ครบ'); upsert(p.provider, 'curated', p.provider, { ...body.data, externalId: body.externalId }); }
    return [202];
  }, { integration: true });

  // Demo
  on('POST', '/v1/demo/personas/{id}', ({ device, p }) => {
    const per = Object.hasOwn(demoPersonas, p.id) && demoPersonas[p.id];
    if (!demoOn || !per) return E(404, 'NOT_FOUND', demoOn ? 'ไม่พบผู้ใช้ตัวอย่างนี้' : 'ปิดโหมดสาธิตอยู่');
    devices.delete(device); const d = dev(device);
    d.consents.push({ id: 'c' + d.seq++, noticeVersion: NOTICE.version, ageConfirmed: true, purposes: Object.fromEntries(purposeIds.map(id => [id, id !== 'gov'])), at: nowIso() });
    d.profile = { ...per.profile }; const g = geo.geocode(per.profile.district); if (g) { d.profile.lat = g.lat; d.profile.lng = g.lng; }
    d.facts = { ...per.facts };
    per.tasks.forEach(oid => svc.createTask(d, { opportunityId: oid }));
    return [200, { persona: p.id, label: per.label, profile: d.profile, facts: d.facts, taskCount: d.tasks.length, dataStatus: 'mock' }];
  });

  // ---- scheduled jobs (B3) ----
  async function checkLinks(ctx) {
    const f = ctx.fetch || opts.fetch || fetch;
    const xs = [...opps.values()].filter(o => o.provenance.provider !== 'mock' && /^https?:\/\//.test(o.provenance.sourceUrl || '')).slice(0, ctx.limit || 300);
    const count = { ok: 0, broken: 0, unknown: 0 };
    for (const o of xs) {
      let st = 'unknown';
      try {
        const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), 8000);
        const r = await f(o.provenance.sourceUrl, { method: 'HEAD', redirect: 'follow', signal: ctl.signal }); clearTimeout(t);
        st = r.status === 404 || r.status === 410 ? 'broken' : r.status < 400 ? 'ok' : 'unknown'; // 403/405 on HEAD is common, do not hide those
      } catch { /* network error or timeout: unknown, keep the item */ }
      o.provenance.linkStatus = st; o.provenance.linkCheckedAt = nowIso(); count[st]++;
    }
    persist();
    return 'checked ' + xs.length + ': ok ' + count.ok + ', broken ' + count.broken + ', unknown ' + count.unknown;
  }
  const reminderText = j => {
    const d = devices.get(j.deviceId), t = d && d.tasks.find(x => x.id === j.taskId);
    if (!t) return 'ถึงเวลาทำขั้นต่อไปแล้ว';
    if (t.status === 'snoozed') { t.status = 'active'; t.dueText = undefined; }
    return 'เตือน: ' + t.title + ' ขั้นต่อไป ' + t.steps[Math.min(t.doneCount, t.steps.length - 1)];
  };
  const jobs = createJobs([
    { name: 'sources_refresh', everyMinutes: refreshHours * 60, enabled: !!opts.live, run: async () => { await refresh('all'); return srcState.filter(s => s.direction === 'pull').map(s => s.provider + ' ' + s.state).join(', '); } },
    { name: 'link_check', everyMinutes: 24 * 60, run: checkLinks },
    { name: 'reminders', everyMinutes: 1, run: ctx => { const n = notifier.dispatch(ctx.now ?? Date.now(), reminderText); if (n) persist(); return 'sent ' + n; } },
    { name: 'retention', everyMinutes: 24 * 60, enabled: retentionDays > 0, run: ctx => {
      const days = ctx.days ?? retentionDays; if (!(days > 0)) return 'off (RETENTION_DAYS not set)';
      const mode = ctx.mode || retentionMode, now = ctx.now ?? Date.now(), cut = now - days * 864e5, out = [];
      for (const [id, d] of devices) if (new Date(d.lastSeenAt || 0).getTime() < cut) { out.push(packDevice(id, d)); devices.delete(id); notifier.cancel(id); }
      // Archive keeps profile + activity only; identity (ThaID) and runtime state are never archived.
      if (out.length && mode === 'archive') store.archive(out.map(r => archiveRecord(r, 'retention ' + days + ' days', new Date(now).toISOString())));
      if (out.length) persist(); return (mode === 'archive' ? 'archived ' : 'deleted ') + out.length + ' devices not seen for ' + days + ' days';
    } }
  ]);

  // ---- HTTP ----
  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, 'http://x'), requestId = crypto.randomUUID();
    const send = (status, body, headers = {}) => {
      if (body && typeof body === 'object' && 'code' in body && 'message' in body && !('requestId' in body)) body = { ...body, requestId };
      res.writeHead(status, { 'X-Request-Id': requestId, 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Expose-Headers': 'X-Request-Id, X-Total-Count, ETag', 'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS', ...(body !== undefined ? { 'Content-Type': 'application/json; charset=utf-8' } : {}), ...headers });
      res.end(body !== undefined ? JSON.stringify(body) : undefined);
    };
    if (req.method === 'OPTIONS') return send(204);
    if (req.method === 'GET' && /^\/docs\/?$/.test(u.pathname)) {
      const f = path.join(DIR, '..', 'docs', 'backend', 'index.html');
      if (!fs.existsSync(f)) return send(404, { code: 'NOT_FOUND', message: 'ยังไม่ได้สร้างเอกสาร รัน npm run docs', status: 404, retryable: false });
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); return res.end(fs.readFileSync(f));
    }
    let raw = ''; for await (const c of req) raw += c;
    let body; try { body = raw ? JSON.parse(raw) : undefined; } catch { return send(...E(400, 'VALIDATION', 'JSON ไม่ถูกต้อง')); }
    for (const r of R) {
      const m = r.method === req.method && u.pathname.match(r.re); if (!m) continue;
      if (r.integration && req.headers['x-api-key'] !== integrationKey) return send(...E(401, 'UNAUTHORIZED', 'ต้องมี X-Api-Key ที่ถูกต้อง'));
      const device = req.headers['x-device-id'];
      if (!r.public && !r.integration && (!device || device.length < 8)) return send(...E(400, 'MISSING_DEVICE', 'ต้องมี X-Device-Id'));
      try {
        const d = device ? dev(device) : null; if (d) d.lastSeenAt = nowIso();
        const [st, b, h] = await r.fn({ req, q: u.searchParams, p: m.groups || {}, body, device, d });
        if (req.method !== 'GET' && st < 400) persist();
        return send(st, b, h);
      }
      catch (e) { if (opts.debug) console.error(e); return send(...E(500, 'INTERNAL', 'ระบบขัดข้อง')); }
    }
    send(...E(404, 'NOT_FOUND', 'ไม่พบ endpoint นี้'));
  });
  server.ports = { ai, agent, notifier, refresh, jobs, store, persist };
  if (opts.jobs !== false) { jobs.start(); server.on('close', () => jobs.stop()); }
  return server;
}

module.exports = { createServer };
if (require.main === module) {
  const port = +(process.env.PORT || 8080);
  // `npm run mock` keeps data in contracts/.data/ (git-ignored) so a restart does not wipe the demo.
  const dataDir = path.join(DIR, '.data');
  const s = createServer({ live: process.env.LIVE === '1', debug: true,
    dataFile: process.env.DATA_FILE !== undefined ? process.env.DATA_FILE : path.join(dataDir, 'state.json'),
    aiLogFile: process.env.AI_LOG_FILE !== undefined ? process.env.AI_LOG_FILE : path.join(dataDir, 'ai-calls.jsonl') });
  s.listen(port, () => {
    // B2: phones on the same Wi-Fi can call the LAN address; for other networks use a tunnel (see docs/guide/run-demo-server.md).
    const lan = Object.values(require('os').networkInterfaces()).flat().filter(i => i && i.family === 'IPv4' && !i.internal).map(i => 'http://' + i.address + ':' + port);
    console.log('API on http://localhost:' + port + '  docs: /docs  AI: ' + s.ports.ai.provider + '  store: ' + s.ports.store.kind + '  commit: ' + COMMIT);
    console.log('Android emulator: http://10.0.2.2:' + port + (lan.length ? '  same Wi-Fi: ' + lan.join(', ') : ''));
  });
}
