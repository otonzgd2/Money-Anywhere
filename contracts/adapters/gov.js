// Government connection port (ThaID / Tang Rat). Hidden behind the govConnected feature flag.
// Only a mock adapter exists: it returns sample data labelled mock. A real adapter needs an agreement with
// the identity provider and the data owner, a DPIA, and production security (requirements section 9).
const crypto = require('crypto');

function createGovMock(govMock) {
  const pending = new Map(); // state -> deviceId
  return {
    provider: 'thaid_mock',
    start(deviceId) {
      const state = crypto.randomBytes(12).toString('hex');
      pending.set(state, deviceId);
      return { status: 'pending', authUrl: 'https://example.org/thaid-mock/authorize?state=' + state, state };
    },
    // A real adapter exchanges the code for a token and calls the data owner's API here. The mock answers like an
    // agency would for this person: a record only appears when the person's own answers fit it (requires / skipIf).
    finish(deviceId, state, code, facts = {}) {
      if (pending.get(state) !== deviceId || !code) return null;
      pending.delete(state);
      const fits = v => Object.entries(v.requires || {}).every(([k, x]) => facts[k] === x) && !Object.entries(v.skipIf || {}).some(([k, x]) => facts[k] === x);
      const data = Object.fromEntries(Object.entries(govMock).filter(([, v]) => fits(v)).map(([k, { requires, skipIf, ...v }]) => [k, { ...v, mock: true }]));
      return { status: 'connected', provider: 'thaid_mock', mock: true, connectedAt: new Date().toISOString(), data };
    }
  };
}
module.exports = { createGovMock };
