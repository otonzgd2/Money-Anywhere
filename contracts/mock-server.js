// Mock server that implements every operation in openapi.yaml with in-memory state.
// For app development and contract tests only. Not the production backend (stack not chosen yet).
// Run: node mock-server.js   PORT=8080 by default. LIVE=1 pulls Greenhouse/Lever on start.
// AI: set AI_BASE_URL + AI_API_KEY (+ AI_MODEL) for an OpenAI-compatible provider; otherwise rules are used.
// Integrations: X-Api-Key must equal INTEGRATION_KEY (defaults to "dev-only-key" for local use).
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { URL } = require('url');
const { createAi } = require('./adapters/ai');
const sources = require('./adapters/sources');
const { createGeocoder } = require('./adapters/geocoder');
const { createNotifier } = require('./adapters/notifier');

const DIR = __dirname;
const readJson = f => JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8'));
const nowIso = () => new Date().toISOString();
const daysAgo = d => d ? Math.max(0, Math.round((Date.now() - new Date(d)) / 864e5)) : undefined;

function km(a, b) {
  const R = 6371, t = x => x * Math.PI / 180, dLat = t(b.lat - a.lat), dLng = t(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(t(a.lat)) * Math.cos(t(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function createServer(opts = {}) {
  const ref = readJson('fixtures/reference.json');
  const fx = readJson('fixtures/opportunities.json');
  const ai = opts.ai || createAi(opts.aiOptions || {});
  const geo = createGeocoder(ref.taxonomies.districts);
  const notifier = createNotifier();
  const integrationKey = opts.integrationKey || process.env.INTEGRATION_KEY || 'dev-only-key';
  const scam = text => ref.scamRules.filter(s => new RegExp(s.pattern).test(text)).map(s => s.reason);

  // ---- shared catalogue ----
  const opps = new Map(); // id -> Opportunity
  // Age is computed at read time so a long-running server never reports a stale age.
  const fresh = o => ({ ...o, provenance: { ...o.provenance, ageDays: daysAgo(o.provenance.updatedAt) } });
  function upsert(provider, dataStatus, attribution, input) {
    const id = provider + '_' + input.externalId;
    const reasons = scam(input.title + ' ' + (input.conditions || []).join(' ') + ' ' + (input.suspiciousText || ''));
    opps.set(id, {
      id, title: input.title, organization: input.organization, category: input.category, mapGroup: input.mapGroup,
      location: input.location || { precision: 'none' }, money: input.money, conditions: input.conditions || [],
      provenance: { provider, dataStatus, sourceUrl: input.sourceUrl, updatedAt: input.updatedAt, expiresAt: input.expiresAt, fetchedAt: nowIso(), ageDays: daysAgo(input.updatedAt), attribution },
      suspicious: reasons.length > 0, suspiciousReasons: reasons, checklistTemplateId: input.category
    });
    return id;
  }
  fx.items.forEach(r => upsert('mock', 'mock', 'DEMO / MOCK', {
    externalId: r.id.replace(/^mock_/, ''), title: r.title, organization: r.organization, category: r.category, mapGroup: r.mapGroup,
    location: r.dxKm === undefined ? { precision: 'none' } : { precision: 'exact', text: 'ที่อยู่ตัวอย่าง (สมมติ)', lat: +(fx.center.lat - r.dyKm * 0.009).toFixed(6), lng: +(fx.center.lng + r.dxKm * 0.00926).toFixed(6) },
    money: r.money, conditions: r.conditions, sourceUrl: 'https://example.org/demo/' + r.id, updatedAt: new Date(Date.now() - r.ageDays * 864e5).toISOString(), suspiciousText: r.suspiciousText
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
  const dev = id => { if (!devices.has(id)) devices.set(id, { profile: null, settings: { largeText: false, reminders: true }, consents: [], tasks: [], events: [], sessions: {}, idem: new Map(), seq: 1 }); return devices.get(id); };
  const taskOut = t => ({ id: t.id, opportunityId: t.opportunityId, title: t.title, steps: t.steps, doneCount: t.doneCount, status: t.status, reportedBy: 'user', dueText: t.dueText, blockReason: t.blockReason });
  const searchPoint = (d, q) => q.has('lat') && q.has('lng') ? { lat: +q.get('lat'), lng: +q.get('lng') }
    : d.profile && typeof d.profile.lat === 'number' ? { lat: d.profile.lat, lng: d.profile.lng } : { lat: fx.center.lat, lng: fx.center.lng };

  const E = (status, code, message, extra = {}) => [status, { code, message, status, retryable: status >= 500, ...extra }];
  const R = [];
  const on = (method, pattern, fn, o = {}) => R.push({ method, re: new RegExp('^' + pattern.replace(/\{(\w+)\}/g, '(?<$1>[^/]+)') + '$'), fn, ...o });

  // Config
  on('GET', '/v1/app-config', ({ req }) => {
    const cfg = readJson('app-config.sample.json'); const tag = '"' + cfg.configVersion + '"';
    return req.headers['if-none-match'] === tag ? [304] : [200, cfg, { ETag: tag, 'Cache-Control': 'no-cache' }];
  }, { public: true });
  on('GET', '/v1/taxonomies', () => [200, ref.taxonomies], { public: true });

  // Me
  on('DELETE', '/v1/me', ({ device }) => { devices.delete(device); notifier.cancel(device); return [204]; });
  on('GET', '/v1/me/profile', ({ d }) => d.profile ? [200, d.profile] : E(404, 'NOT_FOUND', 'ยังไม่มีโปรไฟล์'));
  on('PUT', '/v1/me/profile', ({ d, body }) => {
    if (!body || typeof body !== 'object' || Array.isArray(body)) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง');
    const allowed = ['displayName', 'district', 'lat', 'lng', 'skills', 'hoursPerWeek', 'incomeGoalPerMonth', 'goals', 'constraints'];
    const p = Object.fromEntries(Object.entries(body).filter(([k]) => allowed.includes(k)));
    if (p.district && typeof p.lat !== 'number') { const g = geo.geocode(p.district); if (g) { p.lat = g.lat; p.lng = g.lng; } }
    d.profile = p; return [200, p];
  });
  on('POST', '/v1/me/consents', ({ d, body }) => {
    if (!body || typeof body.version !== 'string' || typeof body.accepted !== 'boolean') return E(400, 'VALIDATION', 'ต้องมี version และ accepted');
    const c = { version: body.version, accepted: body.accepted, at: nowIso() }; d.consents.push(c); return [201, c];
  });
  on('GET', '/v1/me/settings', ({ d }) => [200, d.settings]);
  on('PATCH', '/v1/me/settings', ({ d, device, body }) => {
    d.settings = { ...d.settings, ...Object.fromEntries(Object.entries(body || {}).filter(([k, v]) => ['largeText', 'reminders'].includes(k) && typeof v === 'boolean')) };
    if (d.settings.reminders === false) notifier.cancel(device);
    return [200, d.settings];
  });
  on('GET', '/v1/me/export', ({ d }) => [200, { profile: d.profile || {}, settings: d.settings, tasks: d.tasks.map(taskOut), consents: d.consents,
    storedFields: ['profile.displayName', 'profile.district', 'profile.skills', 'profile.hoursPerWeek', 'profile.incomeGoalPerMonth', 'profile.goals', 'settings', 'tasks', 'consents'] }]);

  // Intake
  const turn = (sid, s) => {
    const Q = ref.intake;
    if (s.i >= Q.length) return { sessionId: sid, aiStatus: 'fallback_rules', done: true, question: 'สรุปข้อมูลแล้ว ถูกต้องไหมคะ', profileDraft: s.draft };
    return { sessionId: sid, aiStatus: 'fallback_rules', done: false, question: Q[s.i].question, quickReplies: Q[s.i].quickReplies, profileDraft: s.draft };
  };
  on('POST', '/v1/intake/sessions', ({ d }) => { const sid = 's' + d.seq++; d.sessions[sid] = { i: 0, draft: {} }; return [201, turn(sid, d.sessions[sid])]; });
  on('POST', '/v1/intake/sessions/{id}/messages', ({ d, p, body }) => {
    const s = d.sessions[p.id]; if (!s) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    if (!body || typeof body.text !== 'string' || !body.text.trim()) return E(422, 'VALIDATION', 'ต้องมีข้อความ');
    const Q = ref.intake; if (s.i >= Q.length) return [200, turn(p.id, s)];
    const k = Q[s.i].key, v = body.text.trim();
    s.draft[k] = k === 'skills' || k === 'goals' ? [v] : k === 'incomeGoalPerMonth' ? (+v.replace(/\D/g, '') || undefined) : v;
    if (k === 'district') { const g = geo.geocode(v); if (g) { s.draft.lat = g.lat; s.draft.lng = g.lng; } }
    s.i++; return [200, turn(p.id, s)];
  });

  // Opportunities
  function search(d, q) {
    const c = searchPoint(d, q), r = q.has('radiusKm') ? +q.get('radiusKm') : 5, group = q.get('group') || 'all', cat = q.get('category'), text = (q.get('q') || '').trim();
    const onlyMoney = q.get('onlyMoney') === 'true', showSus = q.get('showSuspicious') === 'true', sort = q.get('sort') || 'near';
    let xs = [...opps.values()].map(fresh).map(o => o.location.precision === 'exact' ? { ...o, location: { ...o.location, distanceKm: +km(c, o.location).toFixed(2) } } : o)
      .filter(o => group === 'all' || o.mapGroup === group).filter(o => !cat || o.category === cat)
      .filter(o => !text || (o.title + ' ' + (o.organization || '')).includes(text))
      .filter(o => !onlyMoney || o.money.basis !== 'none')
      .filter(o => o.location.precision !== 'exact' || o.location.distanceKm <= r)
      .filter(o => !o.provenance.expiresAt || new Date(o.provenance.expiresAt) > new Date());
    const hidden = showSus ? 0 : xs.filter(o => o.suspicious).length;
    if (!showSus) xs = xs.filter(o => !o.suspicious);
    const key = { near: o => o.location.distanceKm ?? 1e9, money: o => -(o.money.max ?? -1), fresh: o => o.provenance.ageDays ?? 1e9 }[sort];
    if (!key) return null;
    return { xs: xs.sort((a, b) => key(a) - key(b)), hidden };
  }
  on('GET', '/v1/opportunities', ({ d, q }) => {
    const res = search(d, q); if (!res) return E(400, 'VALIDATION', 'sort ไม่ถูกต้อง');
    const limit = Math.min(100, Math.max(1, +(q.get('limit') || 30)));
    const start = q.get('cursor') ? +Buffer.from(q.get('cursor'), 'base64url').toString() || 0 : 0;
    const page = res.xs.slice(start, start + limit);
    const warn = srcState.filter(s => s.state === 'failed').map(s => s.provider);
    return [200, { items: page, nextCursor: start + limit < res.xs.length ? Buffer.from(String(start + limit)).toString('base64url') : undefined, hiddenSuspicious: res.hidden, sourceWarnings: warn.length ? warn : undefined }, { 'X-Total-Count': String(res.xs.length) }];
  });
  on('GET', '/v1/opportunities/{id}', ({ p }) => opps.has(p.id) ? [200, fresh(opps.get(p.id))] : E(404, 'NOT_FOUND', 'ไม่พบรายการนี้'), { public: true });
  const reports = [];
  on('POST', '/v1/opportunities/{id}/reports', ({ device, p, body }) => {
    if (!opps.has(p.id)) return E(404, 'NOT_FOUND', 'ไม่พบรายการนี้');
    if (!body || !['suspicious', 'wrong_info', 'expired', 'other'].includes(body.reason)) return E(400, 'VALIDATION', 'reason ไม่ถูกต้อง');
    reports.push({ device, id: p.id, reason: body.reason, note: body.note, at: nowIso() }); return [202];
  });

  // AI
  on('POST', '/v1/ai/rankings', async ({ d, body }) => {
    const ids = body && Array.isArray(body.opportunityIds) ? body.opportunityIds : [];
    if (!ids.length) return E(400, 'VALIDATION', 'ต้องมี opportunityIds อย่างน้อย 1 รายการ');
    const candidates = [...new Set(ids)].slice(0, 50).map(id => opps.get(id)).filter(o => o && !o.suspicious);
    const out = await ai.rank(d.profile, candidates);
    return [200, { aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId, ranked: out.ranked }];
  });
  on('POST', '/v1/ai/explanations', async ({ d, body }) => {
    if (!body || !['task_step', 'opportunity'].includes(body.subjectType) || !body.subjectId) return E(400, 'VALIDATION', 'ต้องมี subjectType และ subjectId');
    let subject;
    if (body.subjectType === 'task_step') {
      const t = d.tasks.find(x => x.id === body.subjectId); if (!t) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้');
      subject = { type: 'task_step', title: t.title, step: t.steps[Math.min(t.doneCount, t.steps.length - 1)] };
    } else {
      const o = opps.get(body.subjectId); if (!o) return E(404, 'NOT_FOUND', 'ไม่พบรายการนี้');
      subject = { type: 'opportunity', opportunity: { title: o.title, conditions: o.conditions, category: o.category } };
    }
    const out = await ai.explain(subject);
    return [200, { aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId, text: out.text }];
  });

  // Planner
  on('GET', '/v1/plans/options', ({ q }) => {
    const want = (q.get('opportunityIds') || '').split(',').filter(Boolean);
    return [200, { items: ref.plans.filter(p => !want.length || want.includes(p.opportunityId)).map(p => p.grossPerMonth
      ? { ...p, netPerMonth: [p.grossPerMonth[0] - p.costPerMonth[1], p.grossPerMonth[1] - p.costPerMonth[0]] } : p) }];
  });

  // Tasks
  const findTask = (d, id) => d.tasks.find(t => t.id === id);
  on('GET', '/v1/tasks', ({ d, q }) => [200, { items: d.tasks.filter(t => !q.get('status') || t.status === q.get('status')).map(taskOut) }]);
  on('POST', '/v1/tasks', ({ d, body }) => {
    const o = body && opps.get(body.opportunityId); if (!o) return E(404, 'NOT_FOUND', 'ไม่พบโอกาสที่จะบันทึก');
    const ex = d.tasks.find(t => t.opportunityId === o.id); if (ex) return [201, taskOut(ex)];
    const steps = ref.checklists[o.checklistTemplateId] || ['ติดต่อผู้ประกาศ', 'ดำเนินการตามขั้นตอนที่ต้นทาง'];
    const t = { id: 't' + d.seq++, opportunityId: o.id, title: o.title, steps, doneCount: 0, status: 'active' };
    d.tasks.push(t); return [201, taskOut(t)];
  });
  on('GET', '/v1/tasks/{id}', ({ d, p }) => { const t = findTask(d, p.id); return t ? [200, taskOut(t)] : E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); });
  on('DELETE', '/v1/tasks/{id}', ({ d, device, p }) => {
    const i = d.tasks.findIndex(t => t.id === p.id); if (i < 0) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้');
    d.tasks.splice(i, 1); notifier.cancel(device, p.id); return [204];
  });
  on('GET', '/v1/tasks/{id}/events', ({ d, p }) => findTask(d, p.id) ? [200, { items: d.events.filter(e => e.taskId === p.id).map(e => ({ id: e.id, type: e.type, at: e.at, undone: !!e.undone })) }] : E(404, 'NOT_FOUND', 'ไม่พบงานนี้'));
  on('POST', '/v1/tasks/{id}/events', ({ d, device, p, body, req }) => {
    const t = findTask(d, p.id); if (!t) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้');
    const types = ['complete_step', 'undo', 'block', 'snooze', 'resume'];
    if (!body || !types.includes(body.type)) return E(422, 'VALIDATION', 'type ไม่ถูกต้อง');
    const key = req.headers['idempotency-key'];
    if (key && d.idem.has(key)) return d.idem.get(key);
    const before = { doneCount: t.doneCount, status: t.status, dueText: t.dueText, blockReason: t.blockReason };
    if (body.type === 'complete_step') {
      if (t.status === 'finished') return E(409, 'CONFLICT', 'งานนี้ครบทุกขั้นแล้ว');
      t.doneCount++; t.status = t.doneCount >= t.steps.length ? 'finished' : 'active'; t.blockReason = undefined;
    } else if (body.type === 'undo') {
      const last = [...d.events].reverse().find(e => e.taskId === t.id && !e.undone && e.type !== 'undo');
      if (!last) return E(409, 'CONFLICT', 'ไม่มีอะไรให้เลิกทำ');
      Object.assign(t, last.before); last.undone = true;
    } else if (body.type === 'block') {
      t.status = 'blocked'; t.blockReason = body.reason || 'other';
    } else if (body.type === 'snooze') {
      const until = body.until || 'tomorrow';
      if (until === 'never') { notifier.cancel(device, t.id); t.dueText = undefined; }
      else {
        const days = { tomorrow: 1, in_3_days: 3, next_week: 7 }[until]; if (!days) return E(422, 'VALIDATION', 'until ไม่ถูกต้อง');
        t.status = 'snoozed'; t.dueText = { tomorrow: 'เตือนพรุ่งนี้', in_3_days: 'เตือนอีก 3 วัน', next_week: 'เตือนสัปดาห์หน้า' }[until];
        if (d.settings.reminders) notifier.schedule(device, t.id, new Date(Date.now() + days * 864e5).toISOString());
      }
    } else if (body.type === 'resume') {
      t.status = t.doneCount >= t.steps.length ? 'finished' : 'active'; t.blockReason = undefined; t.dueText = undefined; notifier.cancel(device, t.id);
    }
    d.events.push({ id: 'ev' + d.seq++, taskId: t.id, type: body.type, before, at: nowIso() });
    const result = [201, taskOut(t)];
    if (key) d.idem.set(key, result);
    return result;
  });

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
    const rejected = []; let accepted = 0;
    body.items.forEach((it, index) => {
      if (!validInput(it)) return rejected.push({ index, reason: 'ข้อมูลไม่ครบ หรือไม่มีลิงก์ต้นทาง หรือ exact ไม่มีพิกัด' });
      upsert(body.provider, status, body.attribution || body.provider, it); accepted++;
    });
    let st = srcState.find(s => s.provider === body.provider);
    if (!st) srcState.push(st = { provider: body.provider, name: body.provider, kind: 'ส่งเข้าผ่าน Integrations', attribution: body.attribution || body.provider, direction: 'push', state: 'ok' });
    Object.assign(st, { state: 'ok', lastFetchedAt: nowIso(), itemCount: [...opps.values()].filter(o => o.provenance.provider === body.provider).length });
    return [200, { accepted, rejected }];
  }, { integration: true });
  on('POST', '/v1/integrations/webhooks/{provider}', ({ p, body }) => {
    if (!srcState.some(s => s.provider === p.provider)) return E(404, 'NOT_FOUND', 'ไม่รู้จักผู้ให้ข้อมูลนี้');
    if (!body || !['opportunity.closed', 'opportunity.updated'].includes(body.event) || !body.externalId) return E(422, 'VALIDATION', 'event หรือ externalId ไม่ถูกต้อง');
    const id = p.provider + '_' + body.externalId;
    if (body.event === 'opportunity.closed') opps.delete(id);
    else { if (!validInput({ ...body.data, externalId: body.externalId })) return E(422, 'VALIDATION', 'data ไม่ครบ'); upsert(p.provider, 'curated', p.provider, { ...body.data, externalId: body.externalId }); }
    return [202];
  }, { integration: true });

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
      try { const [st, b, h] = await r.fn({ req, q: u.searchParams, p: m.groups || {}, body, device, d: device ? dev(device) : null }); return send(st, b, h); }
      catch (e) { return send(...E(500, 'INTERNAL', 'ระบบขัดข้อง')); }
    }
    send(...E(404, 'NOT_FOUND', 'ไม่พบ endpoint นี้'));
  });
  server.ports = { ai, notifier, refresh };
  return server;
}

module.exports = { createServer };
if (require.main === module) {
  const port = +(process.env.PORT || 8080);
  const s = createServer({ live: process.env.LIVE === '1' });
  s.listen(port, () => console.log('Mock API on http://localhost:' + port + '  docs: /docs  AI: ' + s.ports.ai.provider));
}
