const assert = require('node:assert/strict');
const { once } = require('node:events');
const { join } = require('node:path');
const { createServer } = require('../../../contracts/mock-server');

async function capture() {
  const server = createServer({
    appMode: 'demo',
    demo: true,
    govConnected: true,
    moreMock: true,
    jobs: false,
    live: false,
    dataFile: '',
    aiLogFile: '',
    retentionDays: 0,
    jobDbFile: join(__dirname, '../../entities/database-script/demo/catalogue.db'),
    aiOptions: { baseUrl: '', apiKey: '' },
    clock: () => new Date('2026-11-28T05:00:00Z'),
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = `http://127.0.0.1:${server.address().port}`;
  const examples = [];

  async function call(name, path, { method = 'GET', body, status = 200, headers = {}, project = data => data } = {}) {
    const response = await fetch(origin + path, {
      method,
      headers: { 'X-Device-Id': 'device-skillwar-qa', 'Content-Type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(8000),
    });
    assert.equal(response.status, status, name);
    const data = await response.json();
    examples.push({ name, request: { method, path, headers, body }, status, response: project(data) });
    return data;
  }

  try {
    const config = await call('Config flags', '/v1/app-config', {
      project: ({ mode, noticeVersion, featureFlags }) => ({ mode, noticeVersion, featureFlags }),
    });
    const preview = await call('Synthetic source shape', '/v1/demo/personas/gov-prefill?sources=thaid,socialSecurity', {
      project: ({ dataStatus, sources }) => ({ dataStatus, sources }),
    });
    assert.equal(preview.dataStatus, 'mock');
    await call('Calculate a preview', '/v1/money/preview', {
      method: 'POST',
      body: { facts: { hasUnpaid: true, unpaidDays: 2, dailyWage: 500 } },
      project: ({ items }) => items.filter(item => item.id === 'unpaid_wages')
        .map(({ id, status, amount }) => ({ id, status, amount })),
    });
    const catalogue = await call('Bang Na mock catalogue', '/v1/opportunities?area=bangkok&districtCode=1047&district='
      + encodeURIComponent('บางนา') + '&dataMode=mock&group=job&includeDistrictPins=true&limit=1', {
      project: ({ items, districtPins }) => ({
        items: items.map(({ id, title, category, location, provenance }) =>
          ({ id, title, category, location, provenance })),
        districtPins,
      }),
    });
    assert.equal(catalogue.items[0].id, 'mock_bangkok_catalogue_d20-job_full-01');
    assert.equal(catalogue.districtPins[0].count, 60);
    assert.equal((await fetch(catalogue.items[0].provenance.sourceUrl)).status, 200);
    await call('Give synthetic-user consent', '/v1/me/consents', {
      method: 'POST', status: 201,
      body: { noticeVersion: config.noticeVersion, ageConfirmed: true, purposes: { core: true, ai: true } },
      project: ({ purposes }) => ({ purposes }),
    });
    const turnFields = ({ aiStatus, reply, step, quickReplies }) =>
      ({ aiStatus, reply, step: step && { id: step.id, fact: step.fact }, quickReplies });
    const start = await call('Start guided conversation', '/v1/ai/conversations', {
      method: 'POST', status: 201, body: { mode: 'guided' },
      project: data => ({ conversationId: data.conversationId, ...turnFields(data) }),
    });
    const messages = `/v1/ai/conversations/${start.conversationId}/messages`;
    const asked = await call('Select older persons allowance', messages, {
      method: 'POST', body: { text: 'เช็กสิทธิเบี้ยผู้สูงอายุ', stepId: start.step?.id }, project: turnFields,
    });
    assert.equal(asked.step.fact, 'ageBand');
    const answer = await call('Answer the displayed step', messages, {
      method: 'POST', body: { text: 'อายุ 65 ปีค่ะ', stepId: asked.step.id }, project: turnFields,
    });
    assert.notEqual(answer.step?.fact, 'ageBand');
    const skip = answer.quickReplies.find(text => text.startsWith('ไม่แน่ใจ') && text.includes('ข้าม'));
    assert.ok(skip);
    const skipped = await call('Skip the current benefit question', messages, {
      method: 'POST', body: { text: skip, stepId: answer.step.id }, project: turnFields,
    });
    assert.notEqual(skipped.step?.fact, answer.step.fact);
    const task = await call('Save the catalogue item', '/v1/tasks', {
      method: 'POST', status: 201, body: { opportunityId: catalogue.items[0].id, districtCode: '1047' },
      project: ({ id, title, category, districtCode, status, doneCount, steps }) =>
        ({ id, title, category, districtCode, status, doneCount, steps }),
    });
    const event = {
      method: 'POST', status: 201, headers: { 'Idempotency-Key': 'qa-step-01' },
      body: { type: 'complete_step' },
      project: ({ id, doneCount }) => ({ id, doneCount }),
    };
    const first = await call('Complete the first step', `/v1/tasks/${task.id}/events`, event);
    const retry = await call('Retry the same event', `/v1/tasks/${task.id}/events`, event);
    assert.equal(first.doneCount, 1);
    assert.equal(retry.doneCount, first.doneCount);
    const record = {
      purpose: 'QA evidence from a rules-only runtime. Responses are field projections. Never serve this file as an AI answer.',
      requestDefaults: { 'X-Device-Id': 'device-skillwar-qa', 'Content-Type': 'application/json' },
      examples,
    };
    process.stdout.write(JSON.stringify(record, null, 2).replaceAll(origin, 'http://demo.invalid') + '\n');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

capture().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
