// Run with node tools/gov-data-demo.js from the repository root.
const assert = require('node:assert/strict');
const { once } = require('node:events');
const fixture = require('../contracts/fixtures/gov-prefill-demo.json');
const { createServer } = require('../contracts/mock-server');
const { taxWithholdingFacts } = require('../contracts/adapters/demo-tax');
const { tangRatFacts, socialSecurityFacts } = require('../contracts/adapters/gov-prefill-demo');

function requestFor(base, deviceId) {
  return async (path, method = 'GET', body, expected = 200) => {
    const response = await fetch(base + path, {
      method,
      headers: { 'X-Device-Id': deviceId, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(5000)
    });
    assert.equal(response.status, expected, method + ' ' + path);
    return response.status === 204 ? undefined : response.json();
  };
}

async function guidedQuestions(request) {
  let turn = await request('/v1/ai/conversations', 'POST', { mode: 'guided' }, 201);
  const path = '/v1/ai/conversations/' + turn.conversationId + '/messages';
  const questions = {};
  while (turn.step) {
    assert.ok(!Object.hasOwn(questions, turn.step.fact), 'A skipped question was repeated');
    questions[turn.step.fact] = turn.step.question;
    const skip = turn.quickReplies.find(reply => reply.startsWith('ไม่แน่ใจ') && reply.includes('ข้าม'));
    assert.ok(skip, 'Guided chat has no skip option');
    turn = await request(path, 'POST', { text: skip });
  }
  return questions;
}

async function linkThaId(request) {
  const pending = await request('/v1/me/gov-link', 'POST', {}, 201);
  return request('/v1/me/gov-link/callback', 'POST', { state: pending.state, code: 'demo-prefill' });
}

async function runDemo() {
  assert.equal(fixture.dataStatus, 'synthetic');
  const server = createServer({
    govConnected: true, jobs: false, live: false, dataFile: '', aiLogFile: '',
    aiOptions: { baseUrl: '', apiKey: '' }
  });
  server.listen(0, '127.0.0.1');
  try {
    await once(server, 'listening');
    const base = 'http://127.0.0.1:' + server.address().port;
    const request = requestFor(base, 'device-gov-prefill-demo');
    const { version: noticeVersion } = await request('/v1/privacy/notice');
    const consent = gov => ({ noticeVersion, ageConfirmed: true, purposes: { core: true, ai: true, gov } });
    const confirmed = [];
    const health = await request('/v1/health');
    assert.deepEqual(health.ai, { provider: 'rules', agent: 'rules' });
    assert.equal(health.store, 'memory');

    await request('/v1/me/consents', 'POST', consent(false), 201);
    const denied = await request('/v1/me/gov-link', 'POST', {}, 403);
    assert.equal(denied.code, 'CONSENT_REQUIRED');
    confirmed.push('ThaID mock requires government-data consent');

    await request('/v1/me/facts', 'PATCH', fixture.initialAnswers);
    const baseline = await guidedQuestions(request);
    assert.deepEqual(Object.keys(baseline), ['ageBand', 'ss33', 'disabilityCard']);
    const waitingForAge = await request('/v1/ai/conversations', 'POST', { mode: 'guided' }, 201);
    assert.equal(waitingForAge.step.fact, 'ageBand');

    await request('/v1/me/consents', 'POST', consent(true), 201);
    const link = await linkThaId(request);
    assert.equal(link.status, 'connected');
    assert.equal(link.identity.dataStatus, 'mock');
    assert.ok(!Object.hasOwn(link.identity.claims, 'pid'));
    const linkedFacts = await request('/v1/me/facts');
    assert.equal(linkedFacts.ageBand, link.identity.derived.ageBand);
    const resumed = await request('/v1/ai/conversations/' + waitingForAge.conversationId + '/messages', 'POST', { text: '80-89' });
    assert.equal(resumed.step.fact, 'ss33');
    assert.equal((await request('/v1/me/facts')).ageBand, linkedFacts.ageBand);
    confirmed.push('A conversation started before linking ThaID advances without overwriting the imported age');
    const afterThaId = await guidedQuestions(request);
    assert.deepEqual(Object.keys(afterThaId), ['ss33', 'disabilityCard']);
    confirmed.push('Synthetic ThaID age band skips the age question');

    const tangRat = tangRatFacts(fixture.sourceRecords.tangRat);
    await request('/v1/me/facts', 'PATCH', tangRat);
    const afterTangRat = await guidedQuestions(request);
    assert.deepEqual(Object.keys(afterTangRat), ['ss33']);
    confirmed.push('Synthetic disability-card status skips the disability-card question');

    const sample = fixture.sourceRecords.socialSecurity;
    const incomplete = socialSecurityFacts({ ...sample, contributionHistory: { ...sample.contributionHistory, complete: false, paidMonths: null } });
    await request('/v1/me/facts', 'PATCH', incomplete);
    const afterIncomplete = await guidedQuestions(request);
    assert.deepEqual(Object.keys(afterIncomplete), ['ss33']);
    assert.deepEqual(socialSecurityFacts({ ...sample, contributionHistory: { ...sample.contributionHistory, paidMonths: 0 } }), { ss33: false });
    confirmed.push('Missing history keeps the question open, unlike a known zero');

    const socialSecurity = socialSecurityFacts(sample);
    await request('/v1/me/facts', 'PATCH', socialSecurity);
    const afterSocialSecurity = await guidedQuestions(request);
    assert.deepEqual(Object.keys(afterSocialSecurity), []);
    const money = await request('/v1/money');
    assert.equal(money.items.find(item => item.id === 'unemployment')?.status, 'likely');
    confirmed.push('Synthetic contribution history skips the SSO question and supports preliminary screening');

    await request('/v1/me/consents', 'POST', consent(false), 201);
    const afterRevocation = await guidedQuestions(request);
    assert.deepEqual(Object.keys(afterRevocation), ['ageBand']);
    assert.equal((await request('/v1/me/gov-link')).status, 'not_connected');
    confirmed.push('Withdrawing government-data consent removes the mock ThaID age band');

    // Use the same config and persona loader as the mobile demo. ThaID stays disconnected.
    const taxRequest = requestFor(base, 'device-gov-prefill-demo-demo-dmytax');
    const config = await taxRequest('/v1/app-config');
    assert.equal(config.featureFlags.demo, true);
    const taxOptions = config.routes.me.sections.find(section => section.id === 'demo.dmytax').items;
    const loadPersona = (scenario, demoRequest) => {
      const { action, params } = scenario.onTap;
      const { path, method } = config.actions[action];
      return demoRequest(path.replace('{id}', params.id), method);
    };
    const [beforeOption, afterOption] = taxOptions;
    assert.equal((await loadPersona(beforeOption, taxRequest)).dataStatus, 'mock');
    const beforeDMyTax = await guidedQuestions(taxRequest);
    assert.deepEqual(Object.keys(beforeDMyTax), ['taxWithheld']);

    const taxSample = fixture.sourceRecords.dMyTax;
    const currentTaxYear = Number(taxSample.asOf.slice(0, 4));
    const previousYear = taxWithholdingFacts({ ...taxSample, taxYear: currentTaxYear - 1 }, currentTaxYear);
    await taxRequest('/v1/me/facts', 'PATCH', previousYear);
    const afterPreviousYear = await guidedQuestions(taxRequest);
    assert.deepEqual(afterPreviousYear, beforeDMyTax);
    confirmed.push('A previous-year tax record keeps the current-year question open');

    const zero = { ...taxSample, withholdingSummary: { complete: true, amountTHB: 0 } };
    const partial = { ...zero, withholdingSummary: { ...zero.withholdingSummary, complete: false } };
    await taxRequest('/v1/me/facts', 'PATCH', taxWithholdingFacts(partial, currentTaxYear));
    const afterPartialTaxRecord = await guidedQuestions(taxRequest);
    assert.deepEqual(afterPartialTaxRecord, beforeDMyTax);
    assert.deepEqual(taxWithholdingFacts(zero, currentTaxYear), { taxWithheld: false });
    confirmed.push('An incomplete tax record does not count as confirmed zero withholding');

    const expectedTaxFacts = taxWithholdingFacts(taxSample, currentTaxYear);
    const loadedTaxPersona = await loadPersona(afterOption, taxRequest);
    assert.equal(loadedTaxPersona.dataStatus, 'mock');
    const importedTaxFacts = { taxWithheld: (await taxRequest('/v1/me/facts')).taxWithheld };
    assert.deepEqual(importedTaxFacts, expectedTaxFacts);
    assert.equal((await request('/v1/me/facts')).taxWithheld, false);
    const afterDMyTax = await guidedQuestions(taxRequest);
    assert.deepEqual(Object.keys(afterDMyTax), []);
    const refund = (await taxRequest('/v1/money')).items.find(item => item.id === 'tax_refund');
    assert.equal(refund?.status, 'check');
    assert.equal(refund.amount.basis, 'none');
    confirmed.push('Current-year withholding skips the question and leaves the refund for verification');
    confirmed.push('Configured mobile demo actions use a separate profile');

    const profileRequest = requestFor(base, 'device-gov-prefill-demo-demo-gov-prefill');
    const [profileOption] = config.routes.me.sections.find(section => section.id === 'demo.gov-prefill').items;
    assert.equal(profileOption.onTap.then.route, 'me.profile');
    const principal = await request('/v1/me/profile');
    const principalFacts = await request('/v1/me/facts');
    const loadedProfile = await loadPersona(profileOption, profileRequest);
    assert.equal(loadedProfile.dataStatus, 'mock');
    assert.deepEqual(loadedProfile.sources.map(source => source.label), ['ThaID', 'ทางรัฐ', 'ประกันสังคม', 'D-MyTax']);
    assert.match(loadedProfile.sources[2].value, /8 จาก 15/);
    assert.match(loadedProfile.sources[3].value, /1,250 บาท/);
    const profile = await profileRequest('/v1/me/profile');
    assert.deepEqual(profile, loadedProfile.profile);
    assert.match(profile.displayName, /สมมติ/);
    const profileFacts = await profileRequest('/v1/me/facts');
    assert.deepEqual(profileFacts, {
      ...fixture.initialAnswers, ageBand: '60-69', disabilityCard: true, ss33: true, taxWithheld: true
    });
    assert.deepEqual(await guidedQuestions(profileRequest), {});
    assert.deepEqual(await request('/v1/me/profile'), principal);
    assert.deepEqual(await request('/v1/me/facts'), principalFacts);
    confirmed.push('All four synthetic sources appear on an isolated profile and supply the guided chat facts');

    console.log(JSON.stringify({
      dataStatus: fixture.dataStatus,
      factsFromSample: { ageBand: linkedFacts.ageBand, ...tangRat, ...socialSecurity },
      guidedQuestions: { baseline, afterThaId, afterTangRat, afterIncomplete, afterSocialSecurity, afterRevocation },
      dMyTax: {
        taxYear: currentTaxYear,
        withheldAmountTHB: taxSample.withholdingSummary.amountTHB,
        importedFacts: importedTaxFacts,
        guidedQuestions: { beforeDMyTax, afterPreviousYear, afterPartialTaxRecord, afterDMyTax },
        refundScreeningStatus: refund.status
      },
      profileDemo: { name: profile.displayName, sources: loadedProfile.sources },
      checksPassed: confirmed
    }, null, 2));
  } finally {
    server.close();
  }
}

runDemo().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
