const { join } = require('node:path');
const { statSync } = require('node:fs');
const { createServer } = require('./mock-server');

// Port 8082 is forwarded as port 8080 on the Android demo emulator.
const port = Number(process.env.PORT ?? 8082);
const jobDbFile = process.env.JOB_DB_FILE || join(__dirname, '..', 'docs', 'entities', 'database-script', 'demo', 'catalogue.db');
if (!statSync(jobDbFile, { throwIfNoEntry: false })?.isFile()) {
  console.error('ไม่พบไฟล์ฐานข้อมูลประกาศงาน: ' + jobDbFile);
  process.exit(1);
}
const server = createServer({
  jobDbFile,
  demo: true,
  live: false,
  autoJobSync: false,
  aiOptions: { baseUrl: '', apiKey: '' }
});

server.listen(port, '127.0.0.1', () => {
  console.log('Bangkok DEMO / MOCK API on http://127.0.0.1:' + server.address().port);
});
