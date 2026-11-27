// Loopback QA server for the Android build. Commands on stdin apply only to this fixture.
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createInterface } = require('node:readline');
const { createServer } = require('./mock-server');
const { createAi } = require('./adapters/ai');
const { createAgent } = require('./adapters/agent');
const { cachedTangRatCard, lastValidInstant, firstExpiredInstant, startTangRatError } = require('./fixtures/man28-refresh');

async function main() {
  const upstream = await startTangRatError();
  let now = lastValidInstant;
  const server = createServer({
    appMode: 'demo', demo: true, jobs: false, dataFile: '', retentionDays: 0,
    ai: createAi({ baseUrl: '', apiKey: '' }),
    agent: createAgent({ baseUrl: '', apiKey: '' }),
    aiLogFile: '', demoSourceRecords: { tangRat: cachedTangRatCard },
    clock: () => now, demoTangRatEndpoint: upstream.endpoint,
    fetch: (url, options) => {
      if (url !== upstream.endpoint) throw new Error('Unexpected external URL in the MAN-28 fixture');
      return fetch(url, options);
    },
  });
  try {
    server.listen(Number(process.argv[2] || 4392), '127.0.0.1');
    await once(server, 'listening');
    const base = 'http://127.0.0.1:' + server.address().port;
    const input = createInterface({ input: process.stdin, terminal: false });
    console.log('MAN-28 API listening on ' + base + '. Enter: valid <device-id>, expired <device-id>, or quit');
    let seededDevice;
    for await (const line of input) {
      const [phase, device, ...extra] = line.trim().split(/\s+/);
      if (phase === 'quit') break;
      try {
        assert.ok(['valid', 'expired'].includes(phase) && /^device-[a-f0-9]+$/.test(device || '') && !extra.length, 'Invalid fixture command');
        const headers = { 'X-Device-Id': device };
        if (phase === 'valid') {
          now = lastValidInstant;
          const seeded = await fetch(base + '/v1/demo/personas/gov-prefill?sources=tangRat', { method: 'POST', headers });
          assert.equal(seeded.status, 200);
          assert.equal((await seeded.json()).facts.disabilityCard, true);
          seededDevice = device;
        } else {
          assert.equal(device, seededDevice, 'Run the valid phase for the same app install first');
          now = firstExpiredInstant;
        }
        const refresh = await server.ports.refreshDemoTangRat(device);
        assert.deepEqual(refresh, { status: 'failed', upstreamStatus: 503 });
        const facts = await (await fetch(base + '/v1/me/facts', { headers })).json();
        const profile = await (await fetch(base + '/v1/me/profile', { headers })).json();
        const card = profile.factProvenance.disabilityCard;
        assert.equal(facts.disabilityCard, phase === 'valid' ? true : undefined);
        assert.equal(card.status, phase === 'valid' ? undefined : 'stale');
        assert.equal(card.checkedAt, '2026-11-27');
        console.log(JSON.stringify({ phase, refresh, upstreamCalls: upstream.requests.length,
          cacheUsable: facts.disabilityCard === true, card }));
      } catch (error) {
        console.error('MAN-28 fixture command failed: ' + error.message);
      }
    }
  } finally {
    await Promise.all([new Promise(resolve => server.close(resolve)), upstream.close()]);
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
