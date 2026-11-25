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
    // PDPA consent
    w.eval("Object.assign(consent,{accepted:false,p:{core:true,location:false,ai:false,reminders:false},history:[]}); go('welcome'); withConsent(startChat)");
    check('consent sheet opens before first use', d.getElementById('msheet').innerHTML.includes('ก่อนเริ่ม'));
    check('accept is disabled until age is confirmed', d.querySelector('#msheet .btn[disabled]') !== null);
    w.eval("toggleDraft('ai'); draftC.adult=true; acceptConsent()");
    check('declining AI sends the user to manual form', on('manual') && w.eval('consent.p.ai') === false);
    w.eval("startChat()"); check('chat asks for AI consent when it was declined', d.getElementById('msheet').innerHTML.includes('ยังไม่ได้ยินยอมให้ใช้ AI'));
    w.eval("go('me'); manageConsent(); toggleConsent('reminders')");
    check('withdrawing a consent is recorded in history', w.eval('consent.history.length') === 2 && w.eval('consent.p.reminders') === false);
    w.eval("consent.p.location=false; go('map'); askLoc()"); check('no location consent goes straight to district picker', d.getElementById('msheet').innerHTML.includes('เลือกจุดค้นหา'));
    w.eval("showNotice()"); check('privacy notice lists user rights', d.getElementById('msheet').innerHTML.includes('สิทธิ์ของคุณ'));
    // Where is my money
    w.eval("setPersona('p1'); go('home')"); check('home shows money summary first', !!d.querySelector('#homeBody .mcard') && d.querySelector('#homeBody .mcard').textContent.includes('฿600'));
    w.eval("go('money')"); check('money page groups by status', d.getElementById('moneyBody').innerHTML.includes('น่าจะมีสิทธิ์'));
    check('ThaID hidden when the flag is off', !d.getElementById('moneyBody').innerHTML.includes('ThaID'));
    w.eval("openRoute('tax')"); check('route asks the one missing question', d.getElementById('routeBody').innerHTML.includes('เคยถูกหักภาษี'));
    w.eval("answerFact('taxWithheld','เคย')"); check('answer re-evaluates to check-amount', d.getElementById('routeBody').innerHTML.includes('ต้องเช็คยอดจริง') && d.getElementById('routeBody').innerHTML.includes('50 ทวิ'));
    w.eval("setPersona('p2'); openRoute('owed')"); check('owed wages computed from user input', d.getElementById('routeBody').innerHTML.includes('฿2,000'));
    w.eval("useChannel('owed',0)"); check('employer letter template', d.getElementById('msheet').innerHTML.includes('ยังไม่ได้รับค่าจ้าง'));
    w.eval("openRoute('old')"); check('not eligible shows reasons, no claim button', d.getElementById('routeBody').innerHTML.includes('ไม่น่าจะมีสิทธิ์') && !d.getElementById('routeBody').innerHTML.includes('เริ่มรับเงิน'));
    w.eval("openRoute('unemp'); startClaim('unemp')"); check('start claim creates a plan and opens tracker', on('tracker') && w.eval("tasks.some(t => t.src === 'money_unemp')"));
    w.eval("toggleGov(); go('money')"); check('ThaID entry appears when flag is on', d.getElementById('moneyBody').innerHTML.includes('เชื่อม ThaID'));
    w.eval("connectThaid()"); check('ThaID connect is clearly marked as demo', d.getElementById('msheet').innerHTML.includes('ยังไม่ได้เชื่อมระบบจริง'));
    w.eval("doConnect()"); check('connected shows verified items labelled mock', d.getElementById('moneyBody').innerHTML.includes('ยืนยันจากหน่วยงาน') && w.eval('consent.p.gov') === true);
    w.eval("go('me')"); check('me tab shows ThaID account', d.getElementById('meBody').innerHTML.includes('บัญชีที่เชื่อมต่อ'));
    w.eval("disconnectThaid(); toggleGov(); go('money')"); check('flag off hides ThaID again', !d.getElementById('moneyBody').innerHTML.includes('ThaID') && w.eval('gov.connected') === false);
    // AI assistant
    w.eval("setPersona('p2'); go('home')"); check('home offers the AI assistant', d.getElementById('homeBody').innerHTML.includes('ถาม AI เรื่องเงินของฉัน'));
    w.eval("consent.p.ai=false; startAssistant()"); check('assistant asks for AI consent first', d.getElementById('msheet').innerHTML.includes('ต้องยินยอมให้ใช้ AI'));
    w.eval("consent.p.ai=true; startAssistant()"); check('assistant greets', on('assistant') && d.getElementById('achat').textContent.includes('ถามเรื่องเงิน'));
    const ask = q => { const r = w.eval("aBot(aRespond(" + JSON.stringify(q) + ")); aRespond(" + JSON.stringify(q) + ")"); return r; };
    ask('เงินฉันอยู่ไหน'); check('assistant answers money from the app data', d.getElementById('achat').textContent.includes('฿6,000'));
    w.eval("aBot(aRespond('หางานใกล้บ้าน'))"); check('assistant proposes an action with confirm buttons', d.querySelectorAll('#achat .pact').length === 1);
    const before = w.eval('tasks.length'); w.eval("aDecide(Object.keys(aPending)[0], true)"); check('confirming the action adds to my plan', w.eval('tasks.length') === before + 1);
    w.eval("aBot(aRespond('ฉันไม่สะดวกเดินทางไกล'))"); check('assistant remembers a preference visibly', w.eval('aMemory.length') === 1 && !!d.querySelector('#achat .pmem'));
    w.eval("go('me'); showMemory()"); check('memory page lists it with delete', d.getElementById('msheet').innerHTML.includes('ไม่สะดวกเดินทางไกล'));
    w.eval("toggleConsent('ai')"); check('withdrawing AI consent deletes AI memory', w.eval('aMemory.length') === 0);
  });
  if (errors.length) results.push('FAIL window errors: ' + errors.join(' | '));
  console.log(results.join('\n'));
  console.log(results.some(r => r.startsWith('FAIL')) ? 'RESULT: FAIL' : 'RESULT: PASS');
  w.close();
}, 300);
