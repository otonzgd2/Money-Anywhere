// Backend evidence for the MAN scenarios. UI steps are recorded separately in the handoff.
// Run: node --test --test-reporter=spec contracts/test-thang-rot-manual.js
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { test } = require('node:test');
const { createServer } = require('./mock-server');
const { createAi } = require('./adapters/ai');
const { createAgent } = require('./adapters/agent');
const { sourceRecords } = require('./fixtures/gov-prefill-demo.json');
const { cachedTangRatCard, lastValidInstant, firstExpiredInstant, startTangRatError } = require('./fixtures/man28-refresh');

const referenceTime = Date.parse('2026-11-29T17:15:00.000Z');
const rulesAi = createAi({ baseUrl: '', apiKey: '' });
const rulesAgent = createAgent({ baseUrl: '', apiKey: '' });
const oldAge = 'เช็กสิทธิเบี้ยผู้สูงอายุ';
const clientPath = '/v1/ai/conversations';

async function setup(t, options = {}) {
  const server = createServer({
    appMode: 'demo', demo: true, govConnected: true, jobs: false, retentionDays: 0,
    ai: rulesAi, agent: rulesAgent, aiLogFile: '', aiDailyLimit: 0, clock: () => referenceTime,
    fetch: async () => { throw new Error('No external service in the MAN fixtures'); },
    ...options
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  let device = 0;
  return function newPerson() {
    const deviceId = 'manual-person-number-' + ++device;
    const request = async (method, path, body, expected = 200) => {
      const response = await fetch('http://127.0.0.1:' + server.address().port + path, {
        method, headers: { 'Content-Type': 'application/json', 'X-Device-Id': deviceId },
        body: body === undefined ? undefined : JSON.stringify(body)
      });
      const result = response.status === 204 ? null : await response.json();
      assert.equal(response.status, expected, method + ' ' + path + ' ' + JSON.stringify(result));
      return result;
    };
    return {
      request,
      async consent(ai = true, gov = false) {
        const { version } = await request('GET', '/v1/privacy/notice');
        return request('POST', '/v1/me/consents', { noticeVersion: version, ageConfirmed: true, purposes: { core: true, ai, gov } }, 201);
      },
      load: sources => request('POST', '/v1/demo/personas/gov-prefill' + (sources === undefined ? '' : '?sources=' + sources)),
      facts: () => request('GET', '/v1/me/facts'),
      update: facts => request('PATCH', '/v1/me/facts', facts),
      profile: () => request('GET', '/v1/me/profile'),
      refreshDemoTangRat: () => server.ports.refreshDemoTangRat(deviceId),
      put: fields => request('PUT', '/v1/me/profile', fields),
      async chat() {
        const start = await request('POST', clientPath, { mode: 'guided' }, 201);
        const path = clientPath + '/' + start.conversationId;
        return {
          start,
          send: (text, stepId, status) => request('POST', path + '/messages', { text, stepId }, status),
          confirm: id => request('POST', path + '/actions/' + id, { decision: 'confirm' })
        };
      }
    };
  };
}

const mockReply = content => Response.json({ choices: [{ message: { content } }] });
function model(fetch, timeoutMs) {
  return createAgent({ baseUrl: 'https://model.invalid/v1', apiKey: 'test-only', apiStyle: 'chat-completions', fetch, timeoutMs });
}

test('MAN-01 all four sources: nationality first, no model call', async t => {
  let calls = 0;
  const create = await setup(t, { agent: model(async () => { calls++; return mockReply('unexpected'); }) });
  const user = create();
  await user.load();
  const { step } = await (await user.chat()).send(oldAge);
  assert.equal(step.fact, 'nationality');
  assert.equal(calls, 0);
});

test('MAN-02 ThaID and SSO: ask only the missing wage', async t => {
  const user = (await setup(t))();
  await user.load('thaid,socialSecurity');
  await user.update({ wage: null });
  assert.equal((await (await user.chat()).send('เช็กเงินว่างงาน')).step.fact, 'wage');
});

test('MAN-03 manual age is used, and an empty profile can answer it', async t => {
  const create = await setup(t);
  const empty = create(), filled = create();
  await empty.consent(); await filled.consent();
  await filled.update({ ageBand: '70-79' });
  const a = await empty.chat(), b = await filled.chat();
  assert.equal((await a.send(oldAge)).step.fact, 'ageBand');
  assert.equal((await a.send('อายุ 72')).step.fact, 'nationality');
  assert.equal((await b.send(oldAge)).step.fact, 'nationality');
});

test('MAN-04 conflict asks for confirmation; skip contributes no projected amount', async t => {
  const user = (await setup(t))();
  await user.load('tangRat');
  await user.update({ disabilityCard: false });
  const chat = await user.chat(), check = await chat.send('เช็กเบี้ยความพิการ');
  assert.equal(check.step.fact, 'disabilityCard');
  assert.match(check.reply, /ไม่ตรงกัน/);
  assert.match((await chat.send('ไม่แน่ใจ ข้ามข้อนี้', check.step.id)).reply, /ข้อมูลไม่พอ/);
  const money = await user.request('GET', '/v1/money');
  assert.equal(money.items.find(item => item.id === 'disability').status, 'need');
  assert.equal(money.summary.monthly, 0);
  const next = await user.chat();
  const confirmed = await next.send('เช็กเบี้ยความพิการ');
  await next.send('ไม่มี', confirmed.step.id);
  assert.equal((await user.facts()).disabilityCard, false);
  assert.equal((await user.profile()).factProvenance.disabilityCard.confirmed, true);
});

test('MAN-05 retirement checks the 55th birthday in Bangkok', async t => {
  let now = referenceTime - 60 * 60 * 1000;
  const sso = { ...sourceRecords.socialSecurity, coverageStatus: 'ended', lifetimePaidMonths33And39: 42 };
  const create = await setup(t, { clock: () => now, demoSourceRecords: { socialSecurity: sso, thaid: { ...sourceRecords.thaid, birthdate: '1971-11-30', ageBand: 'ต่ำกว่า 60' } } });
  const person = create();
  await person.load('thaid,socialSecurity');
  assert.equal((await person.facts()).ageAtLeast55, false);
  now = referenceTime;
  assert.equal((await person.facts()).ageAtLeast55, true);
  assert.match((await (await person.chat()).send('เช็กชราภาพ')).reply, /ชราภาพ/);
  const bands = await setup(t, { demoSourceRecords: { socialSecurity: sso, thaid: { ...sourceRecords.thaid, ageBand: 'ต่ำกว่า 60', ageBandOnly: true } } });
  const bandOnly = bands();
  await bandOnly.load('thaid,socialSecurity');
  assert.equal((await (await bandOnly.chat()).send('เช็กชราภาพ')).step.fact, 'ageAtLeast55');
});

test('MAN-06 registered district and job district have separate values', async t => {
  const create = await setup(t, { demoSourceRecords: { thaid: { ...sourceRecords.thaid, registryDistrict: 'ดินแดง' } } });
  const user = create();
  await user.load('thaid');
  await user.put({ district: 'บางกะปิ' });
  await user.update({ oldAgeGets: true });
  const profile = await user.profile();
  assert.equal(profile.district, 'บางกะปิ');
  assert.equal(profile.factProvenance.registryDistrict.value, 'ดินแดง');
  assert.match((await (await user.chat()).send('เบี้ยผู้สูงอายุงวดนี้ไม่เข้า')).reply, /ดินแดง/);
});

test('MAN-07 an existing payment is tracked and excluded from new income', async t => {
  const user = (await setup(t))();
  await user.consent();
  await user.update({ oldAgeGets: true, ageBand: '60-69' });
  const turn = await (await user.chat()).send('งวดนี้เบี้ยไม่เข้า');
  assert.equal(turn.step, undefined);
  assert.match(turn.reply, /ติดตามการจ่าย/);
  assert.ok(!(await user.request('GET', '/v1/plans/goal?target=5000')).parts.some(part => part.id === 'old_age'));
});

test('MAN-08 ask about the welfare card only for the supplement', async t => {
  const user = (await setup(t))();
  await user.load('tangRat');
  await user.update({ welfareCard: null });
  const chat = await user.chat();
  assert.match((await chat.send('เช็กเบี้ยความพิการส่วนพื้นฐาน')).reply, /800/);
  assert.equal((await chat.send('เช็กเงินเพิ่มเบี้ยความพิการ')).step.fact, 'welfareCard');
});

test('MAN-09 unemployment contributions do not fill retirement facts', async t => {
  const user = (await setup(t))();
  await user.load('thaid,socialSecurity');
  const chat = await user.chat();
  assert.equal((await chat.send('เช็กเงินว่างงาน')).step, undefined);
  const ended = await chat.send('เช็กชราภาพ');
  assert.equal(ended.step.fact, 'coverageEnded');
  assert.equal((await chat.send('สิ้นสุดแล้ว', ended.step.id)).step.fact, 'lifetimePaidMonths33And39');
  assert.equal((await user.facts()).ss33, true);
});

test('MAN-10 tax history stays dated and does not answer a different year', async t => {
  const create = await setup(t, { demoSourceRecords: { dMyTax: { ...sourceRecords.dMyTax, taxYear: 2025 } } });
  const user = create(); await user.load('dMyTax');
  const chat = await user.chat();
  assert.equal((await chat.send('เช็กเงินคืนภาษี ปี 2569')).step.fact, 'taxWithheld');
  assert.equal((await user.profile()).factProvenance.taxWithheld.taxYear, 2025);
  assert.equal((await chat.send('เช็กเงินคืนภาษี ปี 2568')).step, undefined);
});

test('MAN-11 rejecting a delayed callback leaves the profile disconnected', async t => {
  const user = (await setup(t))(); await user.consent(true, true);
  const { state } = await user.request('POST', '/v1/me/gov-link', undefined, 201);
  await user.request('DELETE', '/v1/me/gov-link', undefined, 204);
  await user.request('POST', '/v1/me/gov-link/callback', { state, code: 'synthetic' }, 422);
  assert.equal((await user.request('GET', '/v1/me/gov-link')).status, 'not_connected');
  assert.equal((await (await user.chat()).send(oldAge)).step.fact, 'ageBand');
  const fresh = await user.request('POST', '/v1/me/gov-link', undefined, 201);
  await user.request('POST', '/v1/me/gov-link/callback', { state: fresh.state, code: 'synthetic' });
  const overview = await user.request('GET', '/v1/money');
  assert.equal(overview.items.find(item => item.id === 'old_age').nextQuestion.fact, 'nationality');
  assert.equal(overview.items.find(item => item.id === 'tax_refund').status, 'need');
  assert.equal(overview.summary.once, 0);
});

test('MAN-12 demo and personal profile are isolated', async t => {
  const create = await setup(t), real = create(), demo = create();
  await real.consent(); await demo.load();
  assert.equal((await demo.facts()).ss33, true);
  assert.deepEqual(await real.facts(), {});
  assert.equal((await (await real.chat()).send(oldAge)).step.fact, 'ageBand');
});

test('MAN-13 an income request cannot answer the wage question', async t => {
  const user = (await setup(t))(); await user.load('socialSecurity');
  await user.update({ wage: null });
  const chat = await user.chat();
  assert.equal((await chat.send('เช็กเงินว่างงาน')).step.fact, 'wage');
  assert.equal((await chat.send('อยากได้ตัง 5000 หาให้หน่อยดิ๊')).step.fact, 'goalPeriod');
  assert.equal((await user.facts()).wage, undefined);
});

test('MAN-14 a displayed step remains bound to its original question', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat(), old = await chat.send(oldAge);
  await user.update({ ageBand: '70-79' });
  const current = await chat.send('60-69', old.step.id);
  assert.equal(current.step.fact, 'nationality');
  assert.deepEqual(await user.facts(), { ageBand: '70-79' });
});

test('MAN-15 end of month and past date use Bangkok time', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat();
  const result = await chat.send('หาเงินห้าพันจ่ายค่าเช่าสิ้นเดือน');
  assert.match(result.reply, /เงินก้อน 5,000.*30 พฤศจิกายน 2569/);
  const past = await chat.send('เงินก้อน 5000 จ่ายค่าเช่าภายใน 2026-11-29');
  assert.equal(past.step.fact, 'goalDeadline', past.reply);
});

test('MAN-16 no amount is needed to view options using profile skills and hours', async t => {
  const user = (await setup(t))(); await user.consent(); await user.put({ skills: ['ทำอาหาร'], hoursPerWeek: '10-20' });
  const chat = await user.chat();
  const amount = await chat.send('วางแผนหาเงินเพิ่ม');
  const expense = await chat.send('ยังไม่แน่ใจ', amount.step.id);
  assert.equal(expense.step.fact, 'goalExpense');
  const ideas = await chat.send('ดูทางเลือก', expense.step.id);
  assert.match(ideas.reply, /ทำอาหาร.*10-20/);
});

test('MAN-17 withdrawal blocks chat and keeps the rule-only endpoints', async t => {
  let calls = 0;
  const create = await setup(t, { agent: model(async () => { calls++; return mockReply('unexpected'); }) });
  const user = create(); await user.consent();
  const chat = await user.chat();
  await user.consent(false);
  await chat.send('หางาน', undefined, 403);
  assert.equal((await user.request('POST', '/v1/money/preview', { facts: {} })).stored, false);
  assert.equal((await user.request('GET', '/v1/plans/goal?target=5000')).target, 5000);
  assert.equal(calls, 0);
});

test('MAN-18 mixed scope and deposit warnings retain the work request', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat();
  const mixed = await chat.send('แต่งกลอน แล้วช่วยหางานจากบ้านที');
  assert.match(mixed.reply, /ทำงานจากบ้าน/);
  const scam = await chat.send('งานพาร์ตไทม์นี้ให้โอนมัดจำ ช่วยหางานอื่นได้ไหม');
  assert.match(scam.reply, /ระวัง.*ตรวจชื่อบริษัท.*ดูงานอื่น/);
});

test('MAN-19 a missing criterion stays in rules and wrong model values cannot be approved', async t => {
  let calls = 0;
  const create = await setup(t, { agent: model(async () => {
    if (++calls === 1) return Response.json({ choices: [{ message: { tool_calls: [
      { id: 'test', function: { name: 'update_facts', arguments: '{"facts":{"wage":"5000"}}' } }
    ] } }] });
    return mockReply('คุณควรได้รับเงิน 9,999 บาทแน่นอน');
  }) });
  const user = create(); await user.consent();
  assert.equal((await (await user.chat()).send(oldAge)).step.fact, 'ageBand');
  assert.equal(calls, 0);
  const turn = await (await user.chat()).send('ช่วยอธิบายผลเช็กเงินของฉัน');
  assert.equal(calls, 2);
  assert.doesNotMatch(turn.reply, /9,999|แน่นอน/);
  assert.match(turn.reply, /ต้องตอบคำถาม/);
  assert.deepEqual(turn.pendingActions, []);
  assert.deepEqual(await user.facts(), {});
});

test('MAN-20 timeout, malformed reply and quota preserve rules and saved state', async t => {
  let calls = 0;
  const create = await setup(t, { aiDailyLimit: 1, agent: model(async (_url, { signal }) => {
    calls++;
    await new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
  }, 25) });
  const user = create(); await user.consent(); await user.put({ incomeGoalPerMonth: 3000 });
  const chat = await user.chat();
  assert.equal((await chat.send('ช่วยดูเงินของฉันหน่อย')).aiStatus, 'fallback_rules');
  assert.equal((await chat.send('ช่วยดูเงินของฉันหน่อย')).aiStatus, 'fallback_rules');
  assert.equal(calls, 1);
  assert.equal((await chat.send(oldAge)).step.fact, 'ageBand');
  assert.equal((await user.profile()).incomeGoalPerMonth, 3000);
  const malformed = (await setup(t, { agent: model(async () => Response.json({ choices: [] })) }))();
  await malformed.consent();
  assert.equal((await (await malformed.chat()).send('ช่วยดูเงินของฉันหน่อย')).aiStatus, 'fallback_rules');
});

test('MAN-21 profile payload names the source, date and known negative', async t => {
  const user = (await setup(t))(); await user.load('tangRat');
  await user.update({ nationality: false });
  const profile = await user.profile();
  const { disabilityCard, nationality, ss33 } = profile.factProvenance;
  assert.equal(profile.dataStatus, 'mock');
  assert.equal(disabilityCard.source, 'tangRat');
  assert.equal(disabilityCard.checkedAt, '2026-11-27');
  assert.equal(nationality.value, false);
  assert.equal(nationality.source, 'user');
  assert.ok(nationality.checkedAt);
  assert.equal(ss33, undefined);
});

test('MAN-22 goal confirmation is idempotent and leaving a proposal does not save it', async t => {
  const user = (await setup(t))(); await user.consent(); await user.put({ incomeGoalPerMonth: 3000 });
  const chat = await user.chat();
  const proposal = await chat.send('อยากได้เงินเดือนละ 5,000 บาท');
  assert.equal((await user.profile()).incomeGoalPerMonth, 3000);
  const action = proposal.pendingActions.find(item => item.tool === 'save_income_goal');
  assert.ok(action);
  const results = await Promise.all([chat.confirm(action.id), chat.confirm(action.id)]);
  assert.deepEqual(results[0], results[1]);
  assert.equal((await user.profile()).incomeGoalPerMonth, 5000);
});

test('MAN-23 an explicit request for a relative does not write facts', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat(); await chat.send(oldAge);
  assert.match((await chat.send('ช่วยเช็กสิทธิให้แม่')).reply, /เจ้าของโปรไฟล์/);
  assert.deepEqual(await user.facts(), {});
});

test('MAN-24 another account and invalid token cannot fill missing facts', async t => {
  const create = await setup(t, { demoSourceRecords: {
    tangRat: { ...sourceRecords.tangRat, owner: 'someone-else' },
    dMyTax: { ...sourceRecords.dMyTax, tokenStatus: 'invalid' }
  } });
  const user = create(); await user.load('tangRat,dMyTax');
  const chat = await user.chat();
  assert.equal((await chat.send('เช็กเบี้ยความพิการ')).step.fact, 'disabilityCard');
  await user.update({ taxWithheld: false });
  assert.equal((await user.facts()).taxWithheld, false);
  assert.equal((await user.profile()).factProvenance.taxWithheld.source, 'user');
});

test('MAN-25 text-only and button clients both reach the next question', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat(), old = await chat.send(oldAge);
  assert.equal((await chat.send('ยังไม่ได้ค่ะ')).step.id, old.step.id);
  const next = await chat.send('อายุ 65 ปี');
  assert.equal(next.step.fact, 'nationality');
  assert.equal((await chat.send('มีสัญชาติไทย', next.step.id)).step.fact, 'registryDistrict');
  await chat.send('อยากได้เงินเดือนละ 5,000 บาท');
  const clarify = await chat.send('hello');
  assert.equal(clarify.step.fact, 'intent');
  const selected = await chat.send('เช็กสิทธิรับเงิน', clarify.step.id);
  assert.equal(selected.step.fact, 'benefitTopic');
});

test('MAN-26 retry of the displayed answer leaves the next question in place', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat(), old = await chat.send(oldAge);
  const first = await chat.send('60-69', old.step.id);
  const replay = await chat.send('60-69', old.step.id);
  assert.equal(replay.step.id, first.step.id);
  assert.deepEqual(await user.facts(), { ageBand: '60-69' });
});

test('MAN-27 an older exit history cannot answer about a new exit', async t => {
  const user = (await setup(t))(); await user.load('socialSecurity');
  const chat = await user.chat();
  assert.equal((await chat.send('เช็กเงินว่างงานจากที่บันทึกไว้')).step, undefined);
  assert.equal((await chat.send('เช็กเงินว่างงานจากการออกงานครั้งใหม่')).step.fact, 'ss33');
});

test('MAN-28 a failed refresh preserves valid and expired cache data without extending its validity', async t => {
  const tangRat = await startTangRatError();
  t.after(tangRat.close);
  let now = lastValidInstant;
  const create = await setup(t, { clock: () => now, demoSourceRecords: {
    tangRat: cachedTangRatCard
  }, demoTangRatEndpoint: tangRat.endpoint, fetch });
  const user = create(); await user.load('tangRat');
  const unrelated = create(); await unrelated.load('');
  assert.deepEqual(await unrelated.refreshDemoTangRat(), { status: 'unavailable' });
  assert.deepEqual(tangRat.requests, []);

  const before = (await user.profile()).factProvenance.disabilityCard;
  assert.equal(before.value, true);
  assert.equal(before.checkedAt, '2026-11-27');
  assert.deepEqual(await user.refreshDemoTangRat(), { status: 'failed', upstreamStatus: 503 });
  assert.deepEqual((await user.profile()).factProvenance.disabilityCard, before);
  assert.equal((await user.facts()).disabilityCard, true);

  const chat = await user.chat();
  const valid = await chat.send('เช็กเบี้ยความพิการ');
  assert.equal(valid.step, undefined);
  assert.match(valid.reply, /ประเมิน 800/);

  now = firstExpiredInstant;
  assert.deepEqual(await user.refreshDemoTangRat(), { status: 'failed', upstreamStatus: 503 });
  assert.equal(tangRat.requests.length, 2);
  assert.ok(tangRat.requests.every(call => call.path === '/disability-card' && call.status === 503));
  assert.equal((await user.facts()).disabilityCard, undefined);
  const card = (await user.profile()).factProvenance.disabilityCard;
  assert.deepEqual(card, { ...before, status: 'stale' });
  assert.equal((await chat.send('เช็กเบี้ยความพิการ')).step.fact, 'disabilityCard');
  const tax = await chat.send('เช็กเงินคืนภาษี');
  assert.equal(tax.step.fact, 'taxWithheld');
  assert.doesNotMatch(tax.reply, /บัตรคนพิการ/);
});

test('MAN-29 the second request keeps its amount while tax is checked first', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat();
  const tax = await chat.send('ช่วยเช็กคืนภาษี แล้วช่วยวางแผนหาเงินเพิ่ม 5,000 ด้วย');
  assert.equal(tax.step.fact, 'taxWithheld');
  const done = await chat.send('เคย', tax.step.id);
  assert.ok(done.quickReplies.includes('ไปเรื่องถัดไป'));
  assert.match((await chat.send('ไปเรื่องถัดไป')).reply, /5,000.*เงินก้อน.*เดือนละ/);
});

test('MAN-30 generated links and numbers without a tool citation are omitted', async t => {
  const create = await setup(t, { agent: model(async () => mockReply('ยื่นที่ https://invented.invalid/claim หรือโทร 081-555-1234')) });
  const user = create(); await user.consent();
  const turn = await (await user.chat()).send('ช่วยอธิบายผลเช็กเงินของฉัน');
  assert.doesNotMatch(turn.reply, /invented|081-555/);
  assert.match(turn.reply, /ดูช่องทางในแอป/);
});

test('MAN-31 ambiguous age after a reference to mother needs confirmation', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat(); await chat.send(oldAge); await chat.send('ช่วยเช็กสิทธิให้แม่');
  const turn = await chat.send('อายุ 72');
  assert.equal(turn.step.fact, 'subjectAge');
  assert.deepEqual(await user.facts(), {});
  await chat.send('อายุของฉัน', turn.step.id);
  assert.equal((await user.facts()).ageBand, '70-79');
});

test('MAN-32 two simultaneous answers cannot advance two steps', async t => {
  const user = (await setup(t))(); await user.consent();
  const chat = await user.chat(), question = await chat.send(oldAge);
  const results = await Promise.all([chat.send('60-69', question.step.id), chat.send('60-69', question.step.id)]);
  assert.equal(results[0].step.id, results[1].step.id);
  assert.equal(results[0].step.fact, 'nationality');
  assert.deepEqual(await user.facts(), { ageBand: '60-69' });
});

test('MAN-33 in-flight results are discarded when AI or source access is withdrawn', async t => {
  let calls = 0, announce, release;
  const create = await setup(t, { agent: model(async () => {
    calls++;
    announce();
    await new Promise(resolve => { release = resolve; });
    return mockReply('คำตอบเก่าจากโมเดล');
  }) });
  const user = create();
  await user.consent(true);
  const chat = await user.chat();
  const first = new Promise(resolve => { announce = resolve; });
  const revokedAi = chat.send('ช่วยดูเงินของฉันหน่อย', undefined, 403);
  await first;
  await user.consent(false);
  release();
  await revokedAi;
  assert.deepEqual((await user.request('GET', '/v1/me/memory')).items, []);
  assert.equal(calls, 1);

  await user.consent(true, true);
  const { state } = await user.request('POST', '/v1/me/gov-link', undefined, 201);
  await user.request('POST', '/v1/me/gov-link/callback', { state, code: 'synthetic' });
  const linked = await user.chat();
  const second = new Promise(resolve => { announce = resolve; });
  const revokedSource = linked.send('ช่วยดูเงินของฉันหน่อย');
  await second;
  await user.request('DELETE', '/v1/me/gov-link', undefined, 204);
  release();
  const fresh = await revokedSource;
  assert.doesNotMatch(fresh.reply, /คำตอบเก่า|1,850/);
  assert.equal((await user.request('GET', '/v1/me/gov-link')).status, 'not_connected');
  assert.equal(calls, 2);
});
