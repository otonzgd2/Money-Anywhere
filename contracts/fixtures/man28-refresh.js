const http = require('node:http');
const { once } = require('node:events');
const { sourceRecords } = require('./gov-prefill-demo.json');

const cacheExpiresAt = '2026-11-30';
const cachedTangRatCard = { ...sourceRecords.tangRat, expiresAt: cacheExpiresAt };
const lastValidInstant = Date.parse('2026-11-30T23:59:59+07:00');
const firstExpiredInstant = Date.parse('2026-12-01T00:00:00+07:00');

async function startTangRatError() {
  const requests = [];
  const server = http.createServer((req, res) => {
    if (req.method !== 'GET' || req.url !== '/disability-card') {
      res.writeHead(404).end();
      return;
    }
    requests.push({ method: req.method, path: req.url, status: 503 });
    res.writeHead(503, { 'Content-Type': 'application/json' })
      .end(JSON.stringify({ code: 'SERVICE_UNAVAILABLE' }));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return {
    endpoint: 'http://127.0.0.1:' + server.address().port + '/disability-card',
    requests,
    close: () => new Promise(resolve => server.close(resolve)),
  };
}

module.exports = { cachedTangRatCard, lastValidInstant, firstExpiredInstant, startTangRatError };
