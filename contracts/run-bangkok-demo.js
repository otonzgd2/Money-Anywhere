const { join } = require('node:path');
const { copyFileSync, mkdirSync, mkdtempSync, rmdirSync, statSync, unlinkSync } = require('node:fs');
const { createServer } = require('./mock-server');

// Port 8082 is forwarded as port 8080 on the Android demo emulator.
const port = Number(process.env.PORT ?? 8082);
const fixture = join(__dirname, '..', 'docs', 'entities', 'database-script', 'demo', 'catalogue.db');
const input = process.env.JOB_DB_FILE || fixture;
if (!statSync(input, { throwIfNoEntry: false })?.isFile()) {
  console.error('ไม่พบไฟล์ฐานข้อมูลประกาศงาน: ' + input);
  process.exit(1);
}

let jobDbFile = input;
let workingDirectory;
if (!process.env.JOB_DB_FILE) {
  const dataDirectory = join(__dirname, '.data');
  mkdirSync(dataDirectory, { recursive: true });
  workingDirectory = mkdtempSync(join(dataDirectory, 'bangkok-'));
  jobDbFile = join(workingDirectory, 'catalogue.db');
  copyFileSync(fixture, jobDbFile);
}

const server = createServer({
  jobDbFile,
  demo: true,
  live: false,
  autoJobSync: false,
  aiOptions: { baseUrl: '', apiKey: '' }
});

if (workingDirectory) {
  server.once('close', () => {
    unlinkSync(jobDbFile);
    rmdirSync(workingDirectory);
  });
}
process.once('SIGINT', () => server.close());
process.once('SIGTERM', () => server.close());

server.listen(port, '127.0.0.1', () => {
  console.log('Bangkok DEMO / MOCK API on http://127.0.0.1:' + server.address().port);
});
