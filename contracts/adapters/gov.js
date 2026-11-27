// Government connection port (ThaID / Tang Rat). Hidden behind the govConnected feature flag.
// Only a mock adapter exists. It answers with the same claim names a real ThaID (DOPA) OAuth2/OIDC login returns
// (reference.json -> thaid.scopes), filled with synthetic values that fit the person's own answers.
// A real adapter needs an agreement with DOPA and the data owners, a DPIA, and production security (requirements 9).
//
// What ThaID gives: identity only (name, birthdate, gender, address, card dates). It does NOT give welfare or money
// records; those come from agency APIs (GDX, CATALOG_ONLY today), mocked here as `data` from reference.json -> govMock.
// The raw national ID (pid) never leaves this adapter: callers get pidMasked and a one-way pidHash.
const crypto = require('crypto');

const BKK = 'กรุงเทพมหานคร';
const ageOn = (birthdate, now) => {
  const b = new Date(birthdate + 'T00:00:00Z'), n = new Date(now);
  let a = n.getUTCFullYear() - b.getUTCFullYear();
  if (n.getUTCMonth() < b.getUTCMonth() || (n.getUTCMonth() === b.getUTCMonth() && n.getUTCDate() < b.getUTCDate())) a--;
  return a;
};
const bandOf = a => a >= 90 ? '90 ขึ้นไป' : a >= 80 ? '80-89' : a >= 70 ? '70-79' : a >= 60 ? '60-69' : 'ต่ำกว่า 60';

// Synthetic 13-digit number with a valid check digit, starting with 0 (not a normal Thai citizen range).
function syntheticPid(seed) {
  const h = crypto.createHash('sha256').update('thaid-mock:' + seed).digest('hex');
  const d = ('0' + [...h].filter(c => /\d/.test(c)).join('') + '000000000000').slice(0, 12).split('').map(Number);
  const sum = d.reduce((s, x, i) => s + x * (13 - i), 0);
  return d.join('') + ((11 - (sum % 11)) % 10);
}
const maskPid = pid => 'X-XXXX-XXXXX-' + pid.slice(10, 12) + '-' + pid.slice(12);

function createGovMock(govMock, thaid = {}) {
  const pending = new Map(); // state -> deviceId
  const people = thaid.people || {};
  const years = thaid.birthYearByAgeBand || {};

  function identityFor(deviceId, facts, profile, data, now) {
    // Keep the mock coherent: an unknown age follows the agency records (old-age record -> 60+).
    const band = facts.ageBand || thaid.defaultAgeBand || (data.old_age ? '60-69' : 'ต่ำกว่า 60');
    const p = band === 'ต่ำกว่า 60' ? people.default || {} : people.older || people.default || {};
    const birthdate = (years[band] || 1988) + '-04-12';
    const district = profile.registryDistrict || thaid.defaultDistrict || 'ปทุมวัน';
    const pid = syntheticPid(deviceId);
    const claims = {
      title: p.title, given_name: p.given_name, middle_name: '', family_name: p.family_name,
      name: p.title + p.given_name + ' ' + p.family_name,
      title_en: p.title_en, given_name_en: p.given_name_en, middle_name_en: '', family_name_en: p.family_name_en,
      name_en: p.title_en + ' ' + p.given_name_en + ' ' + p.family_name_en,
      birthdate, gender: p.gender,
      address: { formatted: p.street_address + ' เขต' + district + ' ' + BKK + ' ' + (thaid.postalCode || '10000'), street_address: p.street_address, locality: district, region: BKK, postal_code: thaid.postalCode || '10000', country: 'TH' },
      date_of_issuance: thaid.dateOfIssuance || '2023-01-10', date_of_expiry: thaid.dateOfExpiry || '2031-04-11',
      ial: thaid.ial || '2.3'
    };
    const age = ageOn(birthdate, now);
    return {
      dataStatus: 'mock', claimsVerified: thaid.claimsVerified === true, scopes: thaid.scopes || [],
      pidMasked: maskPid(pid), pidHash: crypto.createHash('sha256').update(pid).digest('hex').slice(0, 16),
      claims, derived: { age, ageBand: bandOf(age), district, displayName: claims.name }
    };
  }

  return {
    provider: 'thaid_mock',
    start(deviceId) {
      const state = crypto.randomBytes(12).toString('hex');
      pending.set(state, deviceId);
      const scope = encodeURIComponent((thaid.scopes || ['openid']).join(' '));
      return { status: 'pending', authUrl: 'https://example.org/thaid-mock/authorize?response_type=code&scope=' + scope + '&state=' + state, state };
    },
    // A real adapter exchanges the code for tokens at thaid.endpoints.token and reads the claims here. The mock answers
    // like an agency would for this person: a record only appears when the person's own answers fit it (requires / skipIf).
    finish(deviceId, state, code, facts = {}, profile = {}, now = Date.now()) {
      if (pending.get(state) !== deviceId || !code) return null;
      pending.delete(state);
      const fits = v => Object.entries(v.requires || {}).every(([k, x]) => facts[k] === x) && !Object.entries(v.skipIf || {}).some(([k, x]) => facts[k] === x);
      const data = Object.fromEntries(Object.entries(govMock).filter(([, v]) => fits(v)).map(([k, { requires, skipIf, ...v }]) => [k, { ...v, mock: true }]));
      const identity = identityFor(deviceId, facts, profile || {}, data, now);
      return { status: 'connected', provider: 'thaid_mock', mock: true, connectedAt: new Date(now).toISOString(), data, identity };
    }
  };
}
module.exports = { createGovMock, syntheticPid, maskPid, bandOf, ageOn };
