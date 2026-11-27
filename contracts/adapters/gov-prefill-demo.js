const fixture = require('../fixtures/gov-prefill-demo.json');
const { createGovMock } = require('./gov');
const { taxWithholdingFacts } = require('./demo-tax');

function tangRatFacts(record) {
  return record.disabilityCard?.status === 'active' ? { disabilityCard: true } : {};
}

function socialSecurityFacts(record) {
  const { contributionHistory: history } = record;
  if (record.coverageSectionAtExit !== 33 || history?.complete !== true || history.windowMonthsBeforeExit !== 15
      || !Number.isInteger(history.paidMonths) || history.paidMonths < 0 || history.paidMonths > 15) return {};
  return { ss33: history.paidMonths >= 6 };
}

function govPrefillPersona(thaidConfig) {
  const { thaid, tangRat, socialSecurity, dMyTax } = fixture.sourceRecords;
  const adapter = createGovMock({}, thaidConfig);
  const device = 'gov-prefill-persona';
  const { state } = adapter.start(device);
  const { identity } = adapter.finish(device, state, 'demo-profile', { ageBand: '60-69' }, {}, thaid.asOf);
  const { displayName, ageBand, district } = identity.derived;
  const { paidMonths, windowMonthsBeforeExit } = socialSecurity.contributionHistory;
  const amount = new Intl.NumberFormat('th-TH').format(dMyTax.withholdingSummary.amountTHB);

  return {
    label: 'โปรไฟล์เชื่อม 4 แหล่ง (DEMO)',
    profile: { displayName, district },
    identity: {
      dataStatus: identity.dataStatus, claimsVerified: identity.claimsVerified, scopes: identity.scopes,
      pidMasked: identity.pidMasked, claims: identity.claims, derived: identity.derived
    },
    facts: {
      ...fixture.initialAnswers,
      ageBand,
      ...tangRatFacts(tangRat),
      ...socialSecurityFacts(socialSecurity),
      ...taxWithholdingFacts(dMyTax, Number(dMyTax.asOf.slice(0, 4)))
    },
    sources: [
      { field: 'identity', label: 'ThaID', value: `อายุ ${identity.derived.age} ปี` },
      { field: 'disabilityCard', label: 'ทางรัฐ', value: 'มีบัตร' },
      { field: 'ss33', label: 'ประกันสังคม', value: `ม. ${socialSecurity.coverageSectionAtExit} · ส่งสมทบ ${paidMonths} จาก ${windowMonthsBeforeExit} เดือนก่อนออกงาน` },
      { field: 'taxWithheld', label: 'D-MyTax', value: `${amount} บาท · ปีภาษี ${dMyTax.taxYear + 543}` }
    ],
    tasks: []
  };
}

module.exports = { govPrefillPersona, tangRatFacts, socialSecurityFacts };
