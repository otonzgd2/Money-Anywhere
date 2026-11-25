// Mock server that implements every operation in openapi.yaml with in-memory state.
// For app development and contract tests only. Not the production backend (stack not chosen yet).
// Run: node mock-server.js   (PORT=8080 by default; LIVE=1 also pulls Greenhouse/Lever on start)
// Docs: http://localhost:8080/docs   Config: http://localhost:8080/v1/app-config?appVersion=0.1.0
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const DIR = __dirname;
const readJson = f => JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8'));

function createState() {
  const fx = readJson('fixtures/opportunities.json');
  const ref = readJson('fixtures/reference.json');
  const now = Date.now();
  const toOpp = r => {
    const loc = r.dxKm === undefined ? { precision: 'none' }
      : { precision: 'exact', text: 'ที่อยู่ตัวอย่าง (สมมติ)', lat: +(fx.center.lat - r.dyKm * 0.009).toFixed(6), lng: +(fx.center.lng + r.dxKm * 0.00926).toFixed(6) };
    const updated = new Date(now - r.ageDays * 864e5).toISOString();
    const text = r.title + ' ' + (r.suspiciousText || '');
    const reasons = ref.scamRules.filter(s => new RegExp(s.pattern).test(text)).map(s => s.reason);
    return {
      id: r.id, title: r.title, organization: r.organization, category: r.category, mapGroup: r.mapGroup,
      location: loc, money: r.money, conditions: r.conditions,
      provenance: { provider: r.provider, dataStatus: r.dataStatus, sourceUrl: 'https://example.org/demo/' + r.id, updatedAt: updated, fetchedAt: new Date(now).toISOString(), ageDays: r.ageDays, attribution: 'DEMO / MOCK' },
      suspicious: reasons.length > 0, suspiciousReasons: reasons, checklistTemplateId: r.category
    };
  };
  return {
    fx, ref, center: fx.center,
    opportunities: fx.items.map(toOpp),
    profile: null, consent: null,
    settings: { largeText: false, reminders: true, searchPoint: { label: fx.center.label, lat: fx.center.lat, lng: fx.center.lng } },
    tasks: [], events: [], reports: [], chats: {}, seq: 1,
    sources: ref.sources.map(s => ({ provider: s.provider, name: s.name, kind: s.kind, attribution: s.attribution, state: s.url ? 'loading' : 'static', itemCount: 0 })),
    aiCalls: 0
  };
}

const km = (a, b) => {
  const R = 6371, t = x => x * Math.PI / 180;
  const dLat = t(b.lat - a.lat), dLng = t(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(t(a.lat)) * Math.cos(t(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};
const err = (code, message, retryable = false, extra = {}) => ({ code, message, retryable, ...extra });

// ---------- live adapters (Greenhouse, Lever): fetch -> common fields ----------
async function refreshLive(S, which) {
  const defs = S.ref.sources.filter(s => s.url && (which === 'all' || s.provider === which));
  await Promise.all(defs.map(async d => {
    const src = S.sources.find(x => x.provider === d.provider); src.state = 'loading';
    try {
      const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 10000);
      const res = await fetch(d.url, { signal: ctl.signal }); clearTimeout(t);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const j = await res.json();
      const rows = d.provider === 'greenhouse'
        ? (j.jobs || []).map(x => ({ pid: x.id, title: x.title, org: x.company_name, loc: x.location && x.location.name, url: x.absolute_url, updated: x.updated_at }))
        : (Array.isArray(j) ? j : []).map(x => ({ pid: x.id, title: x.text, org: 'Coda', loc: x.categories && x.categories.location, url: x.hostedUrl, updated: x.createdAt ? new Date(x.createdAt).toISOString() : undefined }));
      const bkk = rows.filter(r => /bangkok/i.test(r.loc || '') && !/malaysia/i.test(r.loc) && r.url && r.title);
      S.opportunities = S.opportunities.filter(o => o.provenance.provider !== d.provider);
      bkk.forEach(r => S.opportunities.push({
        id: d.provider + '_' + r.pid, title: r.title, organization: r.org, category: 'job_full', mapGroup: 'job',
        location: { precision: 'city', text: r.loc }, money: { basis: 'none', knownText: 'API ไม่ส่งค่าจ้างมา ดูที่ประกาศต้นทาง' },
        conditions: ['ต้นทางระบุที่ตั้งระดับเมือง จึงไม่ปักหมุด'],
        provenance: { provider: d.provider, dataStatus: 'live', sourceUrl: r.url, updatedAt: r.updated, fetchedAt: new Date().toISOString(), ageDays: r.updated ? Math.max(0, Math.round((Date.now() - new Date(r.updated)) / 864e5)) : undefined, attribution: d.attribution },
        suspicious: false, suspiciousReasons: [], checklistTemplateId: 'job_full'
      }));
      Object.assign(src, { state: 'ok', itemCount: bkk.length, lastFetchedAt: new Date().toISOString(), error: undefined });
    } catch (e) { Object.assign(src, { state: 'failed', error: e.name === 'AbortError' ? 'timeout' : e.message }); }
  }));
}

// ---------- matching: AI hook with deterministic fallback ----------
function rankDeterministic(S, ids) {
  const p = S.profile || {}, skills = (p.skills || []).join(' ');
  const scored = ids.map(id => S.opportunities.find(o => o.id === id)).filter(Boolean).filter(o => !o.suspicious).map(o => {
    let s = 0; const why = [];
    if (o.money.basis !== 'none') { s += 2; why.push('มีตัวเลขค่าตอบแทนจากต้นทาง'); }
    if (skills && skills.split(/\s+/).some(k => k && o.title.includes(k.slice(0, 3)))) { s += 3; why.push('ตรงกับทักษะของคุณ'); }
    if ((p.goals || []).some(g => (g.includes('เงิน') && o.mapGroup === 'money') || (g.includes('งาน') && o.mapGroup === 'job') || (g.includes('ทักษะ') && o.mapGroup === 'skill'))) { s += 2; why.push('ตรงกับเป้าหมาย'); }
    if (o.provenance.ageDays > 30) { s -= 1; why.push('ข้อมูลเก่า ควรตรวจที่ต้นทาง'); }
    const missing = [];
    if (!p.district) missing.push('พื้นที่');
    if (!p.hoursPerWeek) missing.push('เวลาว่าง');
    return { o, s, why, missing };
  }).sort((a, b) => b.s - a.s);
  return scored.map((x, i) => ({ opportunityId: x.o.id, fit: i < scored.length / 3 ? 'high' : i < scored.length * 2 / 3 ? 'good' : 'fair', reason: x.why.join(' · ') || 'อยู่ในหมวดที่คุณเลือก', missingInfo: x.missing }));
}

// ---------- tasks ----------
const taskOut = t => ({ id: t.id, opportunityId: t.opportunityId, title: t.title, steps: t.steps, doneCount: t.doneCount, status: t.status, reportedBy: 'user', dueText: t.dueText, lastEventId: t.lastEventId });
function addEvent(S, t, type, before) { const e = { id: 'ev' + S.seq++, taskId: t.id, type, before, at: new Date().toISOString() }; S.events.push(e); t.lastEventId = e.id; }

// ---------- router ----------
function routes(S) {
  const R = [];
  const on = (method, pattern, fn) => R.push({ method, re: new RegExp('^' + pattern.replace(/\{(\w+)\}/g, '(?<$1>[^/]+)') + '$'), fn });
  const needTask = id => S.tasks.find(t => t.id === id);

  on('GET', '/v1/app-config', ({ req }) => {
    const cfg = readJson('app-config.sample.json'); const tag = '"' + cfg.configVersion + '"';
    if (req.headers['if-none-match'] === tag) return [304];
    return [200, cfg, { ETag: tag }];
  });
  on('GET', '/v1/taxonomies', () => [200, S.ref.taxonomies]);
  on('GET', '/v1/me/profile', () => S.profile ? [200, S.profile] : [404, err('NOT_FOUND', 'ยังไม่มีโปรไฟล์')]);
  on('PUT', '/v1/me/profile', ({ body }) => {
    if (!body || typeof body !== 'object') return [422, err('VALIDATION', 'ข้อมูลไม่ถูกต้อง')];
    const allowed = ['displayName', 'district', 'lat', 'lng', 'skills', 'hoursPerWeek', 'incomeGoalPerMonth', 'goals', 'constraints'];
    S.profile = Object.fromEntries(Object.entries(body).filter(([k]) => allowed.includes(k)));
    return [200, S.profile];
  });
  on('DELETE', '/v1/me/profile', () => { const fresh = createState(); Object.keys(S).forEach(k => delete S[k]); Object.assign(S, fresh); return [204]; });
  on('POST', '/v1/me/consent', ({ body }) => { S.consent = { ...body, at: new Date().toISOString() }; return [204]; });
  on('GET', '/v1/me/settings', () => [200, S.settings]);
  on('PATCH', '/v1/me/settings', ({ body }) => { S.settings = { ...S.settings, ...body }; return [200, S.settings]; });
  on('GET', '/v1/me/data', () => [200, { profile: S.profile || {}, taskCount: S.tasks.length, storedFields: ['displayName', 'district', 'skills', 'hoursPerWeek', 'incomeGoalPerMonth', 'goals', 'tasks', 'settings'] }]);

  on('POST', '/v1/intake/chat', ({ body }) => {
    if (!body || !body.sessionId) return [422, err('VALIDATION', 'ต้องมี sessionId')];
    const c = S.chats[body.sessionId] || (S.chats[body.sessionId] = { i: -1, draft: {} });
    const Q = S.ref.intake;
    if (c.i >= 0 && body.message) {
      const k = Q[c.i].key, v = String(body.message);
      c.draft[k] = k === 'skills' || k === 'goals' ? [v] : k === 'incomeGoalPerMonth' ? (+v.replace(/\D/g, '') || undefined) : v;
    }
    c.i++;
    if (c.i >= Q.length) return [200, { aiStatus: 'fallback_rules', done: true, profileDraft: c.draft, question: 'สรุปข้อมูลแล้ว ถูกต้องไหมคะ' }];
    return [200, { aiStatus: 'fallback_rules', done: false, question: Q[c.i].question, quickReplies: Q[c.i].quickReplies, profileDraft: c.draft }];
  });

  on('GET', '/v1/opportunities', ({ q }) => {
    const center = q.has('lat') && q.has('lng') ? { lat: +q.get('lat'), lng: +q.get('lng') } : S.settings.searchPoint;
    const r = q.has('radiusKm') ? +q.get('radiusKm') : 5, group = q.get('group') || 'all', text = (q.get('q') || '').trim();
    const onlyMoney = q.get('onlyMoney') === 'true', showSus = q.get('showSuspicious') === 'true', sort = q.get('sort') || 'near';
    let xs = S.opportunities.map(o => ({ ...o, location: o.location.precision === 'exact' ? { ...o.location, distanceKm: +km(center, o.location).toFixed(2) } : o.location }))
      .filter(o => group === 'all' || o.mapGroup === group)
      .filter(o => !text || (o.title + ' ' + (o.organization || '')).includes(text))
      .filter(o => !onlyMoney || o.money.basis !== 'none')
      .filter(o => o.location.precision !== 'exact' || o.location.distanceKm <= r);
    const hidden = showSus ? 0 : xs.filter(o => o.suspicious).length;
    if (!showSus) xs = xs.filter(o => !o.suspicious);
    const key = { near: o => o.location.distanceKm ?? 1e9, money: o => -(o.money.max || -1), fresh: o => o.provenance.ageDays ?? 1e9, match: o => o.location.distanceKm ?? 1e9 }[sort] || (o => 0);
    xs.sort((a, b) => key(a) - key(b));
    const start = +(q.get('cursor') || 0), limit = Math.min(100, +(q.get('limit') || 30));
    const page = xs.slice(start, start + limit);
    return [200, { items: page, nextCursor: start + limit < xs.length ? String(start + limit) : undefined, hiddenSuspicious: hidden, sources: S.sources }];
  });
  on('GET', '/v1/opportunities/{id}', ({ p }) => { const o = S.opportunities.find(x => x.id === p.id); return o ? [200, o] : [404, err('NOT_FOUND', 'ไม่พบรายการนี้')]; });
  on('POST', '/v1/opportunities/{id}/reports', ({ p, body }) => { S.reports.push({ id: p.id, reason: body && body.reason, at: new Date().toISOString() }); return [204]; });

  on('POST', '/v1/matches', ({ body }) => {
    const ids = (body && body.opportunityIds || []).slice(0, 50);
    S.aiCalls++;
    // A real AI provider plugs in here. Its output must be filtered to `ids` and stripped of money figures.
    return [200, { aiStatus: 'fallback_rules', aiInvocationId: 'local-' + S.aiCalls, ranked: rankDeterministic(S, ids) }];
  });

  on('GET', '/v1/plans/options', ({ q }) => {
    const want = (q.get('opportunityIds') || '').split(',').filter(Boolean);
    return [200, S.ref.plans.filter(p => !want.length || want.includes(p.opportunityId)).map(p => p.grossPerMonth
      ? { ...p, netPerMonth: [p.grossPerMonth[0] - p.costPerMonth[1], p.grossPerMonth[1] - p.costPerMonth[0]] } : p)];
  });

  on('GET', '/v1/tasks', () => [200, S.tasks.map(taskOut)]);
  on('POST', '/v1/tasks', ({ body }) => {
    const o = body && S.opportunities.find(x => x.id === body.opportunityId);
    if (!o) return [404, err('NOT_FOUND', 'ไม่พบโอกาสที่จะบันทึก')];
    const ex = S.tasks.find(t => t.opportunityId === o.id); if (ex) return [201, taskOut(ex)];
    const steps = S.ref.checklists[o.checklistTemplateId] || ['ติดต่อผู้ประกาศ', 'ดำเนินการตามขั้นตอนที่ต้นทาง'];
    const t = { id: 't' + S.seq++, opportunityId: o.id, title: o.title, steps, doneCount: Math.min(body.startAtStep || 0, steps.length), status: 'active' };
    S.tasks.push(t); addEvent(S, t, 'create', null);
    return [201, taskOut(t)];
  });
  on('GET', '/v1/tasks/{id}', ({ p }) => { const t = needTask(p.id); return t ? [200, taskOut(t)] : [404, err('NOT_FOUND', 'ไม่พบงานนี้')]; });
  on('POST', '/v1/tasks/{id}/steps/complete', ({ p }) => {
    const t = needTask(p.id); if (!t) return [404, err('NOT_FOUND', 'ไม่พบงานนี้')];
    addEvent(S, t, 'complete', { doneCount: t.doneCount, status: t.status });
    t.doneCount = Math.min(t.steps.length, t.doneCount + 1); t.status = t.doneCount >= t.steps.length ? 'finished' : 'active';
    return [200, taskOut(t)];
  });
  on('POST', '/v1/tasks/{id}/undo', ({ p }) => {
    const t = needTask(p.id); if (!t) return [404, err('NOT_FOUND', 'ไม่พบงานนี้')];
    const e = [...S.events].reverse().find(x => x.taskId === t.id && x.before && !x.undone);
    if (e) { Object.assign(t, e.before); e.undone = true; }
    return [200, taskOut(t)];
  });
  on('POST', '/v1/tasks/{id}/block', ({ p, body }) => {
    const t = needTask(p.id); if (!t) return [404, err('NOT_FOUND', 'ไม่พบงานนี้')];
    addEvent(S, t, 'block', { status: t.status }); t.status = 'blocked'; t.blockReason = body && body.reason;
    return [200, taskOut(t)];
  });
  on('POST', '/v1/tasks/{id}/snooze', ({ p, body }) => {
    const t = needTask(p.id); if (!t) return [404, err('NOT_FOUND', 'ไม่พบงานนี้')];
    addEvent(S, t, 'snooze', { status: t.status, dueText: t.dueText });
    if (body && body.until !== 'never') { t.status = 'snoozed'; t.dueText = { tomorrow: 'เตือนพรุ่งนี้', in_3_days: 'เตือนอีก 3 วัน', next_week: 'เตือนสัปดาห์หน้า' }[body.until]; }
    return [204];
  });
  on('POST', '/v1/tasks/{id}/help', ({ p }) => {
    const t = needTask(p.id); if (!t) return [404, err('NOT_FOUND', 'ไม่พบงานนี้')];
    const step = t.steps[Math.min(t.doneCount, t.steps.length - 1)];
    return [200, { aiStatus: 'fallback_rules', text: 'ขั้นนี้: ' + step + ' ลองทำทีละข้อ ถ้ายังติด ให้ติดต่อผู้ประกาศหรือหน่วยงานโดยตรง แอปไม่ดำเนินการแทนคุณ' }];
  });

  on('GET', '/v1/sources', () => [200, S.sources]);
  on('POST', '/v1/sources/{provider}/refresh', ({ p }) => {
    if (p.provider !== 'all' && !S.sources.some(s => s.provider === p.provider)) return [404, err('NOT_FOUND', 'ไม่รู้จักแหล่งนี้')];
    refreshLive(S, p.provider); return [202];
  });
  return R;
}

function createServer(opts = {}) {
  const S = createState();
  if (opts.live) refreshLive(S, 'all'); else S.sources.forEach(s => { if (s.state === 'loading') s.state = 'static'; });
  const R = routes(S);
  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, 'http://x');
    const send = (status, body, headers = {}) => {
      res.writeHead(status, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS', ...(body !== undefined ? { 'Content-Type': 'application/json; charset=utf-8' } : {}), ...headers });
      res.end(body !== undefined ? JSON.stringify(body) : undefined);
    };
    if (req.method === 'OPTIONS') return send(204);
    if (req.method === 'GET' && (u.pathname === '/docs' || u.pathname === '/docs/')) {
      const f = path.join(DIR, '..', 'docs', 'backend', 'index.html');
      if (!fs.existsSync(f)) return send(404, err('NOT_FOUND', 'ยังไม่ได้สร้างเอกสาร รัน npm run docs'));
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); return res.end(fs.readFileSync(f));
    }
    let raw = ''; for await (const c of req) raw += c;
    let body; try { body = raw ? JSON.parse(raw) : undefined; } catch { return send(422, err('VALIDATION', 'JSON ไม่ถูกต้อง')); }
    for (const r of R) {
      const m = r.method === req.method && u.pathname.match(r.re);
      if (m) {
        try { const [st, b, h] = await r.fn({ req, q: u.searchParams, p: m.groups || {}, body, S }); return send(st, b, h); }
        catch (e) { return send(500, err('INTERNAL', 'ระบบขัดข้อง', true)); }
      }
    }
    send(404, err('NOT_FOUND', 'ไม่พบ endpoint นี้'));
  });
  server.state = S;
  return server;
}

module.exports = { createServer };
if (require.main === module) {
  const port = +(process.env.PORT || 8080);
  createServer({ live: process.env.LIVE === '1' }).listen(port, () => console.log('Mock API on http://localhost:' + port + '  docs: http://localhost:' + port + '/docs'));
}
