// Run with node docs/mockups/smoke-test.js and jsdom installed.
// JSDOM_PATH can point to a separate directory containing node_modules/jsdom.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const jsdomPath = process.env.JSDOM_PATH
  ? path.join(process.env.JSDOM_PATH, 'node_modules', 'jsdom')
  : 'jsdom';
const { JSDOM, VirtualConsole } = require(jsdomPath);
const viewports = [];
const failures = [];
let passed = 0;

function openDemo(file = 'index.html', route = '') {
  const errors = [];
  const opened = [];
  const console = new VirtualConsole();
  console.on('jsdomError', error => errors.push(error.message));
  const { window } = new JSDOM(fs.readFileSync(path.join(__dirname, file), 'utf8'), {
    url: 'https://demo.example/' + file + route,
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    virtualConsole: console,
    beforeParse(w) { w.open = url => { opened.push(url); return null; }; },
  });
  viewports.push({ window, errors, file });
  const { document } = window;
  const node = selector => document.querySelector(selector);
  const content = selector => node(selector).textContent.trim();
  const click = selector => node(selector).click();
  const view = () => node('#screen').dataset.view;
  const evaluate = script => window.eval(script);
  const input = (selector, value, event = 'input') => {
    const element = node(selector);
    element.value = value;
    element.dispatchEvent(new window.Event(event, { bubbles: true }));
  };
  return { window, document, node, content, click, view, evaluate, input, opened };
}

async function check(name, run) {
  try {
    await run();
    passed += 1;
    console.log('PASS ' + name);
  } catch (error) {
    failures.push(name);
    console.error('FAIL ' + name + '\n' + error.message);
  }
}

async function waitFor(predicate, label) {
  const end = Date.now() + 3000;
  while (!predicate() && Date.now() < end) {
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.ok(predicate(), label);
}

async function main() {
  await check('fresh launch shows the new logo and connects through the four services', async () => {
    const page = openDemo();
    const { node, click, view, content, evaluate } = page;
    assert.equal(view(), 'startup');
    assert.equal(node('#startupSplash img').getAttribute('src'), 'assets/logo.svg');
    assert.ok(node('#tabs.hidden'));
    await waitFor(() => !node('#startupConnect').hidden, 'first provider');
    assert.match(content('.cn-h'), /ThaID/);
    click('.cn-primary');
    assert.ok(node('.cn-ring.cn-busy'));
    assert.ok(node('.cn-secondary').disabled);
    await waitFor(() => node('.cn-ring.cn-done'), 'connection succeeds');
    await waitFor(() => content('.cn-h').includes('ทางรัฐ'), 'second provider');
    click('.cn-secondary');
    assert.match(content('.cn-h'), /ประกันสังคม/);
    click('.cn-secondary');
    assert.match(content('.cn-h'), /D-MyTax/);
    click('.cn-secondary');
    assert.match(content('.cn-lead'), /1 จาก 4/);
    assert.ok(node('.cn-primary').disabled);
    click('#startTerms');
    click('.cn-primary');
    assert.match(content('#startupStatus'), /กำลังประเมินสิทธิ์และรายได้/);
    await waitFor(() => view() === 'opp', 'assessment opens opportunities');
    assert.equal(evaluate('onboardingChoices'), 'ynnn');
    assert.equal(evaluate('selectedAssessment.ageBand'), '60-69');
    assert.equal(evaluate('facts.ageBand'), undefined);
    assert.equal(evaluate('consent'), null);
    assert.match(content('#oppBody'), /600/);
    click('#tabs button:last-child');
    assert.match(content('#connectedAccounts'), /1 จาก 4/);
    assert.equal(node('.account-card[data-state=connected] strong').textContent, 'ThaID');
    evaluate('openStartup()');
    await waitFor(() => view() === 'opp', 'returning launch resumes from stored choices');
    assert.equal(evaluate('onboardingChoices'), 'ynnn');
  });

  await check('skip all leaves providers unconnected and opportunities accessible', async () => {
    const { node, click, view, evaluate, content } = openDemo();
    await waitFor(() => node('.cn-skipall'), 'skip button');
    click('.cn-skipall');
    assert.match(content('.cn-lead'), /ยังไม่ได้เชื่อมบริการ/);
    click('#startTerms');
    click('.cn-primary');
    await waitFor(() => view() === 'opp', 'browse without connections');
    assert.equal(evaluate('selectedAssessment'), null);
    assert.ok(node('#oppBody [data-item-id]'));
    click('#tabs button:last-child');
    assert.match(content('#connectedAccounts'), /0 จาก 4/);
  });

  await check('five root tabs, secondary routes, and guided consent for the first AI message', () => {
    const { document, node, click, view, content, input, evaluate } = openDemo('index.html', '#home-demo');
    assert.equal(view(), 'home');
    assert.deepEqual([...document.querySelectorAll('#tabs button')].map(tab => tab.textContent.trim()),
      ['หน้าแรก', 'คุยกับ AI', 'โอกาส', 'แผนของฉัน', 'บัญชี']);
    for (const [index, id] of ['home', 'chat', 'opp', 'plans', 'me'].entries()) {
      click('#tabs button:nth-child(' + (index + 1) + ')');
      assert.equal(view(), id);
      assert.equal(node('#tabs [aria-current=page]'), node('#tabs button:nth-child(' + (index + 1) + ')'));
    }
    click('#nav [data-id=quick]');
    assert.equal(view(), 'quick');
    assert.ok(node('#tabs.hidden'));
    assert.match(content('#quickBody'), /คุณอายุเท่าไหร่/);
    evaluate("qAns('60-69'); qAns('ไม่ได้รับ'); qAns('ยังไม่ได้รับ')");
    assert.match(content('#quickBody'), /600/);
    assert.equal(evaluate('facts.ageBand'), undefined);
    click('#v-quick .back');
    assert.equal(view(), 'me');
    click('#nav [data-id=plan]');
    input('#planIn', '10000');
    evaluate('runPlan()');
    assert.match(content('#planBody'), /รวมประมาณ/);
    click('#tabs button:first-child');
    input('#hIn', 'หางานใกล้บ้าน');
    evaluate('homePrimary()');
    assert.match(content('#dlg'), /ก่อนส่งข้อความถึง AI/);
    assert.equal(evaluate('consent'), null);
    click('#dlg button:last-child');
    assert.equal(view(), 'chat');
    assert.equal(evaluate('consent.ai'), true);
    assert.match(content('#achat'), /หางานใกล้บ้าน/);
    click('#nav [data-id=route]');
    assert.equal(view(), 'route');
    assert.ok(node('#routeBody button'));
  });

  await check('opportunity lanes, composable job filters, detail route and save state', () => {
    const { node, document, click, input, view, content, evaluate, opened } =
      openDemo('index.html', '#home-demo');
    click('#tabs button:nth-child(3)');
    assert.deepEqual([...document.querySelectorAll('#oppChips [data-lane]')].map(lane => lane.dataset.lane),
      ['ทั้งหมด', 'สิทธิ์และสวัสดิการ', 'หางาน', 'ขายสินค้า', 'อื่นๆ']);
    click('#oppChips [onclick="setGroup(\'job\')"]');
    node('#oppJobs').open = true;
    click('#filter-job_full');
    click('#filter-freelance');
    assert.ok(node('#oppJobs').open);
    assert.match(content('#oppJobs summary'), /\(2\)/);
    input('#oppDistrict', 'บางนา', 'change');
    assert.equal(document.querySelectorAll('#oppBody .opp-card').length, 1);
    click('#oppBody .opp-card');
    assert.equal(view(), 'oppd');
    assert.match(content('#oppdBody'), /บางนา/);
    click('#v-oppd .back');
    assert.equal(node('#oppDistrict').value, 'บางนา');
    assert.ok(node('#filter-freelance').checked);
    evaluate("openOpp('j3')");
    assert.match(content('#oppdBody'), /DEMO \/ MOCK/);
    click('#oppdBody [onclick="openJobDetails()"]');
    assert.equal(decodeURIComponent(opened[0]), 'job-application.html#title=พนักงานทำความสะอาดสำนักงาน');
    click('#oppdBody [onclick^=saveToPlan]');
    assert.ok(node('#modal.on'));
    click('#cAdult');
    click('#cAccept');
    assert.match(content('#oppdBody button:disabled'), /บันทึกแล้ว/);
    evaluate('saveToPlan({opportunityId:oppId})');
    assert.equal(evaluate("tasks.filter(task => task.opportunityId === 'j3').length"), 1);
    evaluate("openOpp('unknown')");
    assert.match(content('#oppdBody'), /ไม่พบรายการนี้หรือรายการหมดอายุแล้ว/);
  });

  await check('map requires confirmed coordinates and opens the same opportunity and district', () => {
    const { node, document, click, view, evaluate } = openDemo('index.html', '#home-demo');
    click('#tabs button:nth-child(3)');
    assert.ok(node('#oppFab.hidden'));
    assert.ok(node('#oppBody .opp-card'));
    evaluate("OPPS[0].location = {district:'บางนา',precision:'exact',coordinateSource:'database',lat:13.66,lng:100.60}; bump()");
    click('#oppFab');
    assert.equal(document.querySelectorAll('#map .pin').length, 1);
    click('#map .pin');
    click('#map [data-card=doe_smartjob]');
    assert.equal(view(), 'oppd');
    assert.equal(evaluate('oppId'), 'doe_smartjob');
    assert.equal(evaluate('oppDetailDistrict'), 'บางนา');
  });

  await check('plan list uses ten categories and four layouts with shared contact details', () => {
    const { node, document, click, view, content, evaluate } = openDemo('index.html', '#plan-demo');
    evaluate('openPlanSamples()');
    const plans = [...document.querySelectorAll('#plansBody [data-plan-id]')];
    assert.equal(plans.length, 10);
    assert.equal(new Set(plans.map(plan => plan.dataset.layout)).size, 4);
    for (const { dataset: { planId } } of plans) {
      click('[data-plan-id="' + planId + '"]');
      assert.equal(view(), 'task');
      assert.equal(document.activeElement.id, 'taskInfoHeading');
      const title = content('#taskInfoHeading');
      click('#taskContactButton');
      assert.ok(node('#modal.on'));
      assert.equal(content('#taskContactHeading'), title);
      assert.equal(document.activeElement.id, 'taskContactHeading');
      click('#msheet .cs-x');
      click('#v-task .back');
      assert.equal(view(), 'plans');
      assert.equal(document.activeElement.dataset.planId, planId);
    }
    evaluate("openTask(newTask({title:'ประกาศเดิม', opportunityId:'removed-listing', steps:['ตรวจสอบประกาศ']}).id)");
    click('#taskContactButton');
    assert.match(content('#taskContactBody'), /ยังไม่มีช่องทางติดต่อที่ตรวจสอบได้/);
  });

  await check('personal profile can be edited and connected ThaID fields are read-only', () => {
    const { node, click, content, input, evaluate } = openDemo('index.html', '#home-demo');
    click('#tabs button:last-child');
    click('.me-profile-link');
    click('#pViewActions button');
    assert.ok(node('#pAge') && node('#pDistrict'));
    assert.ok(node('#pSaveBtn').disabled);
    input('#pDisplayName', 'มาลี');
    assert.equal(node('#pSaveBtn').disabled, false);
    click('#pActions .out');
    assert.match(content('#dlg'), /ยังไม่ได้บันทึก/);
    click('#dlg button:first-child');
    click('#pSaveBtn');
    click('#cAdult');
    click('#cAccept');
    assert.equal(evaluate('profile.displayName'), 'มาลี');
    evaluate("saveMockConnections('ynyy'); refreshMockAssessment(); goTab('me')");
    assert.match(content('#connectedAccounts'), /3 จาก 4/);
    assert.match(content('#connectedAccounts'), /ข้อมูลจำลอง/);
    click('.me-profile-link');
    click('#pViewActions button');
    assert.match(content('#profileBody'), /นายสมศักดิ์ สมมติ/);
    assert.equal(node('#pAge'), null);
    assert.equal(node('#pDistrict'), null);
    evaluate("profileBack(); goTab('me'); disconnectThaid()");
    assert.match(content('#connectedAccounts'), /2 จาก 4/);
    click('.me-profile-link');
    click('#pViewActions button');
    assert.equal(node('#pDisplayName').value, 'มาลี');
  });

  await check('privacy, source labels, offline state and the shared assistant policy', () => {
    const { node, click, content, view, evaluate } = openDemo('index.html', '#home-demo');
    click('#tabs button:last-child');
    evaluate("go('privacy')");
    assert.equal(view(), 'privacy');
    assert.match(content('#privacyBody'), /ประกาศความเป็นส่วนตัว/);
    assert.match(content('#privacyBody'), /AI จำอะไรเกี่ยวกับฉัน/);
    click('#nav [data-id=sources]');
    assert.match(content('#sourcesBody'), /ข้อมูลจำลอง/);
    evaluate("goTab('me'); toggleOffline()");
    assert.match(content('#meBody'), /ลองใหม่/);
    assert.ok(node('#nav [data-id=P7]'));
    const { version, rules, inScope, redirect } = JSON.parse(fs.readFileSync(
      path.join(__dirname, '..', '..', 'contracts', 'fixtures', 'assistant-policy.json'), 'utf8'));
    assert.equal(JSON.stringify(evaluate('POLICY')), JSON.stringify({ version, rules, inScope, redirect }));
  });

  await check('standalone job form preserves encoded title and supports review, edit and mock send', () => {
    const title = 'งานพิมพ์ (A&B #2 + C%) <ตัวอย่าง>';
    const { node, window, content, click } = openDemo('job-application.html', '#title=' + encodeURIComponent(title));
    assert.equal(content('#job-title'), title);
    assert.equal(node('#job-title').children.length, 0);
    assert.ok(node('#sample-job-details').hidden);
    click('#fill-sample');
    node('#application').dispatchEvent(new window.Event('submit', { cancelable: true }));
    assert.equal(node('#review').hidden, false);
    assert.match(content('#check-resume'), /resume-demo\.txt/);
    click('#edit');
    assert.equal(node('#application').hidden, false);
    node('#application').dispatchEvent(new window.Event('submit', { cancelable: true }));
    click('#send');
    assert.equal(node('#confirmation').hidden, false);
    assert.match(content('#reference'), /^MOCK-/);
    click('#restart');
    assert.equal(node('#application').hidden, false);
    window.location.hash = '';
    window.dispatchEvent(new window.HashChangeEvent('hashchange'));
    assert.equal(content('#job-title'), 'เจ้าหน้าที่ธุรการ');
    assert.equal(node('#sample-job-details').hidden, false);
  });

  await check('all demo pages run without uncaught JS errors', () => {
    for (const { errors, file } of viewports) assert.deepEqual(errors, [], file);
  });
}

main().finally(() => {
  for (const { window } of viewports) window.close();
  console.log(passed + '/' + (passed + failures.length) + ' groups passed');
  if (failures.length) process.exitCode = 1;
});
