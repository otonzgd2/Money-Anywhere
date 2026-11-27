const { join } = require('node:path');
const { createServer } = require('./mock-server');

// Port 8082 is forwarded as port 8080 on the Android demo emulator.
const port = Number(process.env.PORT ?? 8082);
const server = createServer({
  jobDbFile: join(__dirname, '..', 'docs', 'entities', 'database-script', 'catalogue.db'),
  demo: true,
  live: false,
  autoJobSync: false,
  aiOptions: { baseUrl: '', apiKey: '' }
});

server.listen(port, '127.0.0.1', () => {
  console.log('Bangkok DEMO / MOCK API on http://127.0.0.1:' + server.address().port);
});
