// End-to-end walk through the app's flows against the RUNNING server (same calls the Flutter app makes).
// Writes contracts/.data/e2e-out.txt. Run (server running): node tools/e2e-flows.js
const fs = require('fs');
const base = 'http://127.0.0.1:8080', dev = 'device-e2e-' + Date.now();
const out = [], ok = [], bad = [];
const log = s => out.push(s);
const check = (name, cond, detail = '') => { (cond ? ok : bad).push(name); log((cond ? 'PASS ' : 'FAIL ') + name + (detail ? '\n     ' + String(detail).replace(/\n/g, ' / ').slice(0, 400) : '')); };
async function api(method, path, body, extra = {}) {
  const t0 = Date.now();
  const r = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json', 'X-Device-Id': dev, ...extra }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text(); let data = {}; try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  return { status: r.status, data, ms: Date.now() - t0 };
}
(async () => {
  const h = await api('GET', '/v1/health');
  check('server is up and on the newest version', h.status === 200 && h.data.version === '0.10.0', 'version ' + h.data.version + ', AI ' + (h.data.ai && h.data.ai.agent));

  // S1 new person: quick check without consent
  let facts = {};
  let pv = await api('POST', '/v1/money/preview', { facts });
  check('quick check: first question asked without consent', pv.status === 200 && pv.data.nextQuestion && pv.data.stored === false, pv.data.nextQuestion && pv.data.nextQuestion.question);
  check('quick check: every question has a plain help text', !!(pv.data.nextQuestion && pv.data.nextQuestion.help), pv.data.nextQuestion && pv.data.nextQuestion.help);

  // S3 one-click AI: consent core+ai, guided chat
  const notice = await api('GET', '/v1/privacy/notice');
  await api('POST', '/v1/me/consents', { noticeVersion: notice.data.version, ageConfirmed: true, purposes: { core: true, ai: true } });
  const conv = await api('POST', '/v1/ai/conversations', { mode: 'guided' });
  const cid = conv.data.conversationId;
  check('AI chat greets and asks the first question with a skip option', conv.status === 201 && conv.data.quickReplies.includes('ไม่แน่ใจ ข้ามข้อนี้'), conv.data.greeting);
  const say = async (text) => { const r = await api('POST', '/v1/ai/conversations/' + cid + '/messages', { text }); log('     > ' + text + '  [' + (r.data.guard && r.data.guard.kind) + ' / ' + r.data.aiStatus + ' / ' + r.ms + 'ms]\n       ' + String(r.data.reply).replace(/\n/g, ' / ').slice(0, 300)); return r.data; };

  let r = await say('ไม่เข้าใจคำถาม');
  check('chat: "ไม่เข้าใจคำถาม" explains the question (not off-topic)', r.guard.kind === 'explain');
  r = await say('อายุ 35 ค่ะ');
  check('chat: typed age is understood', r.guard.kind === 'answer');
  r = await say('แม่ผมแก่แล้ว');
  check('chat: "แม่ผมแก่แล้ว" is not refused as off-topic', r.guard.kind !== 'off_topic' && r.guard.kind !== 'unclear');
  r = await say('ควรได้อะไรจากรัฐบ้าง');
  check('chat: "ควรได้อะไรจากรัฐบ้าง" answered from data, not a list of every program', r.aiStatus === 'guarded' && !/เบี้ยความพิการ.*เงินคืนภาษี/.test(r.reply));
  // answer the remaining questions the way a young parent would
  let guard = 0;
  while (r.step && guard++ < 12) {
    const f = r.step.fact;
    const a = { govPension: 'ไม่ได้รับ', work: 'ทำงานอิสระ', kidUnder6: 'ใช่', lowIncome: 'ไม่เกิน', hasUnpaid: 'ไม่มี', disabilityCard: 'ไม่มี', taxWithheld: 'ไม่เคย', ss33: 'ไม่ครบ', unpaidDays: 'ไม่มี', welfareCard: 'ไม่มี' }[f] || 'ไม่แน่ใจ ข้ามข้อนี้';
    const before = f;
    r = await say(a);
    if (before === 'kidUnder6') check('chat: after "has a child" the income question comes next', r.step && r.step.fact === 'lowIncome', r.step && r.step.question);
  }
  const mo = await api('GET', '/v1/money');
  const child = mo.data.items.find(i => i.id === 'child_support');
  check('money: child support 600 is "likely" after the chat answers', child && child.status === 'likely' && child.amount.value === 600, child && child.status);
  const owed = mo.data.items.find(i => i.id === 'unpaid_wages');
  check('money: "no unpaid wages" closes that item without asking a number', owed && owed.status === 'unlikely', owed && owed.status);

  // Goal in chat (the Demo headline)
  r = await say('อยากได้เดือนละ 12,000 บาท');
  check('chat: "อยากได้เดือนละ 12,000" returns an income plan', /เป้า 12,000/.test(r.reply) && r.toolCalls.some(t => t.tool === 'plan_income_goal'));

  // S10 profile with skills, S11 income plan
  const pr = await api('PUT', '/v1/me/profile', { skills: ['ทำอาหาร', 'ขับรถยนต์'], hoursPerWeek: '20-40', incomeGoalPerMonth: 12000, district: 'บางกะปิ' });
  check('profile: skills, free time and goal saved', pr.status === 200 && pr.data.lat !== undefined);
  const gp = await api('GET', '/v1/plans/goal');
  const g = gp.data;
  log('     plan: ' + (g.parts || []).map(p => p.title + ' ' + p.net.join('-') + ' (' + p.numberSource + ')').join(' + ') + ' = ' + (g.total || []).join('-') + ' reach=' + g.reach + ' gap=' + g.gap);
  check('income plan: uses the profile goal, includes the child benefit and a skill-matched option', gp.status === 200 && g.target === 12000 && g.parts.some(p => p.id === 'child_support') && g.parts.some(p => p.matched && p.matched.length));
  check('income plan: total = sum of parts, gap = goal - low end', g.total[0] === g.parts.reduce((s, p) => s + p.net[0], 0) && g.gap === Math.max(0, 12000 - g.total[0]));

  // S6 opportunities: official links, skill ranking, map pins
  const jobs = await api('GET', '/v1/opportunities?group=job&radiusKm=50&limit=100');
  const official = jobs.data.items.filter(o => o.provenance.provider === 'official');
  const live = jobs.data.items.filter(o => o.provenance.dataStatus === 'live');
  check('opportunities: Department of Employment links are listed with real URLs', official.length >= 2 && official.every(o => /doe\.go\.th/.test(o.provenance.sourceUrl)), official.map(o => o.provenance.sourceUrl).join(' '));
  check('opportunities: real job posts pulled from Agoda (LIVE=1)', live.length > 0, 'live items: ' + live.length);
  const skill = await api('GET', '/v1/opportunities?group=skill&radiusKm=50');
  check('opportunities: free vocational training (DSD) is listed', skill.data.items.some(o => /dsd\.go\.th/.test(o.provenance.sourceUrl)));
  const pins = jobs.data.items.filter(o => o.location.precision === 'exact');
  check('map: some items have exact coordinates for pins', pins.length > 0, 'pins: ' + pins.length);
  const rk = await api('POST', '/v1/ai/rankings', { opportunityIds: jobs.data.items.slice(0, 20).map(o => o.id) });
  check('opportunities: "match my skills" ranking returns fit + reason', rk.status === 200 && rk.data.ranked.length > 0 && rk.data.ranked[0].reason, rk.data.aiStatus + ' ' + (rk.data.ranked[0] && rk.data.ranked[0].reason));

  // S5 route + S8 plan
  const route = await api('GET', '/v1/money/child_support');
  check('route: documents, channels and dated sources', route.data.documents.length && route.data.channels.length && route.data.sources.every(s => s.checkedAt));
  const t = await api('POST', '/v1/tasks', { moneyId: 'child_support' });
  check('plan: saved as steps', t.status === 201 && t.data.steps.length >= 3);
  const k = () => ({ 'Idempotency-Key': 'k' + Math.random() });
  const e1 = await api('POST', '/v1/tasks/' + t.data.id + '/events', { type: 'complete_step' }, k());
  const e2 = await api('POST', '/v1/tasks/' + t.data.id + '/events', { type: 'undo' }, k());
  const e3 = await api('POST', '/v1/tasks/' + t.data.id + '/events', { type: 'snooze', until: 'tomorrow' }, k());
  const e4 = await api('POST', '/v1/tasks/' + t.data.id + '/events', { type: 'resume' }, k());
  check('plan: step done, undo, snooze, resume all work', e1.data.doneCount === 1 && e2.data.doneCount === 0 && e3.data.status === 'snoozed' && e4.data.status === 'active');

  // New conversation does not re-ask
  const conv2 = await api('POST', '/v1/ai/conversations', { mode: 'guided' });
  check('chat: a new conversation does not ask what was already answered', !conv2.data.step || !['ageBand', 'kidUnder6', 'lowIncome'].includes(conv2.data.step.fact), conv2.data.step && conv2.data.step.question);

  // ThaID connect with bypass (same calls as the app)
  const gl0 = await api('GET', '/v1/me/gov-link');
  check('ThaID: mode is on and starts not connected', gl0.status === 200 && gl0.data.status === 'not_connected', JSON.stringify(gl0.data));
  await api('POST', '/v1/me/consents', { noticeVersion: notice.data.version, ageConfirmed: true, purposes: { core: true, ai: true, gov: true } });
  const gs0 = await api('POST', '/v1/me/gov-link');
  const gc0 = await api('POST', '/v1/me/gov-link/callback', { state: gs0.data.state, code: 'demo-bypass' });
  const gmo = await api('GET', '/v1/money');
  const ver = gmo.data.items.filter(i => i.status === 'verified');
  check('ThaID bypass: connected, agency records show as verified + mock for this person', gc0.data.status === 'connected' && ver.length > 0 && ver.every(i => i.dataStatus === 'mock') && !ver.some(i => i.id === 'old_age'), ver.map(i => i.title + ' ' + i.amount.value).join(', '));
  const srcs = await api('GET', '/v1/sources');
  check('sources: mock adapters for government and private APIs are listed with item counts', ['mock_doe', 'mock_jobboard', 'mock_dsd', 'thaid_mock'].every(p => srcs.data.items.some(s => s.provider === p)), srcs.data.items.map(s => s.provider + ':' + (s.itemCount || 0)).join(' '));

  // Delete
  const del = await api('DELETE', '/v1/me');
  const after = await api('GET', '/v1/me/facts');
  check('delete all: data is gone', del.status === 204 && Object.keys(after.data).length === 0);

  log('\n' + ok.length + ' passed, ' + bad.length + ' failed');
})().catch(e => log('ERROR ' + e.message)).finally(() => fs.mkdirSync(__dirname + '/../contracts/.data', { recursive: true }); fs.writeFileSync(__dirname + '/../contracts/.data/e2e-out.txt', out.join('\n')));
