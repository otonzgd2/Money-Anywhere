// Runtime smoke test for the clickable mock. Run: node docs/mockups/smoke-test.js
// Needs jsdom; set JSDOM_PATH to a folder containing node_modules/jsdom if not installed locally.
const path = require('path');
const fs = require('fs');
const base = process.env.JSDOM_PATH ? path.join(process.env.JSDOM_PATH, 'node_modules', 'jsdom') : 'jsdom';
const { JSDOM } = require(base);

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const errors = [];
const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true,
  beforeParse(w) { w.open = () => null; w.addEventListener('error', e => errors.push(e.message)); } });
const w = dom.window, d = w.document;
// jsdom has no layout; give the map a size so renderMap draws pins.
Object.defineProperty(w.HTMLElement.prototype, 'clientWidth', { get() { return this.id === 'mapArea' ? 330 : 0; } });
Object.defineProperty(w.HTMLElement.prototype, 'clientHeight', { get() { return this.id === 'mapArea' ? 420 : 0; } });

const results = [];
const check = (name, ok) => results.push((ok ? 'PASS ' : 'FAIL ') + name);
const on = id => d.getElementById('v-' + id).classList.contains('on');
const run = (name, fn) => { try { fn(); } catch (e) { check(name + ' threw: ' + e.message, false); } };

setTimeout(() => {
  run('flows', () => {
    check('starts on welcome', on('welcome'));
    check('bottom nav has 4 tabs', d.querySelectorAll('#tabs > div').length === 4);
    w.eval("setPersona('p2')"); check('returning user lands on home', on('home'));
    check('home shows next step card', !!d.querySelector('#homeBody .next'));
    w.eval("go('results')"); check('results list renders items', d.querySelectorAll('#resBody .rcard').length > 0);
    check('scam hidden by default in list', !d.querySelector('#resBody .rcard.scam'));
    w.eval("chipClick('money')"); const nMoney = d.querySelectorAll('#resBody .rcard').length;
    w.eval("chipClick('all')"); const nAll = d.querySelectorAll('#resBody .rcard').length;
    check('category chip filters list', nMoney > 0 && nMoney < nAll);
    w.eval("setQ('ภาษี')"); check('search filters list', d.querySelectorAll('#resBody .rcard').length === 1);
    w.eval("setQ('')");
    w.eval("openFilter()"); check('filter sheet opens', d.getElementById('modal').classList.contains('on'));
    w.eval("setF('showScam', true)"); check('filter shows scam items', !!d.querySelector('#resBody .rcard.scam'));
    check('filter badge counts 1', d.querySelector('.fcnt').textContent === '1');
    w.eval("Object.assign(mapState, DEFAULT_F); closeModal(); refreshOpp()");
    w.eval("openItem('w1')"); check('list item opens detail in modal', d.getElementById('msheet').innerHTML.includes('เบี้ยยังชีพ'));
    w.eval("go('map')"); check('go() closes modal', !d.getElementById('modal').classList.contains('on') || d.getElementById('msheet').innerHTML.includes('ตำแหน่ง'));
    w.eval("setLoc('gps')"); check('map draws pins', d.querySelectorAll('.pin').length > 0);
    w.eval("openItem('j1')"); check('pin detail opens as map sheet', d.getElementById('sheet').classList.contains('open'));
    w.eval("zoomR(-1); zoomR(-1); zoomR(-1)"); check('radius 1 km', w.eval('mapState.r') === 1);
    w.eval("go('planner')"); check('planner shows all options', d.querySelectorAll('#planBody .plan').length === 5);
    w.eval("toggleCmp('pl1'); toggleCmp('pl2')"); check('compare bar appears at 2', !d.getElementById('cmpbar').classList.contains('hidden'));
    w.eval("openCompare()"); check('compare table renders', d.querySelectorAll('.cmpt th').length === 3);
    w.eval("go('manual'); document.getElementById('skillIn').value='ช่าง'; skillOpen()");
    check('skill search shows group', d.getElementById('skillDD').innerHTML.includes('ช่างและซ่อมแซม'));
    w.eval("document.getElementById('skillIn').value='นวดแผนไทย'; skillOpen()");
    check('skill offers custom add', !!d.querySelector('#skillDD .ddo.add'));
    w.eval("go('me')"); check('me tab renders', d.getElementById('meBody').innerHTML.includes('ลบข้อมูลทั้งหมด'));
    w.eval("go('tracker')"); check('tracker renders', d.querySelectorAll('#v-tracker .card').length > 0);
  });
  if (errors.length) results.push('FAIL window errors: ' + errors.join(' | '));
  console.log(results.join('\n'));
  console.log(results.some(r => r.startsWith('FAIL')) ? 'RESULT: FAIL' : 'RESULT: PASS');
  w.close();
}, 300);
