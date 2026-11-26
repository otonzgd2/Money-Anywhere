// Smoke test for docs/mockups/gov-services.html. Run: node docs/mockups/gov-services-smoke.js
// Needs jsdom; set JSDOM_PATH to a folder containing node_modules/jsdom if not installed locally.
// Expected results come from docs/design/gov-services-inventory.md section 12.
const path = require('path');
const fs = require('fs');
const base = process.env.JSDOM_PATH ? path.join(process.env.JSDOM_PATH, 'node_modules', 'jsdom') : 'jsdom';
const { JSDOM } = require(base);

const html = fs.readFileSync(path.join(__dirname, 'gov-services.html'), 'utf8');
const errors = [];
const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true,
  beforeParse(w) { w.open = () => null; w.addEventListener('error', e => errors.push(e.message)); } });
const w = dom.window, d = w.document;
const results = [];
const check = (name, ok) => results.push((ok ? 'PASS ' : 'FAIL ') + name);
const on = id => d.getElementById('v-' + id).classList.contains('on');
const click = sel => { const el = d.querySelector(sel); if (!el) throw new Error('missing ' + sel); el.click(); };
const run = (name, fn) => { try { fn(); } catch (e) { check(name + ' threw: ' + e.message, false); } };

setTimeout(() => {
  const GS = w.GS;
  const res = (pid, id) => { const p = GS.PERSONAS.find(x => x.id === pid); return GS.evalAll(Object.assign({}, p.f)).find(x => x.p.id === id); };

  run('data', () => {
    check('25 programs', GS.PROGRAMS.length === 25);
    check('10 life events', GS.EVENTS.length === 10);
    check('6 personas, all marked (สมมติ)', GS.PERSONAS.length === 6 && GS.PERSONAS.every(p => p.name.includes('(สมมติ)')));
    check('every office is mock', GS.OFFICES.every(o => o.mock));
    check('severance table 7y=240, 20y=400, 0.2y=0', GS.sevDays(7) === 240 && GS.sevDays(20) === 400 && GS.sevDays(0.2) === 0);
  });

  run('personas', () => {
    const g1 = res('g1', 'severance');
    check('g1 severance likely 120,000', g1.r === 'likely' && g1.once === 120000);
    check('g1 unemployment likely', res('g1', 'unemployment').r === 'likely');
    check('g1 pvd need', res('g1', 'pvd').r === 'need');
    check('g2 maternity 15,000', res('g2', 'sso_maternity').once === 15000);
    check('g2 sso_child 1,000/month', res('g2', 'sso_child').monthly === 1000);
    check('g3 old_age 600', res('g3', 'old_age').monthly === 600);
    check('g3 flood check, nsf unlikely', res('g3', 'flood_2569').r === 'check' && res('g3', 'nsf').r === 'unlikely');
    check('g4 nsf likely max 1,800/yr', res('g4', 'nsf').r === 'likely' && res('g4', 'nsf').yearlyMax === 1800);
    check('g5 funeral 50,000, heir insurance check', res('g5', 'sso_funeral').once === 50000 && res('g5', 'heir_insurance').r === 'check');
    check('g6 securities + dormant check', res('g6', 'lost_securities').r === 'check' && res('g6', 'dormant_account').r === 'check');
    check('no program gives verified', GS.PERSONAS.every(p => GS.evalAll(Object.assign({}, p.f)).every(x => x.r !== 'verified')));
    check('check/need results carry no amount', GS.PERSONAS.every(p => GS.evalAll(Object.assign({}, p.f)).filter(x => x.r !== 'likely').every(x => !x.monthly && !x.once)));
  });

  run('flows', () => {
    click('[data-p="g1"]');
    check('starts on home', on('home'));
    check('DEMO / MOCK pill', d.getElementById('pill').textContent.includes('DEMO / MOCK'));
    check('home shows 10 events', d.querySelectorAll('#events [data-event]').length === 10);
    check('home sum once includes 120,000', d.getElementById('sumOnce').textContent.includes('120,000'));
    click('[data-event="baby"]');
    check('event filters money list', on('money') && d.getElementById('moneyTitle').textContent.includes('มีลูก'));
    click('[data-tab="money"]');
    click('[data-open="severance"]');
    check('detail opens', on('detail') && d.getElementById('dTitle').textContent.includes('ม.118'));
    check('detail shows scam warning', d.getElementById('dBody').textContent.includes('OTP'));
    click('[data-start="severance"]');
    check('handoff sheet opens', d.getElementById('handoff').classList.contains('on'));
    click('#hoGo');
    check('return prompt opens', d.getElementById('returned').classList.contains('on'));
    click('[data-report="done"]');
    check('user report saved', w.GS.state.reports.severance === 'ยื่นแล้ว');
    click('[data-back]');
    check('back goes to money list', on('money'));

    click('[data-p="g3"]');
    check('g3 flood window alert', d.getElementById('windowAlert').textContent.includes('น้ำท่วม'));
    click('[data-tab="money"]');
    click('[data-open="flood_2569"]');
    check('g3 flood detail warns missing ThaID', d.getElementById('dBody').textContent.includes('ยังไม่มี'));
    click('[data-start="flood_2569"]');
    check('not ready goes to readiness', on('ready'));
    click('[data-task="hasThaid"]');
    check('task marks ThaID ready', w.GS.state.persona.f.hasThaid === true);

    click('[data-v="layoff"]');
    d.getElementById('lyYears').value = '3'; d.getElementById('lyYears').dispatchEvent(new w.Event('input'));
    d.getElementById('lyWage').value = '12000'; d.getElementById('lyWage').dispatchEvent(new w.Event('input'));
    check('layoff calc 3y x 12,000 = 72,000', d.getElementById('lyResult').textContent.includes('72,000'));

    click('[data-p="g5"]');
    click('[data-event="death"]');
    check('heir view lists funeral', on('heir') && d.getElementById('heirList').textContent.includes('ค่าทำศพ'));

    click('[data-tab="map"]');
    check('map shows 2 mock pins', d.querySelectorAll('#mapArea .pin').length === 2);
    click('#mapArea .pin');
    check('office info marked MOCK', d.getElementById('officeInfo').textContent.includes('MOCK'));
  });

  check('no runtime errors', errors.length === 0);
  const failed = results.filter(r => r.startsWith('FAIL'));
  console.log(results.join('\n'));
  if (errors.length) console.log('errors:\n' + errors.join('\n'));
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}, 50);
