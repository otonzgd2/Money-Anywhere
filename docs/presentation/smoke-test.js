// Smoke test for api-pitch.html. Run: node docs/presentation/smoke-test.js (needs jsdom; JSDOM_PATH like docs/mockups/smoke-test.js)
const path = require('path'), fs = require('fs');
const base = process.env.JSDOM_PATH ? path.join(process.env.JSDOM_PATH, 'node_modules', 'jsdom') : 'jsdom';
const { JSDOM } = require(base);
const errors = [];
const dom = new JSDOM(fs.readFileSync(path.join(__dirname, 'api-pitch.html'), 'utf8'), { runScripts: 'dangerously', url: 'http://localhost/',
  beforeParse(w) { w.addEventListener('error', e => errors.push(e.message)); } });
setTimeout(() => {
  const d = dom.window.document, slides = [...d.querySelectorAll('.slide')];
  const onIdx = () => slides.findIndex(s => s.classList.contains('on'));
  const r = [];
  r.push(['16 slides', slides.length === 16]);
  r.push(['starts on slide 1', onIdx() === 0]);
  d.getElementById('next').click(); d.getElementById('next').click();
  r.push(['next moves to slide 3', onIdx() === 2]);
  d.getElementById('prev').click();
  r.push(['prev moves back', onIdx() === 1]);
  r.push(['has illustrations (svg >= 8)', d.querySelectorAll('svg').length >= 8]);
  r.push(['no runtime errors', errors.length === 0]);
  const out = r.map(([n, ok]) => (ok ? 'PASS ' : 'FAIL ') + n).join('\n') + '\n' + r.filter(x => x[1]).length + '/' + r.length + ' passed' + (errors.length ? '\n' + errors.join('\n') : '');
  console.log(out);
  process.exit(r.every(x => x[1]) ? 0 : 1);
}, 50);
