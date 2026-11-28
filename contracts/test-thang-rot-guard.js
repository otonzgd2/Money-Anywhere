// Opt-in acceptance checks. Run: node --test --test-reporter=spec contracts/test-thang-rot-guard.js
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { after, before, test } = require('node:test');
const { createServer } = require('./mock-server');
const { createAi } = require('./adapters/ai');
const { createAgent } = require('./adapters/agent');
const { socialSecurityFacts, tangRatFacts } = require('./adapters/gov-prefill-demo');
const { taxWithholdingFacts } = require('./adapters/demo-tax');
const benefitFactNames = Object.keys(require('./fixtures/reference.json').facts);

const sourceFacts = {
  thaid: ['ageBand', '60-69'],
  tangRat: ['disabilityCard', true],
  socialSecurity: ['ss33', true],
  dMyTax: ['taxWithheld', true]
};
const agentCalls = [];
const extractorCalls = [];
const localAi = createAi({ baseUrl: '', apiKey: '' });
const localAgent = createAgent({ baseUrl: '', apiKey: '' });
const servers = [];
let local;
let observed;
let nextDevice = 0;

async function openServer(ai, agent) {
  const server = createServer({
    appMode: 'demo', demo: true, govConnected: true, jobs: false,
    ai, agent, aiDailyLimit: 0, aiLogFile: '', retentionDays: 0,
    fetch: async () => { throw new Error('External calls are disabled in this suite'); }
  });
  servers.push(server);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return 'http://127.0.0.1:' + server.address().port;
}

before(async () => {
  local = await openServer(localAi, localAgent);
  observed = await openServer({
    provider: 'test',
    async extract(field, text) {
      extractorCalls.push({ field, text });
      return localAi.extract(field, text);
    }
  }, createAgent({
    baseUrl: 'https://model.invalid/v1', apiKey: 'test-key', apiStyle: 'chat-completions',
    async fetch(_url, { body }) {
      agentCalls.push(JSON.parse(body));
      return Response.json({ choices: [{ message: { content: 'ผลทดสอบจากตัวแทน LLM' } }] });
    }
  }));
});

after(async () => {
  await Promise.all(servers.map(server => new Promise(resolve => server.close(resolve))));
});

function client(base = local) {
  const device = 'thang-rot-guard-test-' + ++nextDevice;
  return async (method, path, body, status = 200) => {
    const response = await fetch(base + path, {
      method,
      headers: { 'Content-Type': 'application/json', 'X-Device-Id': device },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    const data = response.status === 204 ? null : await response.json();
    assert.equal(response.status, status, method + ' ' + path + ' returned ' + JSON.stringify(data));
    return data;
  };
}

async function person(api, { ai = true, gov = false, facts, profile } = {}) {
  const notice = await api('GET', '/v1/privacy/notice');
  await api('POST', '/v1/me/consents', {
    noticeVersion: notice.version,
    ageConfirmed: true,
    purposes: { core: true, ai, gov }
  }, 201);
  if (facts) await api('PATCH', '/v1/me/facts', facts);
  if (profile) await api('PUT', '/v1/me/profile', profile);
}

async function chat(api) {
  const opened = await api('POST', '/v1/ai/conversations', { mode: 'guided' }, 201);
  return {
    ...opened,
    send: text => api('POST', '/v1/ai/conversations/' + opened.conversationId + '/messages', { text })
  };
}

function usedTool(turn, tool) {
  return turn.toolCalls.some(call => call.tool === tool);
}

const sourceIds = Object.keys(sourceFacts);
for (let mask = 0; mask < 2 ** sourceIds.length; mask++) {
  const selected = sourceIds.filter((_, index) => mask & (1 << index));
  const id = 'SRC-' + String(mask).padStart(2, '0');
  test(id + ' เลือกแหล่งเดโม ' + (selected.join(', ') || 'ไม่มี'), async () => {
    const api = client();
    const result = await api('POST', '/v1/demo/personas/gov-prefill?sources=' + selected.join(','));
    const facts = await api('GET', '/v1/me/facts');
    assert.equal(result.dataStatus, 'mock');
    assert.equal(Boolean(result.identity), selected.includes('thaid'));
    assert.deepEqual(result.sources.map(source => source.field),
      selected.map(source => source === 'thaid' ? 'identity' : sourceFacts[source][0]));
    for (const [source, [key, expected]] of Object.entries(sourceFacts)) {
      assert.equal(Object.hasOwn(facts, key), selected.includes(source), source + ' ' + key);
      if (selected.includes(source)) assert.equal(facts[key], expected);
    }
    assert.equal(facts.govPension, false, 'fixture answer is separate from the four connection fields');
  });
}

const taxCases = [
  ['DATA-01', 'ยอดภาษีเป็นบวก', 2026, 1250, false, { taxWithheld: true }],
  ['DATA-02', 'ยอดศูนย์และข้อมูลครบ', 2026, 0, true, { taxWithheld: false }],
  ['DATA-03', 'ยอดศูนย์และข้อมูลไม่ครบ', 2026, 0, false, {}],
  ['DATA-04', 'ปีภาษีผิดปี', 2025, 1250, true, {}],
  ['DATA-05', 'ยอดภาษีติดลบ', 2026, -1, true, {}]
];
for (const [id, name, taxYear, amountTHB, complete, expected] of taxCases) {
  test(id + ' ' + name, () => {
    assert.deepEqual(taxWithholdingFacts({ taxYear, withholdingSummary: { amountTHB, complete } }, 2026), expected);
  });
}

const ssoCases = [
  ['DATA-06', 'สมทบ 5 เดือนในช่วงที่ครบ', 33, 15, 5, true, { ss33: false }],
  ['DATA-07', 'สมทบครบ 6 เดือน', 33, 15, 6, true, { ss33: true }],
  ['DATA-08', 'ประวัติสมทบยังไม่ครบ', 33, 15, 8, false, {}],
  ['DATA-09', 'ประวัติมีเพียง 14 เดือน', 33, 14, 8, true, {}],
  ['DATA-10', 'ประวัติเป็น ม.39', 39, 15, 8, true, {}],
  ['DATA-11', 'จำนวนเดือนมากกว่าช่วงเวลา', 33, 15, 16, true, {}]
];
for (const [id, name, coverageSectionAtExit, windowMonthsBeforeExit, paidMonths, complete, expected] of ssoCases) {
  test(id + ' ' + name, () => {
    assert.deepEqual(socialSecurityFacts({
      coverageSectionAtExit,
      contributionHistory: { windowMonthsBeforeExit, paidMonths, complete }
    }), expected);
  });
}

const cardCases = [
  ['DATA-12', 'บัตรใช้ได้', { disabilityCard: { status: 'active' } }, { disabilityCard: true }],
  ['DATA-13', 'หน่วยงานระบุว่าบัตรใช้ไม่ได้', { disabilityCard: { status: 'inactive' } }, { disabilityCard: false }],
  ['DATA-14', 'บริการไม่ส่งสถานะบัตร', {}, {}]
];
for (const [id, name, record, expected] of cardCases) {
  test(id + ' ' + name, () => assert.deepEqual(tangRatFacts(record), expected));
}

test('DATA-15 ยกเลิก ThaID คืนค่าช่วงอายุที่ผู้ใช้เคยตอบ', async () => {
  const api = client();
  await person(api, { gov: true, facts: { ageBand: '70-79', govPension: false } });
  const started = await api('POST', '/v1/me/gov-link', undefined, 201);
  await api('POST', '/v1/me/gov-link/callback', { state: started.state, code: 'demo-bypass' });
  await api('DELETE', '/v1/me/gov-link', undefined, 204);
  assert.deepEqual(await api('GET', '/v1/me/facts'), { ageBand: '70-79', govPension: false });
  assert.equal((await api('GET', '/v1/me/gov-link')).status, 'not_connected');
});

test('DATA-16 ห้ามนับเบี้ยผู้สูงอายุในยอดแนวโน้มเมื่อยังขาดสัญชาติและทะเบียนบ้าน', async () => {
  const api = client();
  const preview = await api('POST', '/v1/money/preview', {
    facts: { ageBand: '60-69', govPension: false, oldAgeGets: false }
  });
  const item = preview.items.find(item => item.id === 'old_age');
  assert.match(item.status, /^(need|check)$/);
  assert.equal(preview.summary.monthly, 0);
});

test('DATA-17 คำตอบของโปรไฟล์หนึ่งไม่ปะปนกับอีกโปรไฟล์', async () => {
  const first = client();
  const second = client();
  await person(first, { facts: { ageBand: '70-79', disabilityCard: true } });
  await person(second);
  assert.deepEqual(await second('GET', '/v1/me/facts'), {});
  assert.deepEqual(await first('GET', '/v1/me/facts'), { ageBand: '70-79', disabilityCard: true });
});

test('CHAT-01 คำพูดอยากได้ตัง 5000 ต้องถามเงินก้อนหรือรายเดือน', async () => {
  const api = client();
  await person(api);
  const convo = await chat(api);
  const eligibility = await convo.send('อยากเช็กเบี้ยผู้สูงอายุ');
  assert.equal(eligibility.step?.fact, 'ageBand', eligibility.reply);
  const turn = await convo.send('อยากได้ตัง 5000 หาให้หน่อยดิ๊');
  assert.deepEqual(await api('GET', '/v1/me/facts'), {});
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.match(turn.reply, /เงินก้อน/);
  assert.match(turn.reply, /เดือนละ|รายเดือน/);
});

const monthlyCases = [
  ['CHAT-02', 'อยากได้เงินเดือนละ 5,000 บาท'],
  ['CHAT-03', 'อายุ 65 แล้ว อยากมีเงินเพิ่มเดือนละ 5,000 บาท'],
  ['CHAT-04', 'อยากมีเงินเพิ่มเดือนละ ๕,๐๐๐ บาท']
];
for (const [id, text] of monthlyCases) {
  test(id + ' เป้าชัดเจน ' + text, async () => {
    const api = client();
    await person(api);
    const turn = await (await chat(api)).send(text);
    assert.equal(usedTool(turn, 'plan_income_goal'), true, turn.reply);
    assert.match(turn.reply, /เป้า 5,000 บาท\/เดือน/);
  });
}

test('CHAT-05 เงินก้อนที่มีเส้นตายต้องอิงยอดและกำหนดที่ผู้ใช้บอก', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('หาเงินห้าพันจ่ายค่าเช่าสิ้นเดือน');
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.match(turn.reply, /5,000|5000|ห้าพัน/);
  assert.match(turn.reply, /สิ้นเดือน|ค่าเช่า/);
});

test('CHAT-06 ขอทำงานจากบ้านระหว่างที่มีคำถามเดิมค้าง', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('มีอะไรให้ทำจากบ้านบ้าง เดินไกลไม่ไหว');
  assert.doesNotMatch(turn.reply, /ฉันช่วยได้เฉพาะ|กลับมาที่คำถาม:.*อายุ/);
  assert.match(turn.reply, /จากบ้าน|ที่บ้าน|ทักษะ|เวลาว่าง/);
});

test('CHAT-07 คำตอบสั้นอิงคำถามเรื่องการได้รับเบี้ย', async () => {
  const api = client();
  await person(api, { facts: { ageBand: '60-69', govPension: false } });
  const convo = await chat(api);
  const topic = await convo.send('อยากเช็กสถานะการรับเบี้ยผู้สูงอายุ');
  assert.equal(topic.step?.fact, 'oldAgeGets', topic.reply);
  await convo.send('ยังไม่ได้ค่ะ');
  assert.equal((await api('GET', '/v1/me/facts')).oldAgeGets, false);
});

test('CHAT-08 ได้คำตอบอายุจากโปรไฟล์ระหว่างรอ ต้องประมวลเป้ารายได้ที่เพิ่งส่งด้วย', async () => {
  const api = client();
  await person(api);
  const convo = await chat(api);
  await api('PATCH', '/v1/me/facts', { ageBand: '60-69' });
  const turn = await convo.send('อยากได้เงินเดือนละ 5,000 บาท');
  assert.equal(usedTool(turn, 'plan_income_goal'), true, turn.reply);
});

test('CHAT-09 ยอดติดลบต้องไม่กลายเป็นเป้าบวก', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('อยากมีเงินเพิ่มเดือนละ -5000 บาท');
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.match(turn.reply, /กรอก|ระบุ|ยืนยัน|จำนวนเงิน/);
});

test('CHAT-10 ข้ามข้อที่ไม่แน่ใจแล้วไม่วนมาถามข้อเดิมในรอบนั้น', async () => {
  const api = client();
  await person(api);
  const convo = await chat(api);
  const eligibility = await convo.send('อยากเช็กเบี้ยผู้สูงอายุ');
  assert.equal(eligibility.step?.fact, 'ageBand', eligibility.reply);
  const skipped = await convo.send('ไม่แน่ใจ ข้ามข้อนี้');
  const following = await convo.send('ไม่แน่ใจ ข้ามข้อนี้');
  assert.notEqual(skipped.step?.fact, 'ageBand');
  assert.notEqual(following.step?.fact, 'ageBand');
  assert.deepEqual(await api('GET', '/v1/me/facts'), {});
});

test('CHAT-11 ไม่ยินยอมใช้ AI ยังใช้การคัดกรองและวางแผนแบบไม่ใช้โมเดลได้', async () => {
  const api = client();
  await person(api, { ai: false });
  const preview = await api('POST', '/v1/money/preview', { facts: {} });
  const goal = await api('GET', '/v1/plans/goal?target=5000');
  assert.equal(preview.stored, false);
  assert.equal(goal.target, 5000);
  await api('POST', '/v1/ai/conversations', { mode: 'guided' }, 403);
});

test('CHAT-12 สองยอดที่มีความหมายชัดเจนต้องใช้ยอดเป้าหมาย', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('ตอนนี้ได้วันละ 500 แต่อยากมีเพิ่มเดือนละ 5,000 บาท');
  assert.match(turn.reply, /เป้า 5,000 บาท\/เดือน/);
});

test('CHAT-13 ข้อความปฏิเสธเป้าหมายต้องไม่สร้างแผนจากยอดที่เพิ่งปฏิเสธ', async () => {
  const api = client();
  await person(api, { profile: { incomeGoalPerMonth: 3000 } });
  const turn = await (await chat(api)).send('ไม่ได้อยากได้เงินเดือนละ 5000 แล้วค่ะ');
  assert.equal((await api('GET', '/v1/me/profile')).incomeGoalPerMonth, 3000);
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
});

test('CHAT-14 เป้ารายเดือนเกินขอบเขตต้องไม่ถูกปัดเป็นยอดอื่น', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('อยากมีเงินเพิ่มเดือนละ 1,000,001 บาท');
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.match(turn.reply, /จำนวน|ยอด|กรอก|ระบุ/);
});

test('CHAT-15 เปิดแชทที่ยังไม่มีเจตนา ให้เลือกเป้าหมายก่อนถามอายุ', async () => {
  const api = client();
  await person(api);
  const convo = await chat(api);
  assert.notEqual(convo.step?.fact, 'ageBand', convo.greeting);
  assert.ok(convo.quickReplies.some(reply => /สิทธิ/.test(reply)));
  assert.ok(convo.quickReplies.some(reply => /หาเงินเพิ่ม/.test(reply)));
});

test('CHAT-16 ตัวเลขเดี่ยวตอบคำถามจำนวนวันที่ค้างจ่ายได้', async () => {
  const api = client();
  await person(api, {
    facts: {
      ageBand: 'ต่ำกว่า 60', work: 'ทำงานประจำ', kidUnder6: false,
      disabilityCard: false, taxWithheld: false, hasUnpaid: true
    }
  });
  const convo = await chat(api);
  const topic = await convo.send('อยากเช็กค่าจ้างค้างจ่าย');
  assert.equal(topic.step?.fact, 'unpaidDays', topic.reply);
  const answer = await convo.send('5');
  assert.equal((await api('GET', '/v1/me/facts')).unpaidDays, 5);
  assert.equal(usedTool(answer, 'plan_income_goal'), false);
});

test('CHAT-17 มีสองยอดที่ยังชี้เป้าไม่ได้ ให้ถามยืนยันยอด', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('อยากได้เงินเพิ่ม 5,000 หรือ 8,000 ยังไม่แน่ใจ');
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.match(turn.reply, /ยอดไหน|เท่าไหร่|เลือก|จำนวนเงิน/);
});

test('SAFE-01 ข้อมูลลับต้องถูกกันก่อนเรียกโมเดลและเข้าประวัติ', async () => {
  const api = client(observed);
  await person(api, { profile: { skills: ['ทำอาหาร'], hoursPerWeek: '5', constraints: 'ทำที่บ้าน' } });
  const convo = await chat(api);
  const fakeSecret = 'OTP 000123';
  const count = [extractorCalls.length, agentCalls.length];
  const blocked = await convo.send(fakeSecret);
  const afterBlocked = [extractorCalls.length, agentCalls.length];
  assert.deepEqual(afterBlocked, count);
  assert.equal(blocked.guard.kind, 'sensitive');
  assert.doesNotMatch(JSON.stringify(await api('GET', '/v1/me/memory')), /000123/);
  await convo.send('ช่วยคิดไอเดียหางานที่ใช้ทักษะทำอาหารจากบ้านให้ฉัน');
  const sent = agentCalls.slice(count[1]);
  assert.ok(sent.length > 0);
  assert.equal(JSON.stringify(sent).includes('000123'), false);
});

test('SAFE-02 คำถามเรื่องค่ามัดจำได้คำเตือนและทางไปต่อเรื่องงาน', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('งานนี้ให้จ่ายค่ามัดจำ ปกติไหม?');
  assert.match(turn.reply, /ระวัง|มิจฉาชีพ/);
  assert.match(turn.reply, /ตรวจประกาศ|ตรวจนายจ้าง|ตรวจชื่อบริษัท|หางานอื่น|ดูประกาศอื่น|ดูงานอื่น/);
});

test('SAFE-03 คำขอนอกขอบเขตชัดเจนได้ทางกลับและไม่บันทึก facts', async () => {
  const api = client(observed);
  await person(api);
  const convo = await chat(api);
  const count = [extractorCalls.length, agentCalls.length];
  const turn = await convo.send('แต่งกลอนให้หน่อย');
  assert.equal(turn.guard.kind, 'off_topic');
  assert.deepEqual([extractorCalls.length, agentCalls.length], count);
  assert.deepEqual(await api('GET', '/v1/me/facts'), {});
  assert.ok(turn.quickReplies?.length > 0);
});

test('SAFE-04 คำตอบอายุที่อ่านด้วยกฎต้องไม่เรียกตัวสกัด LLM', async () => {
  const api = client(observed);
  await person(api);
  const convo = await chat(api);
  const eligibility = await convo.send('อยากเช็กเบี้ยผู้สูงอายุ');
  assert.equal(eligibility.step?.fact, 'ageBand', eligibility.reply);
  const count = [extractorCalls.length, agentCalls.length];
  await convo.send('อายุ 65 ปีค่ะ');
  assert.deepEqual([extractorCalls.length, agentCalls.length], count);
  assert.equal((await api('GET', '/v1/me/facts')).ageBand, '60-69');
});

test('SAFE-05 ชื่อในโปรไฟล์ไม่จำเป็นต่อคำแนะนำเรื่องหางาน', async () => {
  const api = client(observed);
  const displayName = 'ชื่อสมมติสำหรับตรวจข้อมูล LLM';
  await person(api, { profile: { displayName, skills: ['ทำอาหาร'], hoursPerWeek: '5', constraints: 'ทำที่บ้าน' } });
  const convo = await chat(api);
  const count = agentCalls.length;
  await convo.send('ช่วยคิดไอเดียหางานที่ใช้ทักษะทำอาหารจากบ้านให้ฉัน');
  const sent = agentCalls.slice(count);
  assert.ok(sent.length > 0);
  assert.equal(JSON.stringify(sent).includes(displayName), false);
});

test('SAFE-06 ผู้ใช้ถามความปลอดภัยเกี่ยวกับ OTP โดยไม่มีรหัสในข้อความ', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('สมัครงานแล้วเขาบอกให้ส่ง OTP แบบนี้ปลอดภัยไหม');
  assert.notEqual(turn.guard?.kind, 'sensitive', turn.reply);
  assert.match(turn.reply, /อย่าส่ง|ไม่ควรส่ง|ตรวจนายจ้าง|มิจฉาชีพ/);
});

// Ask through the same messages endpoint as the app. Each test has its own persona.
// The seeded work history and wage belong to the fixture, irrespective of selected services.
const topicJourneys = [
  { source: 'thaid', topic: 'old_age', text: 'ช่วยเช็กสิทธิเบี้ยผู้สูงอายุให้ฉัน',
    missing: 'ageBand', afterPrefill: 'nationality' },
  { source: 'tangRat', topic: 'disability', text: 'ขอเช็กเบี้ยความพิการเฉพาะส่วนพื้นฐานของฉัน',
    missing: 'disabilityCard', result: /ความพิการ|เบี้ยคนพิการ/ },
  { source: 'socialSecurity', topic: 'unemployment', text: 'ช่วยประเมินเงินว่างงานของฉันสำหรับการออกจากงานครั้งเดียวกับที่บันทึกไว้',
    missing: 'ss33', result: /ว่างงาน/ },
  { source: 'dMyTax', topic: 'tax_refund', text: 'อยากเช็กเงินคืนภาษีของฉัน ปีภาษี 2569',
    missing: 'taxWithheld', result: /คืนภาษี|ภาษีคืน/ }
];
for (let mask = 0; mask < 2 ** sourceIds.length; mask++) {
  const selected = sourceIds.filter((_, index) => mask & (1 << index));
  for (const journey of topicJourneys) {
    const id = 'FLOW-' + String(mask).padStart(2, '0') + '-' + journey.topic;
    test(id + ' ถามเฉพาะเรื่องที่เลือก ตามข้อมูลที่มีในโปรไฟล์', async () => {
      const expected = selected.includes(journey.source) ? journey.afterPrefill : journey.missing;
      const api = client(expected ? observed : local);
      await api('POST', '/v1/demo/personas/gov-prefill?sources=' + selected.join(','));
      const beforeFacts = await api('GET', '/v1/me/facts');
      const convo = await chat(api);
      const calls = [extractorCalls.length, agentCalls.length];
      const turn = await convo.send(journey.text);
      if (expected) {
        assert.equal(turn.step?.fact, expected, turn.reply);
        assert.equal(turn.step.moneyId, journey.topic);
        assert.ok(turn.reply.includes(turn.step.question), 'the app renders reply text as the question');
        assert.deepEqual([extractorCalls.length, agentCalls.length], calls);
      } else {
        assert.equal(turn.step?.fact, undefined, turn.reply);
        assert.doesNotMatch(turn.reply, /กลับมาที่คำถาม|ข้อต่อไป.*อายุ|ฉันช่วยได้เฉพาะ/);
        assert.match(turn.reply, journey.result);
        assert.match(turn.reply, /ประมาณ|ประเมิน|ตรวจ|เช็ก|เช็ค|ยื่น|ขั้นตอน|ยอดจริง|บาท/);
        for (const other of topicJourneys.filter(other => other !== journey && other.result)) {
          assert.doesNotMatch(turn.reply, other.result, 'a single-topic request returned a different benefit');
        }
      }
      assert.deepEqual(await api('GET', '/v1/me/facts'), beforeFacts);
    });
  }
}

test('TURN-01 เก็บยอดข้ามเทิร์นเมื่อผู้ใช้ตอบเพียง “รายเดือน”', async () => {
  const api = client();
  await person(api, { profile: { incomeGoalPerMonth: 3000 } });
  const convo = await chat(api);
  const first = await convo.send('อยากได้ตัง 5000 หาให้หน่อยดิ๊');
  const second = await convo.send('รายเดือน');
  assert.equal(usedTool(first, 'plan_income_goal'), false);
  assert.equal(usedTool(second, 'plan_income_goal'), true, second.reply);
  assert.match(second.reply, /5,000|5000/);
  assert.equal((await api('GET', '/v1/me/profile')).incomeGoalPerMonth, 3000);
});

test('TURN-02 ผู้ใช้เลือกเงินก้อนแล้วแก้ยอด ระบบใช้ยอดล่าสุดโดยไม่เขียนทับโปรไฟล์', async () => {
  const api = client();
  await person(api, { profile: { incomeGoalPerMonth: 3000 } });
  const convo = await chat(api);
  await convo.send('อยากได้เงิน 5,000 บาท');
  const turn = await convo.send('เงินก้อน ขอแก้เป็น 3,500 บาทไว้จ่ายค่าเช่า');
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.match(turn.reply, /3,500|3500/);
  assert.match(turn.reply, /ก้อน|ค่าเช่า/);
  assert.equal(benefitFactNames.includes(turn.step?.fact), false);
  assert.equal((await api('GET', '/v1/me/profile')).incomeGoalPerMonth, 3000);
});

test('choosing a saved goal offers next steps and does not print the same plan again', async () => {
  const api = client();
  await person(api, { profile: { incomeGoalPerMonth: 5000 } });
  const convo = await chat(api);
  assert.equal((await convo.send('วางแผนหาเงินเพิ่ม')).step.fact, 'savedGoal');
  const plan = await convo.send('ใช้เป้าเดิม');
  assert.equal(usedTool(plan, 'plan_income_goal'), true);
  assert.ok(plan.quickReplies.includes('หางานใกล้บ้าน'));
  assert.ok(plan.quickReplies.includes('เปลี่ยนเป้าหมาย'));
  assert.ok(!plan.quickReplies.includes('วางแผนหาเงินเพิ่ม'));

  const again = await convo.send('วางแผนหาเงินเพิ่ม');
  assert.notEqual(again.reply, plan.reply);
  assert.equal(usedTool(again, 'plan_income_goal'), false);
  assert.equal((await convo.send('เปลี่ยนเป้าหมาย')).step.fact, 'goalAmount');
});

test('a regular-job disclosure updates the current side-income plan and asks for spare hours', async () => {
  const api = client();
  await api('POST', '/v1/demo/personas/gov-prefill');
  await person(api, { profile: { incomeGoalPerMonth: 5000, district: 'ปทุมวัน' } });
  const earlierWork = (await api('GET', '/v1/me/facts')).work;
  const convo = await chat(api);
  await convo.send('วางแผนหาเงินเพิ่ม');
  const original = await convo.send('ใช้เป้าเดิม');
  assert.match(original.reply, /งานแพ็คของ รายวัน/);

  const availability = await convo.send('ฉันมีงานประจำอยู่แล้ว');
  assert.match(availability.reply, /นอกเวลางานประจำ/);
  assert.equal(availability.step?.fact, 'sideJobHours');
  assert.equal(usedTool(availability, 'plan_income_goal'), false);

  const revised = await convo.send('4 ชั่วโมงต่อสัปดาห์');
  assert.equal(usedTool(revised, 'plan_income_goal'), true);
  assert.match(revised.reply, /5,000/);
  assert.match(revised.reply, /งานเสริม|งานประจำ/);
  assert.doesNotMatch(revised.reply, /งานแพ็คของ รายวัน|ผู้ช่วยร้านอาหาร|5,196/);
  assert.equal((await api('GET', '/v1/me/facts')).work, earlierWork);
});

test('a follow-up asking for other jobs stays with the search and gets different candidates', async () => {
  const searched = [];
  const api = client(await openServer(localAi, {
    provider: 'test',
    async respond({ tools }) {
      const { items } = await tools.search_opportunities.run({ group: 'job', limit: 1 });
      searched.push(items.map(item => item.id));
      return {
        aiStatus: 'ok', reply: items.map(item => item.title).join('\n') || 'ยังไม่พบงานอื่นในระยะนี้',
        toolCalls: [{ tool: 'search_opportunities' }],
      };
    },
  }));
  await person(api, { profile: { district: 'ปทุมวัน' } });
  const convo = await chat(api);
  const first = await convo.send('หางานใกล้บ้าน');
  assert.ok(first.quickReplies.includes('ดูงานอื่น'));
  const second = await convo.send('มีงานอื่นไหม');
  assert.equal(second.aiStatus, 'ok');
  assert.equal(second.guard.kind, 'in_scope');
  assert.equal(second.step, undefined);
  assert.equal(usedTool(second, 'search_opportunities'), true);
  assert.equal(searched[0].length, 1);
  assert.equal(searched[1].length, 1);
  assert.notEqual(searched[0][0], searched[1][0]);
});

test('TURN-03 ขอประเมินสิทธิให้คนอื่นในเทิร์นที่กำลังถามอายุ', async () => {
  const api = client(observed);
  await person(api);
  const convo = await chat(api);
  await convo.send('ช่วยเช็กสิทธิเบี้ยผู้สูงอายุให้ฉัน');
  const calls = [extractorCalls.length, agentCalls.length];
  const turn = await convo.send('ช่วยเช็กให้แม่ แม่อายุ 72 ปี');
  assert.match(turn.reply, /ตัวคุณ|ตัวเอง|เจ้าของโปรไฟล์|ของคุณเอง/);
  assert.deepEqual(await api('GET', '/v1/me/facts'), {});
  assert.deepEqual([extractorCalls.length, agentCalls.length], calls);
});

test('TURN-04 พูดถึงแม่แต่ขอหางานให้ตัวเอง', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('ต้องดูแลแม่ อยากหางานที่ฉันทำจากบ้านได้');
  assert.doesNotMatch(turn.reply, /ฉันช่วยได้เฉพาะ|กลับมาที่คำถาม|เช็กได้เฉพาะเจ้าของ/);
  assert.match(turn.reply, /จากบ้าน|ที่บ้าน|ทักษะ|เวลาว่าง/);
  assert.deepEqual(await api('GET', '/v1/me/facts'), {});
});

test('TURN-05 ผู้ใช้บอกค่าใช้จ่ายโดยยังไม่ได้ขอยอดหรือระบุสิทธิ', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('สิ้นเดือนนี้ยังขาดค่าเช่าห้อง');
  assert.equal(usedTool(turn, 'plan_income_goal'), false);
  assert.doesNotMatch(turn.reply, /ฉันช่วยได้เฉพาะ|กลับมาที่คำถาม/);
  assert.match(turn.reply, /ค่าเช่า|รายจ่าย|ค่าใช้จ่าย/);
  assert.match([turn.reply, ...(turn.quickReplies || [])].join(' '), /สิทธิ|หาเงินเพิ่ม|ขาด.*เท่าไหร่/);
  assert.equal(benefitFactNames.includes(turn.step?.fact), false);
});

test('TURN-06 ถอนความยินยอม AI ในบทสนทนาเดิมแล้วใช้เครื่องมือแบบกฎต่อ', async () => {
  const api = client(observed);
  await person(api);
  const convo = await chat(api);
  await person(api, { ai: false });
  const calls = [extractorCalls.length, agentCalls.length];
  await api('POST', '/v1/ai/conversations/' + convo.conversationId + '/messages', { text: 'อยากหางาน' }, 403);
  const preview = await api('POST', '/v1/money/preview', { facts: {} });
  assert.equal(preview.stored, false);
  const goal = await api('GET', '/v1/plans/goal?target=5000');
  assert.equal(goal.target, 5000);
  assert.deepEqual([extractorCalls.length, agentCalls.length], calls);
});

test('TURN-07 ไม่มีบริการที่เชื่อมก็ใช้คำตอบปฏิเสธที่ผู้ใช้เพิ่งให้ได้', async () => {
  const api = client();
  await person(api, { facts: { disabilityCard: false } });
  const turn = await (await chat(api)).send('ขอเช็กเบี้ยความพิการเฉพาะส่วนพื้นฐานของฉัน');
  assert.equal(turn.step?.fact, undefined, turn.reply);
  assert.match(turn.reply, /บัตร|ความพิการ/);
  assert.match(turn.reply, /ไม่น่า|ยังไม่มี|ไม่มีบัตร|ต้องมีบัตร|ยังไม่เข้าเกณฑ์/);
  assert.doesNotMatch(turn.reply, /มีบัตร.*ไหม|กลับมาที่คำถาม/);
  assert.equal((await api('GET', '/v1/me/facts')).disabilityCard, false);
});

test('TURN-08 ส่งคำตอบปุ่มเดิมซ้ำ ค่าของข้อใหม่ยังไม่ถูกกรอก', async () => {
  const api = client();
  await person(api, { facts: { ageBand: '60-69', govPension: false } });
  const convo = await chat(api);
  const topic = await convo.send('อยากเช็กสถานะการรับเบี้ยผู้สูงอายุ');
  assert.equal(topic.step?.fact, 'oldAgeGets', topic.reply);
  assert.ok(topic.step.id, 'server must return an identifier for the displayed question');
  const answer = { text: 'ยังไม่ได้ค่ะ', stepId: topic.step.id };
  const path = '/v1/ai/conversations/' + convo.conversationId + '/messages';
  const first = await api('POST', path, answer);
  const beforeReplay = await api('GET', '/v1/me/facts');
  assert.equal(beforeReplay.oldAgeGets, false);
  const second = await api('POST', path, answer);
  assert.deepEqual(await api('GET', '/v1/me/facts'), beforeReplay);
  assert.equal(second.step?.id, first.step?.id);
  assert.equal(second.step?.fact, first.step?.fact);
});

test('TURN-09 ยอดของโครงการที่ถามสิทธิไม่กลายเป็นเป้าหาเงินเพิ่ม', async () => {
  const api = client();
  await person(api);
  const turn = await (await chat(api)).send('เห็นคนพูดถึงเงินช่วยเหลือ 5,000 บาท ฉันมีสิทธิ์โครงการนี้ไหม');
  assert.equal(usedTool(turn, 'plan_income_goal'), false, turn.reply);
  assert.doesNotMatch(turn.reply, /เงินก้อนหรือ|เป้า [\d,]+ บาท\/เดือน/);
  assert.match(turn.reply, /ชื่อโครงการ|โครงการไหน|โครงการอะไร|โครงการใด|ประกาศไหน|ประกาศที่/);
  assert.deepEqual(await api('GET', '/v1/me/facts'), {});
});

async function openCatalogueChat() {
  const { copyFileSync, mkdtempSync } = require('node:fs');
  const { join } = require('node:path');
  const { tmpdir } = require('node:os');
  const jobDbFile = join(mkdtempSync(join(tmpdir(), 'thang-rot-district-')), 'catalogue.db');
  copyFileSync(join(__dirname, '..', 'docs', 'entities', 'database-script', 'demo', 'catalogue.db'), jobDbFile);
  const searched = [];
  const server = createServer({
    appMode: 'demo', demo: true, jobs: false, jobDbFile, aiDailyLimit: 0, aiLogFile: '', retentionDays: 0,
    ai: localAi,
    agent: {
      provider: 'test',
      async respond({ tools }) {
        const { items } = await tools.search_opportunities.run({ group: 'job', limit: 3 });
        searched.push(items.map(item => item.id));
        return { aiStatus: 'ok', reply: items.map(item => item.title).join('\n') || 'ยังไม่พบงาน', toolCalls: [{ tool: 'search_opportunities' }] };
      }
    },
    fetch: async () => { throw new Error('External calls are disabled in this suite'); }
  });
  servers.push(server);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const api = client('http://127.0.0.1:' + server.address().port);
  const districtsOf = async ids => Promise.all(ids.map(async id => (await api('GET', '/v1/opportunities/' + id)).location.district));
  return { api, searched, districtsOf };
}

test('D3-01 หางานใกล้บ้านใช้เขตในโปรไฟล์ ไม่ได้งานเขตอื่น', async () => {
  const { api, searched, districtsOf } = await openCatalogueChat();
  await person(api, { profile: { district: 'บางนา' } });
  const turn = await (await chat(api)).send('หางานใกล้บ้าน');
  assert.equal(usedTool(turn, 'search_opportunities'), true, turn.reply);
  assert.ok(searched[0].length > 0, 'found jobs in Bang Na');
  assert.deepEqual(new Set(await districtsOf(searched[0])), new Set(['บางนา']));
});

test('D3-02 เขตในข้อความมาก่อนเขตในโปรไฟล์ และ "ดูงานอื่น" ยังอยู่เขตเดิม', async () => {
  const { api, searched, districtsOf } = await openCatalogueChat();
  await person(api, { profile: { district: 'บางนา' } });
  const convo = await chat(api);
  await convo.send('หางานแถวประเวศ');
  const more = await convo.send('มีงานอื่นไหม');
  assert.equal(usedTool(more, 'search_opportunities'), true, more.reply);
  assert.deepEqual(new Set(await districtsOf([...searched[0], ...searched[1]])), new Set(['ประเวศ']));
  assert.equal(searched[0].some(id => searched[1].includes(id)), false, 'follow-up shows new listings');
});

test('D3-03 ไม่รู้เขตให้ถามเขตก่อนค้น แล้วค้นตามเขตที่ตอบ', async () => {
  const { api, searched, districtsOf } = await openCatalogueChat();
  await person(api);
  const convo = await chat(api);
  const asked = await convo.send('หางานใกล้บ้าน');
  assert.equal(asked.step?.fact, 'jobDistrict', asked.reply);
  assert.equal(searched.length, 0);
  const answered = await convo.send('บางนา');
  assert.equal(usedTool(answered, 'search_opportunities'), true, answered.reply);
  assert.deepEqual(new Set(await districtsOf(searched[0])), new Set(['บางนา']));
});
