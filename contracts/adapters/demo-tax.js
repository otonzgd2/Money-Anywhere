const fixture = require('../fixtures/gov-prefill-demo.json');

function taxWithholdingFacts(record, taxYear) {
  const { withholdingSummary: summary } = record;
  const amount = summary?.amountTHB;
  if (record.taxYear !== taxYear || !Number.isFinite(amount) || amount < 0) return {};
  if (amount > 0) return { taxWithheld: true };
  return summary.complete === true ? { taxWithheld: false } : {};
}

const taxSample = fixture.sourceRecords.dMyTax;
const taxYear = Number(taxSample.asOf.slice(0, 4));
const baseline = {
  ...fixture.initialAnswers,
  ageBand: 'ต่ำกว่า 60',
  work: 'ทำงานประจำ',
  disabilityCard: false
};

const samplePersona = {
  profile: {
    displayName: 'มาลี (สมมติ)',
    district: 'ปทุมวัน'
  },
  tasks: []
};
const taxDemoPersonas = {
  'dmytax-before': { ...samplePersona, label: 'D-MyTax: before import (DEMO)', facts: baseline },
  'dmytax-after': {
    ...samplePersona,
    label: 'D-MyTax: after import (DEMO)',
    facts: { ...baseline, ...taxWithholdingFacts(taxSample, taxYear) }
  }
};

module.exports = { taxDemoPersonas, taxWithholdingFacts };
