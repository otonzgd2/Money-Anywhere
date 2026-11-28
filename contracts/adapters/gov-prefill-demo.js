const fixture = require('../fixtures/gov-prefill-demo.json');
const { createGovMock } = require('./gov');
const { taxWithholdingFacts } = require('./demo-tax');

const govPrefillSourceIds = ['thaid', 'tangRat', 'socialSecurity', 'dMyTax'];

function tangRatFacts(record) {
  const status = record.disabilityCard?.status;
  if (status === 'active') return { disabilityCard: true };
  if (['inactive', 'expired', 'no_card'].includes(status)) return { disabilityCard: false };
  return {};
}

async function loadDemoTangRatCard(endpoint, fetchImpl) {
  try {
    const response = await fetchImpl(endpoint, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) return { status: 'failed', upstreamStatus: response.status };
    const record = await response.json();
    const day = /^\d{4}-\d{2}-\d{2}$/;
    const isDay = value => typeof value === 'string' && day.test(value)
      && new Date(value).toJSON()?.slice(0, 10) === value;
    if (!record || tangRatFacts(record).disabilityCard === undefined
      || !isDay(record.asOf) || !isDay(record.expiresAt) || record.expiresAt < record.asOf) {
      return { status: 'failed', upstreamStatus: response.status };
    }
    return { status: 'loaded', record };
  } catch {
    return { status: 'failed' };
  }
}

function socialSecurityFacts(record) {
  const { contributionHistory: history } = record;
  if (record.coverageSectionAtExit !== 33 || history?.complete !== true || history.windowMonthsBeforeExit !== 15
      || !Number.isInteger(history.paidMonths) || history.paidMonths < 0 || history.paidMonths > 15) return {};
  return { ss33: history.paidMonths >= 6 };
}

function govPrefillPersona(thaidConfig, selectedSources = govPrefillSourceIds, overrides = {}) {
  const sourceRecords = { ...fixture.sourceRecords, ...overrides };
  const { thaid, tangRat, socialSecurity, dMyTax } = sourceRecords;
  const selected = new Set(selectedSources);
  const facts = { ...fixture.initialAnswers };
  const sources = [];
  let profile = {};
  let identity;

  if (selected.has('thaid')) {
    const adapter = createGovMock({}, thaidConfig);
    const device = 'gov-prefill-persona';
    const { state } = adapter.start(device);
    const { identity: mock } = adapter.finish(device, state, 'demo-profile', { ageBand: thaid.ageBand || '60-69' },
      { registryDistrict: thaid.registryDistrict }, thaid.asOf);
    if (thaid.birthdate) mock.claims.birthdate = thaid.birthdate;
    if (thaid.ageBandOnly) {
      delete mock.claims.birthdate;
      delete mock.derived.age;
      mock.scopes = mock.scopes.filter(scope => scope !== 'birthdate');
    }
    const { displayName, ageBand, district, age } = mock.derived;
    profile = { displayName, district };
    identity = {
      dataStatus: mock.dataStatus, claimsVerified: mock.claimsVerified, scopes: mock.scopes,
      pidMasked: mock.pidMasked, claims: mock.claims, derived: mock.derived
    };
    facts.ageBand = ageBand;
    sources.push({ field: 'identity', label: 'ThaID', value: age === undefined ? `ช่วงอายุ ${ageBand}` : `อายุ ${age} ปี`, checkedAt: thaid.asOf });
  }
  if (selected.has('tangRat')) {
    Object.assign(facts, tangRatFacts(tangRat));
    const status = facts.disabilityCard;
    sources.push({ field: 'disabilityCard', label: 'ทางรัฐ', value: status === undefined ? 'ยังไม่มีข้อมูล' : status ? 'มีบัตรที่ใช้ได้' : 'ไม่มีบัตรที่ใช้ได้', checkedAt: tangRat.asOf });
  }
  if (selected.has('socialSecurity')) {
    Object.assign(facts, socialSecurityFacts(socialSecurity));
    const { paidMonths, windowMonthsBeforeExit } = socialSecurity.contributionHistory || {};
    const summary = paidMonths === undefined ? 'ยังไม่มีข้อมูลช่วงสมทบ' : 'ม. ' + socialSecurity.coverageSectionAtExit
      + ' · ส่งสมทบ ' + paidMonths + ' จาก ' + windowMonthsBeforeExit + ' เดือนก่อนออกงาน';
    sources.push({ field: 'ss33', label: 'ประกันสังคม', value: summary, checkedAt: socialSecurity.asOf });
  }
  if (selected.has('dMyTax')) {
    Object.assign(facts, taxWithholdingFacts(dMyTax, Number(dMyTax.asOf.slice(0, 4))));
    const amount = dMyTax.withholdingSummary?.amountTHB;
    const summary = Number.isFinite(amount) ? new Intl.NumberFormat('th-TH').format(amount) + ' บาท' : 'ยังไม่มีข้อมูลยอดหัก';
    sources.push({ field: 'taxWithheld', label: 'D-MyTax', value: summary + ' · ปีภาษี ' + (dMyTax.taxYear + 543), checkedAt: dMyTax.asOf });
  }

  const records = Object.fromEntries(selectedSources.map(id => [id, sourceRecords[id]]));
  return { label: `โปรไฟล์เชื่อม ${sources.length} แหล่ง (DEMO)`, profile, identity, facts, initialAnswers: fixture.initialAnswers, records, sources, tasks: [] };
}

module.exports = { govPrefillSourceIds, govPrefillPersona, tangRatFacts, socialSecurityFacts, loadDemoTangRatCard };
