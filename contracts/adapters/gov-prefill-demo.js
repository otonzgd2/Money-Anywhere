const fixture = require('../fixtures/gov-prefill-demo.json');
const { createGovMock } = require('./gov');
const { taxWithholdingFacts } = require('./demo-tax');

const govPrefillSourceIds = ['thaid', 'tangRat', 'socialSecurity', 'dMyTax'];

function tangRatFacts(record) {
  return record.disabilityCard?.status === 'active' ? { disabilityCard: true } : {};
}

function socialSecurityFacts(record) {
  const { contributionHistory: history } = record;
  if (record.coverageSectionAtExit !== 33 || history?.complete !== true || history.windowMonthsBeforeExit !== 15
      || !Number.isInteger(history.paidMonths) || history.paidMonths < 0 || history.paidMonths > 15) return {};
  return { ss33: history.paidMonths >= 6 };
}

function govPrefillPersona(thaidConfig, selectedSources = govPrefillSourceIds) {
  const { thaid, tangRat, socialSecurity, dMyTax } = fixture.sourceRecords;
  const selected = new Set(selectedSources);
  const facts = { ...fixture.initialAnswers };
  const sources = [];
  let profile = {};
  let identity;

  if (selected.has('thaid')) {
    const adapter = createGovMock({}, thaidConfig);
    const device = 'gov-prefill-persona';
    const { state } = adapter.start(device);
    const { identity: mock } = adapter.finish(device, state, 'demo-profile', { ageBand: '60-69' }, {}, thaid.asOf);
    const { displayName, ageBand, district, age } = mock.derived;
    profile = { displayName, district };
    identity = {
      dataStatus: mock.dataStatus, claimsVerified: mock.claimsVerified, scopes: mock.scopes,
      pidMasked: mock.pidMasked, claims: mock.claims, derived: mock.derived
    };
    facts.ageBand = ageBand;
    sources.push({ field: 'identity', label: 'ThaID', value: `อายุ ${age} ปี` });
  }
  if (selected.has('tangRat')) {
    Object.assign(facts, tangRatFacts(tangRat));
    sources.push({ field: 'disabilityCard', label: 'ทางรัฐ', value: 'มีบัตร' });
  }
  if (selected.has('socialSecurity')) {
    Object.assign(facts, socialSecurityFacts(socialSecurity));
    const { paidMonths, windowMonthsBeforeExit } = socialSecurity.contributionHistory;
    sources.push({ field: 'ss33', label: 'ประกันสังคม', value: `ม. ${socialSecurity.coverageSectionAtExit} · ส่งสมทบ ${paidMonths} จาก ${windowMonthsBeforeExit} เดือนก่อนออกงาน` });
  }
  if (selected.has('dMyTax')) {
    Object.assign(facts, taxWithholdingFacts(dMyTax, Number(dMyTax.asOf.slice(0, 4))));
    const amount = new Intl.NumberFormat('th-TH').format(dMyTax.withholdingSummary.amountTHB);
    sources.push({ field: 'taxWithheld', label: 'D-MyTax', value: `${amount} บาท · ปีภาษี ${dMyTax.taxYear + 543}` });
  }

  return { label: `โปรไฟล์เชื่อม ${sources.length} แหล่ง (DEMO)`, profile, identity, facts, sources, tasks: [] };
}

module.exports = { govPrefillSourceIds, govPrefillPersona, tangRatFacts, socialSecurityFacts };
