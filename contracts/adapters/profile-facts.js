const { bandOf, ageOn } = require('./gov');
const { tangRatFacts, socialSecurityFacts } = require('./gov-prefill-demo');
const { taxWithholdingFacts } = require('./demo-tax');

function resolveProfileFacts(d, { day, taxYear = Number(day.slice(0, 4)), newExit = false, govIdentity, includeProvenance = false }) {
  const facts = { ...d.facts };
  const details = {};
  const conflicts = {};
  const age = d.gov?.applied?.ageBand;
  // Old snapshots stored the applied identity age in the self-reported facts.
  if (age && !age.separate && facts.ageBand === age.value) {
    if (age.prev === undefined) delete facts.ageBand;
    else facts.ageBand = age.prev;
  }
  const selfMeta = { ...d.answerDetails };
  if (d.taxAnswers?.[taxYear]) {
    const answer = d.taxAnswers[taxYear];
    facts.taxWithheld = answer.value;
    selfMeta.taxWithheld = answer;
  }
  if (selfMeta.taxWithheld?.taxYear !== undefined && selfMeta.taxWithheld.taxYear !== taxYear
    || selfMeta.taxWithheld?.taxYear === undefined && taxYear !== Number(day.slice(0, 4))) delete facts.taxWithheld;
  if (newExit && selfMeta.ss33?.newExit !== true) delete facts.ss33;
  if (includeProvenance) for (const [key, value] of Object.entries(facts)) {
    details[key] = { value, source: d.demoProfile && !selfMeta[key] ? 'demo_answers' : 'user',
      checkedAt: selfMeta[key]?.checkedAt || d.demoProfile?.checkedAt,
      ...(selfMeta[key]?.confirmedSource ? { confirmed: true } : {}),
      ...(key === 'taxWithheld' ? { taxYear } : {}) };
  }

  function use(record, source, values, context = {}, historical = false) {
    if (!record || record.tokenStatus === 'invalid' || (record.owner && record.owner !== d.demoProfile?.owner)) return;
    const stale = historical || record.effectiveAt > day || record.expiresAt < day;
    for (const [key, value] of Object.entries(values)) {
      if (value === undefined || (record.allowedFields && !record.allowedFields.includes(key))) continue;
      const checkedAt = record.checkedAt || record.asOf;
      const detail = { source, value, checkedAt, dataStatus: 'mock', ...context };
      // A confirmation applies to this version and value only.
      const stamp = JSON.stringify([source, checkedAt, value]);
      if (facts[key] !== undefined && selfMeta[key]?.confirmedSource === stamp) continue;
      if (stale) {
        if (includeProvenance && !details[key]) details[key] = { ...detail, status: 'stale' };
        continue;
      }
      if (facts[key] !== undefined && facts[key] !== value) {
        if (includeProvenance) details[key] = { ...detail, status: 'conflict', userValue: facts[key] };
        conflicts[key] = stamp;
        delete facts[key];
      } else {
        facts[key] = value;
        if (includeProvenance) details[key] = detail;
      }
    }
  }

  const demo = d.demoProfile?.records || {};
  const identity = govIdentity || d.demoProfile?.identity;
  if (identity) {
    const birthdate = identity.scopes?.includes('birthdate') ? identity.claims?.birthdate : undefined;
    const currentAge = birthdate ? ageOn(birthdate, day) : undefined;
    const idRecord = govIdentity ? { checkedAt: d.gov.connectedAt } : demo.thaid;
    use(idRecord, 'thaid', {
      ageBand: Number.isFinite(currentAge) ? bandOf(currentAge) : identity.derived?.ageBand,
      ageAtLeast55: Number.isFinite(currentAge) ? currentAge >= 55 : undefined,
      registryDistrict: identity.scopes?.includes('address') ? identity.claims?.address?.locality : undefined,
      registryProvince: identity.scopes?.includes('address') ? identity.claims?.address?.region : undefined,
    });
  }
  if (demo.tangRat) use(demo.tangRat, 'tangRat', {
    ...tangRatFacts(demo.tangRat), oldAgeGets: demo.tangRat.oldAgeGets, disabilityGets: demo.tangRat.disabilityGets,
  });
  if (demo.socialSecurity) {
    const record = demo.socialSecurity;
    if (!newExit) use(record, 'socialSecurity', socialSecurityFacts(record),
      { employmentEndedAt: record.employmentEndedAt, windowMonthsBeforeExit: record.contributionHistory?.windowMonthsBeforeExit });
    use(record, 'socialSecurity', {
      coverageEnded: record.coverageStatus === 'ended' ? true : record.coverageStatus === 'active' ? false : undefined,
      lifetimePaidMonths33And39: record.lifetimePaidMonths33And39,
    });
  }
  if (demo.dMyTax) {
    use(demo.dMyTax, 'dMyTax', taxWithholdingFacts(demo.dMyTax, taxYear), { taxYear });
    if (includeProvenance && !details.taxWithheld && demo.dMyTax.taxYear < taxYear) {
      use(demo.dMyTax, 'dMyTax', taxWithholdingFacts(demo.dMyTax, demo.dMyTax.taxYear), { taxYear: demo.dMyTax.taxYear }, true);
    }
  }
  return { facts, details, conflicts };
}

module.exports = { resolveProfileFacts };
