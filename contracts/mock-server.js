// Demo server that implements every operation in openapi.yaml (ADR-001: this grows into the Demo backend).
// Run: node mock-server.js   PORT=8080 by default. All variables are listed in ../.env.example.
//   LIVE=1            enable the Greenhouse/Lever startup pull when JOB_AUTO_SYNC=1
//   AI_BASE_URL, AI_API_KEY, AI_MODEL   OpenAI-compatible provider (otherwise rules)
//   AI_DAILY_LIMIT    AI calls per device per day before falling back to rules (0 = no limit)
//   AI_LOG_FILE       JSON lines log of AI calls (no prompt text)
//   DATA_FILE         JSON file that keeps device data across restarts (contract tests use memory)
//   JOB_DB_FILE       optional SQLite catalogue for scheduled job feeds
//   JOBICY_SYNC=1     register Jobicy for SQLite refreshes (requires JOB_DB_FILE)
//   JOB_AUTO_SYNC=1   enable startup and timed job refreshes (default: manual refresh only)
//   MOCK_JOB_FEED_FILE optional JSON snapshot for mock_doe (defaults to fixtures/opportunities-mock.json)
//   JOB_FEEDS_FILE    optional JSON configuration for scheduled CSV/JSON feeds (requires JOB_DB_FILE)
//   RETENTION_DAYS    devices not seen for this many days are archived or deleted (0 = off, Owner sets later)
//   RETENTION_MODE    archive (default: move profile + activity to ARCHIVE_FILE) or delete
//   ARCHIVE_FILE      JSON lines archive (default DATA_FILE + .archive.jsonl)
//   GOV_CONNECTED=1   show the hidden government (ThaID) mode, mock adapter only
//   DEMO_MODE=0       disable /v1/demo endpoints
//   INTEGRATION_KEY   key for /v1/integrations (defaults to "dev-only-key" locally)
//   GIT_COMMIT        commit reported by /v1/health (falls back to git rev-parse)
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');
const { URL } = require('url');
const { createAi } = require('./adapters/ai');
const { createAgent, rulesAgent: runRulesAgent, formatGoal, moneyGuide, moneySummaryQuery,
  unpaidPlansQuery, planStatusQuery, matchingMoneyPlans, planPaymentStatus } = require('./adapters/agent');
const { taxDemoPersonas } = require('./adapters/demo-tax');
const { govPrefillPersona, govPrefillSourceIds, loadDemoTangRatCard } = require('./adapters/gov-prefill-demo');
const sources = require('./adapters/sources');
const { createGeocoder } = require('./adapters/geocoder');
const { createNotifier } = require('./adapters/notifier');
const { createMoney } = require('./adapters/money');
const { createGovMock } = require('./adapters/gov');
const { createStore, packDevice, readDevices, archiveRecord, LAYOUT } = require('./adapters/store');
const { createJobs } = require('./adapters/jobs');
const { createGuard, thaiDigits } = require('./adapters/guard');
const { intentQuestion, intentOptions, benefitOptions, expense, jobRequest, monthly, lumpSum, otherSubject,
  self, shortAnswer, moneyText, topicRequests, parseGoal, bangkokDay, answerValue } = require('./adapters/chat-intent');
const { resolveProfileFacts } = require('./adapters/profile-facts');
const { openJobCatalogue, collapseJobListings, normalizeJobText, jobDedupKey, reviewScamSignals, REPORT_HIDE_REASON,
  BANGKOK_DEMO_PROVIDER, BANGKOK_INFO_PATH } = require('./adapters/job-catalogue');
const { createJobSync, createDemoJobSync, createJobPush, JobFeedError, DEMO_JOB_PROVIDER, JOB_REFRESH_MINUTES, WORK_MODES } = require('./adapters/job-sync');
const { readJobFileFeeds } = require('./adapters/job-file-feed');
const { JOBICY_SOURCE, createJobicyFeed } = require('./adapters/jobicy');

const DIR = __dirname;
const readJson = f => JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8'));
const nowIso = () => new Date().toISOString();
const daysAgo = d => d ? Math.max(0, Math.round((Date.now() - new Date(d)) / 864e5)) : undefined;
const HOURS = { 'ไม่เกิน 10': 8, '10-20': 15, '20-40': 30, 'เต็มเวลา': 40 };
const sideJob = opportunity => opportunity.category === 'job_part' || opportunity.category === 'freelance';
const regularJobStatement = /^(?:(?:ตอนนี้|ปัจจุบัน|ฉัน|ผม|หนู|เรา)\s*)*(?:มีงานประจำ|ทำงานประจำ)(?=อยู่|แล้ว|\s|ค่ะ|ครับ|$)/;
const moreJobRequest = /^(?:มีงาน(?:อื่น|อีก)|(?:ขอ|ช่วย)?(?:หา|ดู|แนะนำ)งานอื่น)(?:อีก)?(?:ได้ไหม|ไหม|มั้ย)?(?:\s*(?:ค่ะ|ครับ|คะ))?[?？]?$/;

function advertisedShiftHours(opportunity) {
  for (const condition of opportunity.conditions || []) {
    const duration = /(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?\s*(?:ชม\.?|ชั่วโมง)\s*\/\s*วัน/.exec(condition);
    if (duration) return Number(duration[2] || duration[1]);
    const shift = /(?:กะ|เวลา).*?(\d{1,2}):([0-5]\d)\s*[-–]\s*(\d{1,2}):([0-5]\d)/.exec(condition);
    if (shift && Number(shift[1]) < 24 && Number(shift[3]) < 24) {
      const start = Number(shift[1]) * 60 + Number(shift[2]);
      const end = Number(shift[3]) * 60 + Number(shift[4]);
      return ((end - start + 1440) % 1440) / 60 || undefined;
    }
  }
}
const OPPORTUNITY_DATA_MODES = new Map([['real', new Set(['live', 'curated', 'open_data'])], ['mock', new Set(['mock'])]]);
let COMMIT = process.env.GIT_COMMIT;
if (!COMMIT) { try { COMMIT = execSync('git rev-parse --short HEAD', { cwd: DIR, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { COMMIT = 'unknown'; } }

function km(a, b) {
  const R = 6371, t = x => x * Math.PI / 180, dLat = t(b.lat - a.lat), dLng = t(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(t(a.lat)) * Math.cos(t(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function bangkokDistrictPins(items) {
  const pins = new Map();
  for (const { location, provenance } of items) {
    if (provenance.provider !== BANGKOK_DEMO_PROVIDER || provenance.dataStatus !== 'mock' ||
        location.precision !== 'city' || !location.district ||
        !Number.isFinite(location.lat) || !Number.isFinite(location.lng)) continue;
    const { district, lat, lng } = location;
    const pin = pins.get(district);
    if (pin) pin.count++;
    else pins.set(district, { district, lat, lng, count: 1 });
  }
  return [...pins.values()];
}

function createServer(opts = {}) {
  const ref = readJson('fixtures/reference.json');
  const fx = readJson('fixtures/opportunities.json');
  const NOTICE = ref.privacyNotice;
  const appMode = opts.appMode ?? process.env.APP_MODE ?? 'demo';
  if (appMode !== 'demo' && appMode !== 'user') throw new Error('APP_MODE must be demo or user');
  const govOn = appMode === 'demo' && (opts.govConnected ?? (process.env.GOV_CONNECTED === '1'));
  const demoOn = appMode === 'demo' && (opts.demo ?? (process.env.DEMO_MODE !== '0'));
  const demoPersonas = demoOn ? { ...ref.demoPersonas, ...taxDemoPersonas, 'gov-prefill': govPrefillPersona(ref.thaid, undefined, opts.demoSourceRecords) } : {};
  const ai = opts.ai || createAi(opts.aiOptions || {});
  const agent = opts.agent || createAgent(opts.aiOptions || {});
  const geo = createGeocoder(ref.taxonomies.districts);
  const notifier = createNotifier({ debug: opts.debug });
  const money = createMoney(ref);
  const legacyGovFixtures = opts.legacyGovFixtures === true;
  const govAdapter = govOn ? createGovMock(legacyGovFixtures ? ref.govMock : {}, {
    ...ref.thaid, ...(legacyGovFixtures ? {} : { defaultAgeBand: '60-69' })
  }) : null;
  const integrationKey = opts.integrationKey || process.env.INTEGRATION_KEY || 'dev-only-key';
  const store = opts.store || createStore({ file: opts.dataFile });
  const envNum = (v, dflt) => v !== undefined ? +v : dflt;
  const aiDailyLimit = opts.aiDailyLimit !== undefined ? opts.aiDailyLimit : envNum(process.env.AI_DAILY_LIMIT, 50);
  const aiLogFile = opts.aiLogFile !== undefined ? opts.aiLogFile : process.env.AI_LOG_FILE;
  const retentionDays = opts.retentionDays !== undefined ? opts.retentionDays : envNum(process.env.RETENTION_DAYS, 0);
  const retentionMode = (opts.retentionMode || process.env.RETENTION_MODE || 'archive') === 'delete' ? 'delete' : 'archive';
  const refreshHours = envNum(process.env.SOURCE_REFRESH_HOURS, 1);
  const autoJobSync = opts.jobs !== false && (opts.autoJobSync ?? (process.env.JOB_AUTO_SYNC === '1'));
  const reportHide = opts.reportHideThreshold || 3;
  const rulesAi = createAi({ baseUrl: '', apiKey: '' }), rulesAgent = createAgent({ baseUrl: '', apiKey: '' });
  const guard = createGuard(readJson('fixtures/assistant-policy.json'));
  const startedAt = nowIso();
  const scam = text => reviewScamSignals(ref.scamRules, text);
  const purposeIds = NOTICE.purposes.filter(p => !p.feature || (p.feature === 'govConnected' && govOn)).map(p => p.id);

  // ---- shared catalogue ----
  const opps = new Map();
  const fileFeeds = readJobFileFeeds(opts.jobFeedsFile, opts.fetch);
  if (opts.jobicySync && !opts.jobDbFile) throw new Error('JOBICY_SYNC requires JOB_DB_FILE');
  if (fileFeeds.length && !opts.jobDbFile) throw new Error('JOB_FEEDS_FILE requires JOB_DB_FILE');
  const jobCatalogue = opts.jobDbFile ? openJobCatalogue(opts.jobDbFile, { includeBangkokDemo: demoOn }) : null;
  const syncOptions = {
    jobDbFile: opts.jobDbFile,
    categories: new Set(ref.taxonomies.categories.filter(category => category.mapGroup === 'job').map(category => category.id)),
    scamRules: ref.scamRules,
    clock: opts.jobClock
  };
  const sqliteRefreshJobs = new Map();
  if (jobCatalogue) {
    const mockJobRefresh = createDemoJobSync({
      ...syncOptions,
      feedFile: opts.mockJobFeedFile || path.join(DIR, 'fixtures/opportunities-mock.json'),
      source: ref.sources.find(source => source.provider === DEMO_JOB_PROVIDER)
    });
    sqliteRefreshJobs.set(DEMO_JOB_PROVIDER, { name: 'mock_job_refresh', everyMinutes: JOB_REFRESH_MINUTES, run: mockJobRefresh });
  }
  if (opts.jobicySync) {
    const jobicyRefresh = createJobSync({ ...syncOptions, source: JOBICY_SOURCE, load: createJobicyFeed(opts.fetch) });
    sqliteRefreshJobs.set(JOBICY_SOURCE.provider, { name: 'jobicy_refresh', everyMinutes: JOB_REFRESH_MINUTES, run: jobicyRefresh });
  }
  for (const feed of fileFeeds) {
    const { provider, mock, everyMinutes, minPollMinutes, load } = feed;
    const registered = jobCatalogue.source(provider);
    if (sqliteRefreshJobs.has(provider) || provider === JOBICY_SOURCE.provider || sources.providers.includes(provider)
        || (registered && (!registered.enabled || registered.direction !== 'pull' || (registered.data_status === 'mock') !== mock))
        || (!registered && !mock)) {
      jobCatalogue.close();
      throw new Error('แหล่ง ' + provider + ' ยังไม่พร้อมใช้เป็นฟีด CSV/JSON แบบ pull');
    }
    const source = {
      provider, direction: 'pull', dataStatus: registered?.data_status ?? 'mock', minPollMinutes,
      name: registered?.name ?? provider, kind: registered?.kind ?? 'ฟีด CSV/JSON จำลอง',
      attribution: registered?.attribution ?? 'DEMO / MOCK (' + provider + ')'
    };
    sqliteRefreshJobs.set(provider, { name: 'job_file_refresh_' + provider, everyMinutes, run: createJobSync({ ...syncOptions, source, load }) });
  }
  const pushJobs = jobCatalogue && createJobPush(syncOptions);
  const sqliteProviders = new Set([...(jobCatalogue?.providers() || []), ...sqliteRefreshJobs.keys()]);
  const isLegacy = opportunity => !sqliteProviders.has(opportunity.provenance.provider);
  const opportunityValues = () => {
    const legacy = [...opps.values()];
    if (!jobCatalogue) return legacy;
    const rank = opportunity => fixtureOrder.get(opportunity.id) ?? fixtureOrder.size;
    return legacy.filter(isLegacy).concat(jobCatalogue.all()).sort((a, b) => rank(a) - rank(b));
  };
  const findOpportunity = id => {
    const legacy = opps.get(id);
    if (legacy && isLegacy(legacy)) return legacy;
    return jobCatalogue?.get(id);
  };
  const fresh = o => ({ ...o, provenance: { ...o.provenance, ageDays: daysAgo(o.provenance.updatedAt) } });
  function opportunityResponse(opportunity, req) {
    if (opportunity.provenance.provider !== BANGKOK_DEMO_PROVIDER || opportunity.provenance.dataStatus !== 'mock') return opportunity;
    const protocol = req.socket.encrypted || req.headers['x-forwarded-proto'] === 'https' ? 'https:' : 'http:';
    const base = URL.parse(protocol + '//' + req.headers.host);
    if (!base || !req.headers.host) return opportunity;
    const sourceUrl = new URL(BANGKOK_INFO_PATH, base.origin);
    sourceUrl.searchParams.set('id', opportunity.id);
    return { ...opportunity, provenance: { ...opportunity.provenance, sourceUrl: sourceUrl.href } };
  }
  const withoutCoordinateSource = ({ coordinateSource, ...location }) => location;
  const reports = [], hiddenByReports = new Set();
  // A10: the same listing from two sources is kept once (first source wins). Key = title + organisation, ignoring
  // spacing, punctuation and bracketed notes.
  function upsert(provider, dataStatus, attribution, input) {
    const id = provider + '_' + input.externalId, key = jobDedupKey(input);
    const legacyDuplicate = [...opps.values()].find(o => isLegacy(o) && o.provenance.provider !== provider && jobDedupKey(o) === key);
    const duplicate = legacyDuplicate || jobCatalogue?.findDuplicate(key, provider);
    if (duplicate) return { id: duplicate.id, merged: true };
    const reasons = scam(input.title + ' ' + (input.conditions || []).join(' ') + ' ' + (input.suspiciousText || ''));
    if (hiddenByReports.has(id)) reasons.push(REPORT_HIDE_REASON);
    opps.set(id, {
      id, title: input.title, organization: input.organization, category: input.category, mapGroup: input.mapGroup,
      location: input.location ? withoutCoordinateSource(input.location) : { precision: 'none' },
      locations: input.locations?.map(withoutCoordinateSource),
      description: input.description, contacts: input.contacts, status: input.status,
      summary: input.summary, availability: input.availability, checkedAt: input.checkedAt, documents: input.documents,
      claim: input.claim, job: input.job, income: input.income, grant: input.grant,
      money: input.money, conditions: input.conditions || [],
      provenance: { provider, dataStatus, sourceUrl: input.sourceUrl, updatedAt: input.updatedAt, expiresAt: input.expiresAt, fetchedAt: nowIso(), ageDays: daysAgo(input.updatedAt), attribution },
      suspicious: reasons.length > 0, suspiciousReasons: reasons, checklistTemplateId: input.category,
      skills: Array.isArray(input.skills) && input.skills.length ? input.skills : undefined, forOlder: input.forOlder || undefined
    });
    return { id, merged: false };
  }
  fx.items.forEach(r => upsert('mock', 'mock', 'DEMO / MOCK', {
    externalId: r.id.replace(/^mock_/, ''), title: r.title, organization: r.organization, category: r.category, mapGroup: r.mapGroup,
    location: r.dxKm === undefined ? { precision: 'none' } : { precision: 'exact', text: 'ที่อยู่ตัวอย่าง (สมมติ)', lat: +(fx.center.lat - r.dyKm * 0.009).toFixed(6), lng: +(fx.center.lng + r.dxKm * 0.00926).toFixed(6) },
    money: r.money, conditions: r.conditions, sourceUrl: 'https://example.org/demo/' + r.id, updatedAt: new Date(Date.now() - r.ageDays * 864e5).toISOString(), suspiciousText: r.suspiciousText, skills: r.skills
  }));
  // Broad DEMO catalogue standing in for government and private APIs we cannot connect to yet
  // (fixtures/opportunities-mock.json, generated). On with MOCK_CATALOGUE=1 (the Demo .env); contract tests turn
  // it on for one server only, so counts in the other tests stay stable.
  const moreMock = opts.moreMock !== undefined ? opts.moreMock : process.env.MOCK_CATALOGUE === '1';
  const demoFixture = (moreMock || jobCatalogue) && fs.existsSync(path.join(__dirname, 'fixtures/opportunities-mock.json'))
    ? readJson('fixtures/opportunities-mock.json').items : [];
  // Preserve the fixture order for ties in search and for page cursors with the SQLite overlay.
  const fixtureOrder = new Map([...opps.keys(), ...demoFixture.map(r => r.provider + '_' + r.externalId)].map((id, index) => [id, index]));
  if (moreMock) {
    demoFixture.filter(r => !sqliteProviders.has(r.provider)).forEach(r => upsert(r.provider, 'mock', 'DEMO / MOCK (' + r.provider + ')', {
      ...r, sourceUrl: 'https://example.org/mock/' + r.provider + '/' + r.externalId, updatedAt: new Date(Date.now() - r.ageDays * 864e5).toISOString()
    }));
  }
  // Official services with real links (job centre, job fairs, free training), checked by hand. Not mock.
  (fx.official || []).forEach(r => upsert('official', 'curated', 'เว็บไซต์หน่วยงานราชการ (ตรวจลิงก์ ' + r.checkedAt + ')', {
    externalId: r.id, title: r.title, organization: r.organization, category: r.category, mapGroup: r.mapGroup,
    location: { precision: 'none', text: 'ออนไลน์ หรือสำนักงานใกล้บ้าน' }, money: r.money, conditions: r.conditions,
    sourceUrl: r.sourceUrl, checkedAt: r.checkedAt, updatedAt: new Date(r.checkedAt).toISOString()
  }));
  const srcState = ref.sources.map(s => ({ provider: s.provider, name: s.name, kind: s.kind, attribution: s.attribution,
    direction: s.url ? 'pull' : s.provider === 'curated' ? 'push' : 'static', state: s.url ? 'idle' : 'static',
    itemCount: [...opps.values()].filter(o => o.provenance.provider === s.provider).length }));
  const sourceReferences = readJson('fixtures/thailand-job-sources.json');
  const allSourceStates = () => {
    const states = new Map([...srcState.filter(s => !sqliteProviders.has(s.provider)), ...(jobCatalogue?.sources() || [])]
      .map(source => [source.provider, source]));
    for (const ref of sourceReferences) {
      const source = states.get(ref.provider);
      states.set(ref.provider, source ? { ...source, websiteUrl: ref.websiteUrl } : {
        ...ref, kind: ref.accessMode === 'link' ? 'ลิงก์ไปยังแหล่งต้นทาง' : 'ข้อมูลอ้างอิงแหล่ง',
        direction: 'static', state: 'static', itemCount: 0
      });
    }
    return [...states.values()];
  };
  async function refresh(which) {
    await Promise.all(sources.providers.filter(p => which === 'all' || p === which).map(async p => {
      const st = srcState.find(s => s.provider === p); st.state = 'loading';
      try {
        const r = await sources.pull(p, opts.fetch);
        for (const [k, o] of opps) if (o.provenance.provider === p) opps.delete(k);
        r.items.forEach(i => upsert(p, 'live', st.attribution, i));
        Object.assign(st, { state: 'ok', itemCount: r.items.length, lastFetchedAt: nowIso(), error: undefined });
      } catch (e) { Object.assign(st, { state: 'failed', error: e.name === 'AbortError' ? 'timeout' : e.message }); }
    }));
  }
  if (opts.live && autoJobSync) void refresh('all');

  // ---- per-device state ----
  const devices = new Map();
  const dev = id => {
    if (!devices.has(id)) devices.set(id, { profile: null, facts: {}, settings: { largeText: false }, consents: [], tasks: [], events: [], sessions: {}, idem: new Map(), memory: [], conversations: {}, gov: { status: 'not_connected' }, docsReady: {}, seq: 1, lastSeenAt: nowIso() });
    return devices.get(id);
  };

  // ---- persistence (B1): load once, save after every successful write ----
  // Layout v2: each device is split into collections (identity / profile / activity / runtime), see adapters/store.js.
  const snapshot = () => ({ version: LAYOUT, appMode, savedAt: nowIso(), devices: [...devices].map(([id, d]) => packDevice(id, d)), ingested: [...opps.values()].filter(o => !['mock', 'live'].includes(o.provenance.dataStatus)),
    reports, hiddenByReports: [...hiddenByReports], reminders: notifier.all() });
  const persist = () => { try { store.save(snapshot()); } catch (e) { console.error('store: save failed: ' + e.message); } };
  const saved = store.load();
  if (saved) {
    if ((saved.appMode ?? 'demo') !== appMode) throw new Error('DATA_FILE belongs to a different APP_MODE');
    readDevices(saved).forEach(([id, d]) => devices.set(id, d));
    (saved.ingested || []).forEach(o => opps.set(o.id, o));
    reports.push(...(saved.reports || [])); (saved.hiddenByReports || []).forEach(x => hiddenByReports.add(x));
    notifier.restore(saved.reminders);
    for (const o of saved.ingested || []) if (!srcState.some(s => s.provider === o.provenance.provider))
      srcState.push({ provider: o.provenance.provider, name: o.provenance.provider, kind: 'ส่งเข้าผ่าน Integrations', attribution: o.provenance.attribution, direction: 'push', state: 'ok' });
    srcState.forEach(s => { s.itemCount = [...opps.values()].filter(o => o.provenance.provider === s.provider).length; });
  }

  // ---- AI budget (B4) and call log (B5) ----
  const hashDevice = id => crypto.createHash('sha256').update(String(id)).digest('hex').slice(0, 12);
  function aiFor(d) {
    if ((ai.provider === 'rules' && agent.provider === 'rules') || !(aiDailyLimit > 0)) return { ai, agent };
    const day = nowIso().slice(0, 10);
    if (!d.aiUse || d.aiUse.day !== day) d.aiUse = { day, n: 0 };
    if (d.aiUse.n >= aiDailyLimit) return { ai: rulesAi, agent: rulesAgent, limited: true };
    d.aiUse.n++; return { ai, agent };
  }
  function logAi(device, kind, out) {
    if (!aiLogFile || !out) return;
    try {
      fs.mkdirSync(path.dirname(path.resolve(aiLogFile)), { recursive: true });
      fs.appendFileSync(aiLogFile, JSON.stringify({ at: nowIso(), kind, device: hashDevice(device), provider: kind === 'agent' ? agent.provider : ai.provider, aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId }) + '\n');
    } catch (e) { console.error('ai log: ' + e.message); }
  }
  const curConsent = d => d.consents[d.consents.length - 1];
  const assistantRequests = new WeakMap();
  function cancelAssistantRequests(d) {
    for (const conversation of Object.values(d.conversations)) assistantRequests.get(conversation)?.abort();
  }
  const has = (d, p) => { const c = curConsent(d); return !!(c && c.noticeVersion === NOTICE.version && c.purposes[p] === true); };
  const E = (status, code, message, extra = {}) => [status, { code, message, status, retryable: status >= 500, ...extra }];
  const need = (d, p) => has(d, p) ? null : E(403, 'CONSENT_REQUIRED', 'ต้องได้รับความยินยอมเรื่องนี้ก่อน', { missingFields: [p] });
  const govData = d => legacyGovFixtures && d.gov.status === 'connected' && has(d, 'gov') ? d.gov.data : null;
  const govIdentity = d => d.gov.status === 'connected' && has(d, 'gov') ? d.gov.identity || null : null;
  const day = () => bangkokDay(opts.clock ? opts.clock() : Date.now());
  const profileFacts = (d, context = {}) => resolveProfileFacts(d, { day: day(), govIdentity: govIdentity(d), ...context });
  const effectiveFacts = d => profileFacts(d).facts;
  const profileIdentityKeys = ['displayName', 'district', 'lat', 'lng'];
  const registryFactKeys = new Set(['ageBand', 'ageAtLeast55', 'registryDistrict', 'registryProvince']);
  function appliedIdentity(d, identity) {
    const profile = d.profile || {};
    return Object.fromEntries(['displayName', 'district', 'ageBand']
      .filter(key => identity.derived[key] !== undefined && !(key === 'ageBand' ? d.facts : profile)[key])
      .map(key => [key, { value: identity.derived[key], separate: true }]));
  }
  // Preserve the profile read shape for older clients. The fallback is projected
  // from ThaID on read, while the stored profile belongs to the user.
  function profileWithIdentity(d) {
    const profile = { ...d.profile };
    const applied = d.gov.applied || {};
    if (applied.displayName?.separate) profile.displayName = applied.displayName.value;
    if (applied.district?.separate) {
      profile.district = applied.district.value;
      const point = geo.geocode(profile.district);
      if (point && typeof profile.lat !== 'number') {
        profile.lat = point.lat;
        profile.lng = point.lng;
      }
    }
    return profile;
  }
  function dropGov(d) {
    if (d.gov.status === 'connected') cancelAssistantRequests(d);
    const a = (d.gov && d.gov.applied) || {}, p = d.profile;
    // Older records copied the fallback into the user's stored profile.
    if (p && a.displayName && !a.displayName.separate && p.displayName === a.displayName.value) delete p.displayName;
    if (p && a.district && !a.district.separate && p.district === a.district.value) { delete p.district; delete p.lat; delete p.lng; }
    if (a.ageBand && !a.ageBand.separate && d.facts.ageBand === a.ageBand.value) { const f = { ...d.facts }; if (a.ageBand.prev === undefined) delete f.ageBand; else f.ageBand = a.ageBand.prev; d.facts = f; }
    d.gov = { status: 'not_connected' };
  }
  const govOut = d => ({ status: d.gov.status, provider: govAdapter.provider, mock: true, connectedAt: d.gov.connectedAt, ...(govIdentity(d) ? { identity: { ...d.gov.identity, applied: Object.keys(d.gov.applied || {}) } } : {}) });
  const taskOut = t => ({ id: t.id, opportunityId: t.opportunityId, moneyId: t.moneyId, districtCode: t.districtCode,
    title: t.title, steps: t.steps, doneCount: t.doneCount, status: t.status, reportedBy: 'user', dueText: t.dueText, blockReason: t.blockReason, outcome: t.outcome });
  function searchPoint(d, q) {
    if (q.has('lat') && q.has('lng')) return { lat: +q.get('lat'), lng: +q.get('lng') };
    const profile = d && govIdentity(d) ? profileWithIdentity(d) : d?.profile;
    return typeof profile?.lat === 'number' ? { lat: profile.lat, lng: profile.lng } : fx.center;
  }
  const opportunityLocations = o => o.locations?.length ? o.locations : [o.location];
  const hasMapLocation = o => o.provenance.dataStatus !== 'mock'
    && opportunityLocations(o).some(l => l.coordinateSource === 'database');
  const districtName = value => normalizeJobText(value).replace(/^เขต/, '');
  const bangkokProvinces = new Set(['กรุงเทพมหานคร', 'กรุงเทพฯ', 'กรุงเทพ', 'กทม', 'bangkok'].map(normalizeJobText));
  // Longest names first, so a district name inside a longer one is not matched twice.
  const bangkokDistricts = readJson('fixtures/bangkok-district-map.json').districts
    .map(({ name, lat, lng }) => ({ name, key: districtName(name), lat, lng }))
    .sort((a, b) => b.key.length - a.key.length);
  function districtsIn(text) {
    let rest = normalizeJobText(text);
    const found = [];
    for (const district of bangkokDistricts) {
      if (!rest.includes(district.key)) continue;
      found.push(district);
      rest = rest.split(district.key).join(' ');
    }
    return found;
  }
  const homeDistrict = d => {
    const key = districtName((d && govIdentity(d) ? profileWithIdentity(d) : d?.profile)?.district);
    return key ? bangkokDistricts.find(district => district.key === key) : undefined;
  };

  // ---- shared services (used by HTTP routes and by the AI agent) ----
  function search(d, q) {
    const c = searchPoint(d, q), r = q.has('radiusKm') ? +q.get('radiusKm') : 5, group = q.get('group') || 'all', cat = q.get('category'), text = (q.get('q') || '').trim();
    const onlyMoney = q.get('onlyMoney') === 'true', showSus = q.get('showSuspicious') === 'true', sort = q.get('sort') || 'near';
    const key = { near: o => o.location.distanceKm ?? 1e9, money: o => -(o.money.max ?? -1), fresh: o => o.provenance.ageDays ?? 1e9 }[sort];
    if (!key) return null;
    const dataStatuses = OPPORTUNITY_DATA_MODES.get(q.get('dataMode'));
    const bangkok = q.get('area') === 'bangkok';
    const province = normalizeJobText(q.get('province')), district = districtName(q.get('district')), districtCode = q.get('districtCode');
    const skill = normalizeJobText(q.get('skill')), workMode = q.get('workMode');
    let xs = opportunityValues().filter(o => !dataStatuses || dataStatuses.has(o.provenance.dataStatus)).map(fresh).map(o => o.location.precision === 'exact' ? { ...o, location: { ...o.location, distanceKm: +km(c, o.location).toFixed(2) } } : o)
      .filter(o => group === 'all' || o.mapGroup === group).filter(o => !cat || o.category === cat)
      .filter(o => !text || (o.title + ' ' + (o.organization || '')).includes(text))
      .filter(o => !onlyMoney || o.money.basis !== 'none')
      .filter(o => !province || normalizeJobText(o.location.province) === province)
      .filter(o => !bangkok || opportunityLocations(o).some(l => !l.province || bangkokProvinces.has(normalizeJobText(l.province))))
      .filter(o => !(district || districtCode) || opportunityLocations(o).some(l => {
        if (bangkok && l.province && !bangkokProvinces.has(normalizeJobText(l.province))) return false;
        if (districtCode && l.districtCode != null) return String(l.districtCode) === districtCode;
        return district && districtName(l.districtName ?? l.district) === district;
      }))
      .filter(o => !workMode || (o.location.workMode ?? (o.location.isRemote ? 'remote' : undefined)) === workMode)
      .filter(o => !skill || o.skills?.some(value => normalizeJobText(value) === skill))
      .filter(o => bangkok || o.location.precision !== 'exact' || o.location.distanceKm <= r)
      .filter(o => o.provenance.linkStatus !== 'broken' && !['closed', 'expired'].includes(o.status) && !['closed', 'expired'].includes(o.availability))
      .filter(o => !o.provenance.expiresAt || new Date(o.provenance.expiresAt) > new Date());
    const hidden = showSus ? 0 : xs.filter(o => o.suspicious).length;
    if (!showSus) xs = xs.filter(o => !o.suspicious);
    if (jobCatalogue) xs = collapseJobListings(xs);
    const suggestions = [];
    if (!xs.length) {
      if (r < 10) suggestions.push({ type: 'expand_radius', label: 'ขยายระยะเป็น 10 กม.', radiusKm: 10 });
      if (text) suggestions.push({ type: 'clear_query', label: 'ล้างคำค้น' });
      if (group !== 'all') suggestions.push({ type: 'all_groups', label: 'ดูทุกหมวด' });
      if (onlyMoney) suggestions.push({ type: 'include_unknown_money', label: 'รวมรายการที่ไม่ระบุเงิน' });
    }
    return { xs: xs.sort((a, b) => key(a) - key(b)), hidden, suggestions };
  }
  const svc = {
    createTask(d, body) {
      const gate = need(d, 'core'); if (gate) return gate;
      const districtCode = body?.districtCode;
      if (districtCode !== undefined && (typeof districtCode !== 'string' || !/^\d{4}$/.test(districtCode)))
        return E(422, 'VALIDATION', 'districtCode ต้องเป็นรหัสเขต 4 หลัก');
      if (body && body.moneyId) {
        const steps = money.claimSteps(body.moneyId); if (!steps) return E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้');
        const ex = d.tasks.find(t => t.moneyId === body.moneyId); if (ex) return [201, taskOut(ex)];
        const p = money.programs.find(x => x.id === body.moneyId), ready = d.docsReady[body.moneyId] || [];
        const t = { id: 't' + d.seq++, moneyId: body.moneyId, districtCode, title: p.title, steps, doneCount: ready.length === p.docs.length ? 1 : 0, status: 'active' };
        d.tasks.push(t); return [201, taskOut(t)];
      }
      const o = body && findOpportunity(body.opportunityId); if (!o) return E(404, 'NOT_FOUND', 'ไม่พบโอกาสที่จะบันทึก');
      const ex = d.tasks.find(t => t.opportunityId === o.id); if (ex) return [201, taskOut(ex)];
      const steps = ref.checklists[o.checklistTemplateId] || ['ติดต่อผู้ประกาศ', 'ดำเนินการตามขั้นตอนที่ต้นทาง'];
      const t = { id: 't' + d.seq++, opportunityId: o.id, districtCode, title: o.title, steps, doneCount: 0, status: 'active' };
      d.tasks.push(t); return [201, taskOut(t)];
    },
    taskEvent(d, device, id, body, key) {
      const gate = need(d, 'core'); if (gate) return gate;
      const t = d.tasks.find(x => x.id === id); if (!t) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้');
      const types = ['complete_step', 'undo', 'block', 'snooze', 'resume', 'report_outcome'];
      if (!body || !types.includes(body.type)) return E(422, 'VALIDATION', 'type ไม่ถูกต้อง');
      if (key && d.idem.has(key)) return d.idem.get(key);
      const before = { doneCount: t.doneCount, status: t.status, dueText: t.dueText, blockReason: t.blockReason, outcome: t.outcome };
      if (body.type === 'complete_step') {
        if (t.status === 'finished') return E(409, 'CONFLICT', 'งานนี้ครบทุกขั้นแล้ว');
        t.doneCount++; t.status = t.doneCount >= t.steps.length ? 'finished' : 'active'; t.blockReason = undefined;
      } else if (body.type === 'undo') {
        const last = [...d.events].reverse().find(e => e.taskId === t.id && !e.undone && e.type !== 'undo');
        if (!last) return E(409, 'CONFLICT', 'ไม่มีอะไรให้เลิกทำ');
        Object.assign(t, last.before); last.undone = true;
      } else if (body.type === 'block') { t.status = 'blocked'; t.blockReason = body.reason || 'other'; }
      else if (body.type === 'snooze') {
        const until = body.until || 'tomorrow';
        if (until === 'never') { notifier.cancel(device, t.id); t.dueText = undefined; }
        else {
          const days = { tomorrow: 1, in_3_days: 3, next_week: 7 }[until]; if (!days) return E(422, 'VALIDATION', 'until ไม่ถูกต้อง');
          t.status = 'snoozed'; t.dueText = { tomorrow: 'เตือนพรุ่งนี้', in_3_days: 'เตือนอีก 3 วัน', next_week: 'เตือนสัปดาห์หน้า' }[until];
          if (has(d, 'reminders')) notifier.schedule(device, t.id, new Date(Date.now() + days * 864e5).toISOString());
        }
      } else if (body.type === 'resume') { t.status = t.doneCount >= t.steps.length ? 'finished' : 'active'; t.blockReason = undefined; t.dueText = undefined; notifier.cancel(device, t.id); }
      else if (body.type === 'report_outcome') {
        if (!['received', 'not_received', 'rejected', 'other'].includes(body.result)) return E(422, 'VALIDATION', 'result ไม่ถูกต้อง');
        if (body.amountReported !== undefined && (typeof body.amountReported !== 'number' || body.amountReported < 0)) return E(422, 'VALIDATION', 'amountReported ต้องเป็นตัวเลข');
        t.outcome = { result: body.result, amountReported: body.amountReported, reportedBy: 'user', at: nowIso() };
        if (body.result === 'received') { t.doneCount = t.steps.length; t.status = 'finished'; }
      }
      d.events.push({ id: 'ev' + d.seq++, taskId: t.id, type: body.type, before, at: nowIso() });
      const result = [201, taskOut(t)]; if (key) d.idem.set(key, result); return result;
    },
    patchFacts(d, body, context = {}) {
      const gate = need(d, 'core'); if (gate) return gate;
      const { errors, clean } = money.validateFacts(body);
      if (errors.length) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง', { missingFields: errors });
      d.answerDetails ||= {};
      for (const [key, value] of Object.entries(clean)) {
        if (context.readOnly?.has(key)) continue;
        const taxYear = key === 'taxWithheld' ? context.taxYear || Number(day().slice(0, 4)) : undefined;
        if (key === 'ageBand' && d.gov.applied?.ageBand && !d.gov.applied.ageBand.separate) d.gov.applied.ageBand.separate = true;
        if (value === undefined) {
          delete d.facts[key];
          delete d.answerDetails[key];
          if (taxYear && d.taxAnswers) delete d.taxAnswers[taxYear];
        } else {
          d.facts[key] = value;
          d.answerDetails[key] = { checkedAt: nowIso(),
            ...(taxYear ? { taxYear } : {}),
            ...(key === 'ss33' && context.newExit ? { newExit: true } : {}),
            ...(context.conflicts?.[key] ? { confirmedSource: context.conflicts[key] } : {}) };
          if (taxYear) {
            d.taxAnswers ||= {};
            d.taxAnswers[taxYear] = { ...d.answerDetails[key], value };
          }
        }
      }
      return [200, effectiveFacts(d)];
    }
  };

  // ---- agent tools: what the AI may see and do for this one user ----
  function agentTools(d, device, context = {}) {
    const facts = () => profileFacts(d, context).facts;
    const savedMoneyPlan = moneyId => {
      const task = moneyId && d.tasks.find(t => t.moneyId === moneyId);
      return task ? taskOut(task) : undefined;
    };
    return {
      get_money_overview: { mode: 'read', description: 'สรุปเงินที่ผู้ใช้อาจได้ และสถานะแต่ละรายการ', parameters: { type: 'object', properties: {} }, run: () => money.list(facts(), govData(d)) },
      get_money_route: { mode: 'read', description: 'ขั้นตอนรับเงินของรายการหนึ่ง พร้อมแผนเดิมและผลที่ผู้ใช้แจ้งถ้ามี', parameters: { type: 'object', properties: { moneyId: { type: 'string' } }, required: ['moneyId'] },
        run: a => { const route = money.route(a.moneyId, facts(), govData(d), d.docsReady[a.moneyId]); return route ? { ...route, savedPlan: savedMoneyPlan(a.moneyId) } : { error: 'not found' }; } },
      search_opportunities: { mode: 'read', description: 'ค้นหาโอกาสใกล้ผู้ใช้', parameters: { type: 'object', properties: { q: { type: 'string' }, group: { type: 'string' }, limit: { type: 'integer' } } },
        run: a => {
          const params = extra => {
            const q = new URLSearchParams(extra);
            if (a.q) q.set('q', a.q);
            if (context.sideJob || a.group) q.set('group', context.sideJob ? 'job' : a.group);
            if (context.remote) q.set('workMode', 'remote');
            return q;
          };
          const area = context.jobArea;
          let xs;
          if (!area) xs = search(d, params()).xs;
          else if (!area.district) xs = search(d, params({ area: 'bangkok' })).xs;
          else {
            // The radius only filters pinned listings, so district-level listings count as near only inside the district.
            const { name, lat, lng } = area.district;
            const pinned = search(d, params({ lat, lng })).xs.filter(o => o.location.precision === 'exact');
            const inDistrict = search(d, params({ area: 'bangkok', district: name })).xs;
            xs = [...new Map([...pinned, ...inDistrict].map(o => [o.id, o])).values()];
          }
          const items = xs.filter(o => (!context.sideJob || (sideJob(o) &&
            (context.spareHours === undefined || (advertisedShiftHours(o) ?? 0) <= context.spareHours)))
            && !context.excludedJobs?.has(o.id))
            .slice(0, Math.min(5, a.limit || 3));
          return { items: items.map(o => ({ id: o.id, title: o.title, money: o.money, district: o.location.district, distanceKm: o.location.distanceKm, dataStatus: o.provenance.dataStatus })) };
        } },
      plan_income_goal: { mode: 'read', description: 'วางแผนให้ได้รายได้ต่อเดือนตามเป้าที่ผู้ใช้บอก (บาท) จากเงินสวัสดิการที่น่าจะได้ งาน และทักษะของผู้ใช้ ใช้ตัวเลขจากผลนี้เท่านั้น',
        parameters: { type: 'object', properties: { target: { type: 'integer', description: 'บาทต่อเดือน' } }, required: ['target'] }, run: a => Number.isInteger(a.target) && a.target > 0 && a.target <= 1000000 ? goalPlan(d, a.target, context) : { error: 'invalid monthly goal' } },
      list_tasks: { mode: 'read', description: 'งานในแผนของผู้ใช้', parameters: { type: 'object', properties: {} }, run: () => ({ items: d.tasks.map(taskOut) }) },
      get_profile: { mode: 'read', description: 'ทักษะ เวลาว่าง และข้อจำกัดสำหรับหางาน', parameters: { type: 'object', properties: {} }, run: () => { const { skills, hoursPerWeek, constraints } = d.profile || {}; return { skills, hoursPerWeek, constraints }; } },
      save_income_goal: { mode: 'confirm', description: 'บันทึกเป้ารายเดือนที่ผู้ใช้เลือก',
        label: a => 'บันทึกเป้ารายเดือน ' + moneyText(a.target) + ' บาท',
        exec: a => { d.profile = { ...d.profile, incomeGoalPerMonth: a.target }; return [200, d.profile]; } },
      create_task: { mode: 'confirm', description: 'บันทึกโอกาสหรือรายการเงินเข้าแผน (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { opportunityId: { type: 'string' }, moneyId: { type: 'string' } } },
        findSaved: a => savedMoneyPlan(a.moneyId),
        label: a => 'บันทึกเข้าแผนของฉัน: ' + ((a.moneyId && (money.programs.find(p => p.id === a.moneyId) || {}).title) || (findOpportunity(a.opportunityId) || {}).title || 'รายการนี้'), exec: a => svc.createTask(d, a) },
      snooze_task: { mode: 'confirm', description: 'ตั้งเตือนงานภายหลัง (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { taskId: { type: 'string' }, until: { type: 'string', enum: ['tomorrow', 'in_3_days', 'next_week'] } }, required: ['taskId'] },
        label: a => 'เตือนงานนี้ ' + ({ tomorrow: 'พรุ่งนี้', in_3_days: 'อีก 3 วัน', next_week: 'สัปดาห์หน้า' }[a.until] || 'พรุ่งนี้'), exec: a => svc.taskEvent(d, device, a.taskId, { type: 'snooze', until: a.until || 'tomorrow' }) },
      complete_step: { mode: 'confirm', description: 'บันทึกว่าทำขั้นปัจจุบันเสร็จ (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { taskId: { type: 'string' } }, required: ['taskId'] },
        label: () => 'บันทึกว่าทำขั้นนี้เสร็จแล้ว', exec: a => svc.taskEvent(d, device, a.taskId, { type: 'complete_step' }) },
      update_facts: { mode: 'confirm', description: 'บันทึกข้อมูลสถานการณ์ที่ผู้ใช้บอก (ต้องให้ผู้ใช้ยืนยัน)', parameters: { type: 'object', properties: { facts: { type: 'object' } }, required: ['facts'] },
        label: a => 'บันทึกคำตอบ: ' + Object.entries(a.facts || {}).map(([k, v]) => ((ref.facts[k] || {}).short || k) + ' = ' + (v === true ? 'ใช่' : v === false ? 'ไม่ใช่' : v)).join(', '), exec: a => svc.patchFacts(d, a.facts) },
      remember: { mode: 'memory', description: 'จำความชอบหรือข้อจำกัดสั้นๆ ของผู้ใช้', parameters: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } }
    };
  }

  const R = [];
  const on = (method, pattern, fn, o = {}) => R.push({ method, re: new RegExp('^' + pattern.replace(/\{(\w+)\}/g, '(?<$1>[^/]+)') + '$'), fn, ...o });

  // System + config + privacy
  on('GET', '/v1/health', () => [200, { status: 'ok', version: readJson('package.json').version, commit: COMMIT, startedAt, ai: { provider: ai.provider, agent: agent.provider }, features: { govConnected: govOn, demo: demoOn }, sources: allSourceStates().map(s => ({ provider: s.provider, state: s.state })),
    store: store.kind, storeLayout: LAYOUT, retention: { days: retentionDays, mode: retentionMode }, notifier: notifier.kind, aiDailyLimit, jobs: jobs.state }], { public: true });
  on('GET', '/v1/app-config', ({ req }) => {
    const cfg = readJson('app-config.sample.json');
    cfg.mode = appMode;
    if (appMode === 'user') cfg.governmentConnections = { thaid: 'approval_required', tangRat: 'access_required' };
    cfg.featureFlags = { ...cfg.featureFlags, govConnected: govOn, demo: demoOn }; cfg.noticeVersion = NOTICE.version;
    const tag = '"' + cfg.configVersion + '-' + NOTICE.version + '-' + appMode + (govOn ? '-gov' : '') + (demoOn ? '-demo' : '') + '"';
    return req.headers['if-none-match'] === tag ? [304] : [200, cfg, { ETag: tag, 'Cache-Control': 'no-cache' }];
  }, { public: true });
  on('GET', '/v1/taxonomies', () => [200, { ...ref.taxonomies, facts: ref.facts }], { public: true });
  on('GET', '/v1/privacy/notice', () => [200, { version: NOTICE.version, note: NOTICE.note, sections: NOTICE.sections, purposes: NOTICE.purposes.filter(p => purposeIds.includes(p.id)).map(({ feature, ...p }) => p) }], { public: true });

  // Me
  on('DELETE', '/v1/me', ({ d, device }) => { cancelAssistantRequests(d); devices.delete(device); notifier.cancel(device); return [204]; });
  on('GET', '/v1/me/profile', ({ d }) => {
    const { details } = profileFacts(d, { includeProvenance: true });
    if (!d.profile && !Object.keys(details).length) return E(404, 'NOT_FOUND', 'ยังไม่มีโปรไฟล์');
    const linked = govIdentity(d);
    return [200, { ...(linked ? profileWithIdentity(d) : d.profile), factProvenance: details,
      ...(d.demoProfile ? { dataStatus: 'mock' } : {}),
      ...(linked ? { fromGov: Object.keys(d.gov.applied || {}) } : {}) }];
  });
  on('PUT', '/v1/me/profile', ({ d, body }) => {
    const gate = need(d, 'core'); if (gate) return gate;
    if (!body || typeof body !== 'object' || Array.isArray(body)) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง');
    const allowed = ['displayName', 'district', 'lat', 'lng', 'skills', 'hoursPerWeek', 'incomeGoalPerMonth', 'goals', 'constraints'];
    const p = Object.fromEntries(Object.entries(body).filter(([k]) => allowed.includes(k)));
    if (govIdentity(d)) {
      for (const key of profileIdentityKeys) {
        if (Object.hasOwn(d.profile || {}, key)) p[key] = d.profile[key];
        else delete p[key];
      }
    }
    if (p.district && typeof p.lat !== 'number') { const g = geo.geocode(p.district); if (g) { p.lat = g.lat; p.lng = g.lng; } }
    d.profile = p; return [200, p];
  });
  on('POST', '/v1/me/consents', ({ d, device, body }) => {
    if (!body || typeof body.purposes !== 'object' || body.purposes === null) return E(400, 'VALIDATION', 'ต้องมี noticeVersion, ageConfirmed และ purposes');
    if (body.noticeVersion !== NOTICE.version) return E(422, 'VALIDATION', 'ประกาศที่ยอมรับไม่ใช่ฉบับปัจจุบัน', { missingFields: ['noticeVersion'] });
    if (body.ageConfirmed !== true) return E(422, 'VALIDATION', 'ต้องยืนยันอายุ 20 ปีขึ้นไป หรือผู้ปกครองยินยอม', { missingFields: ['ageConfirmed'] });
    if (body.purposes.core !== true) return E(422, 'VALIDATION', 'ข้อจำเป็นต้องยินยอม ถ้าไม่ต้องการ ให้ลบข้อมูลทั้งหมด', { missingFields: ['purposes.core'] });
    const prev = curConsent(d);
    const purposes = Object.fromEntries(purposeIds.map(id => [id, body.purposes[id] === true]));
    const c = { id: 'c' + d.seq++, noticeVersion: body.noticeVersion, ageConfirmed: true, purposes, at: nowIso() };
    d.consents.push(c);
    // Withdrawals take effect immediately.
    if (prev && prev.purposes.ai && !purposes.ai) { cancelAssistantRequests(d); d.memory = d.memory.filter(m => m.source !== 'ai'); d.conversations = {}; }
    if (!purposes.reminders) notifier.cancel(device);
    if (!purposes.gov && d.gov.status !== 'not_connected') dropGov(d);
    return [201, c];
  });
  on('GET', '/v1/me/consents', ({ d }) => { const c = curConsent(d); return [200, { current: c, noticeVersion: NOTICE.version, needsRenewal: !c || c.noticeVersion !== NOTICE.version, items: d.consents }]; });
  on('GET', '/v1/me/settings', ({ d }) => [200, d.settings]);
  on('PATCH', '/v1/me/settings', ({ d, body }) => {
    d.settings = { ...d.settings, ...Object.fromEntries(Object.entries(body || {}).filter(([k, v]) => k === 'largeText' && typeof v === 'boolean')) };
    return [200, d.settings];
  });
  on('GET', '/v1/me/facts', ({ d }) => [200, effectiveFacts(d)]);
  on('PATCH', '/v1/me/facts', ({ d, body }) => svc.patchFacts(d, body,
    { readOnly: govIdentity(d) ? registryFactKeys : undefined }));
  on('GET', '/v1/me/memory', ({ d }) => [200, { items: d.memory }]);
  on('POST', '/v1/me/memory', ({ d, body }) => {
    const gate = need(d, 'core'); if (gate) return gate;
    const text = body && typeof body.text === 'string' ? body.text.trim().slice(0, 200) : '';
    if (!text) return E(422, 'VALIDATION', 'ต้องมีข้อความ');
    const m = { id: 'm' + d.seq++, text, source: 'user', at: nowIso() }; d.memory.push(m); return [201, m];
  });
  on('DELETE', '/v1/me/memory/{id}', ({ d, p }) => { const i = d.memory.findIndex(m => m.id === p.id); if (i < 0) return E(404, 'NOT_FOUND', 'ไม่พบบันทึกนี้'); d.memory.splice(i, 1); return [204]; });
  on('GET', '/v1/me/export', ({ d }) => [200, { profile: d.profile || {}, facts: d.facts, settings: d.settings, tasks: d.tasks.map(taskOut), consents: d.consents, memory: d.memory,
    govLink: { status: d.gov.status, provider: d.gov.provider, connectedAt: d.gov.connectedAt, ...(d.gov.identity ? { identity: d.gov.identity } : {}) },
    storedFields: ['profile', 'facts', 'settings', 'tasks', 'consents', 'memory', 'govLink'], notStored: ['ประวัติแชทกับ AI (เก็บเฉพาะระหว่างคุย)', 'เลขบัตรประชาชน', 'รหัสผ่าน OTP PIN'] }]);

  // Government connection (hidden mode)
  const govGate = () => govOn ? null : E(404, 'FEATURE_DISABLED', 'โหมดเชื่อมรัฐยังไม่เปิดใช้');
  on('GET', '/v1/me/gov-link', ({ d }) => govGate() || [200, govOut(d)]);
  on('POST', '/v1/me/gov-link', ({ d, device }) => { const g = govGate() || need(d, 'gov'); if (g) return g; dropGov(d); const s = govAdapter.start(device); d.gov = { status: 'pending', state: s.state }; return [201, { status: s.status, provider: govAdapter.provider, mock: true, authUrl: s.authUrl, state: s.state }]; });
  on('POST', '/v1/me/gov-link/callback', ({ d, device, body }) => {
    const g = govGate() || need(d, 'gov'); if (g) return g;
    const r = d.gov.status === 'pending' && d.gov.state === body?.state
      && govAdapter.finish(device, body.state, body.code, d.facts, d.profile || {}, opts.clock ? opts.clock() : Date.now());
    if (!r) return E(422, 'VALIDATION', 'state หรือ code ไม่ถูกต้อง');
    d.gov = r;
    if (r.identity) {
      d.gov.applied = appliedIdentity(d, r.identity);
      d.profile ||= {};
    }
    return [200, govOut(d)];
  });
  on('DELETE', '/v1/me/gov-link', ({ d }) => { const g = govGate(); if (g) return g; dropGov(d); return [204]; });

  // Intake
  const turn = (sid, s) => {
    const Q = ref.intake;
    if (s.i >= Q.length) return { sessionId: sid, aiStatus: s.aiStatus, done: true, question: 'สรุปข้อมูลแล้ว ถูกต้องไหมคะ', profileDraft: s.draft };
    return { sessionId: sid, aiStatus: s.aiStatus, done: false, question: Q[s.i].question, quickReplies: Q[s.i].quickReplies, profileDraft: s.draft };
  };
  on('POST', '/v1/intake/sessions', ({ d }) => { const g = need(d, 'core'); if (g) return g; const sid = 's' + d.seq++; d.sessions[sid] = { i: 0, draft: {}, aiStatus: has(d, 'ai') ? 'fallback_rules' : 'skipped_no_consent' }; return [201, turn(sid, d.sessions[sid])]; });
  on('POST', '/v1/intake/sessions/{id}/messages', async ({ d, device, p, body }) => {
    const s = d.sessions[p.id]; if (!s) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    if (!body || typeof body.text !== 'string' || !body.text.trim()) return E(422, 'VALIDATION', 'ต้องมีข้อความ');
    const Q = ref.intake; if (s.i >= Q.length) return [200, turn(p.id, s)];
    const q = Q[s.i], k = q.key, field = { question: q.question, options: ['goals', 'hoursPerWeek'].includes(k) ? q.quickReplies : undefined, number: k === 'incomeGoalPerMonth' };
    let v = body.text.trim();
    if (has(d, 'ai')) { const r = await aiFor(d).ai.extract(field, v); logAi(device, 'extract', r); v = r.value; s.aiStatus = r.aiStatus; } else v = require('./adapters/ai').rulesExtract(field, v);
    s.draft[k] = k === 'skills' || k === 'goals' ? [String(v)] : v;
    if (k === 'district') { const g = geo.geocode(v); if (g) { s.draft.lat = g.lat; s.draft.lng = g.lng; } }
    s.i++; return [200, turn(p.id, s)];
  });

  // Opportunities
  on('GET', '/v1/opportunities', ({ d, q, req }) => {
    const dataMode = q.get('dataMode') ?? 'all';
    if (dataMode !== 'all' && !OPPORTUNITY_DATA_MODES.has(dataMode)) return E(400, 'VALIDATION', 'dataMode ไม่ถูกต้อง');
    if (q.has('workMode') && !WORK_MODES.has(q.get('workMode'))) return E(400, 'VALIDATION', 'workMode ไม่ถูกต้อง');
    const res = search(d, q); if (!res) return E(400, 'VALIDATION', 'sort ไม่ถูกต้อง');
    const limit = Math.min(100, Math.max(1, +(q.get('limit') || 30)));
    const start = q.get('cursor') ? +Buffer.from(q.get('cursor'), 'base64url').toString() || 0 : 0;
    const warn = allSourceStates().filter(s => s.state === 'failed').map(s => s.provider);
    const end = start + limit;
    return [200, { items: res.xs.slice(start, end).map(item => opportunityResponse(item, req)), totalCount: res.xs.length,
      nextCursor: end < res.xs.length ? Buffer.from(String(end)).toString('base64url') : undefined,
      hasMoreMapLocations: res.xs.slice(end).some(hasMapLocation),
      hiddenSuspicious: res.hidden, districtPins: q.get('includeDistrictPins') === 'true' ? bangkokDistrictPins(res.xs) : undefined,
      suggestions: res.suggestions.length ? res.suggestions : undefined, sourceWarnings: warn.length ? warn : undefined }, { 'X-Total-Count': String(res.xs.length) }];
  });
  on('GET', '/v1/opportunities/{id}', ({ p, q, req }) => {
    const o = findOpportunity(p.id) ?? (q.get('includeClosed') === 'true' ? jobCatalogue?.getClosed(p.id) : undefined);
    return o ? [200, opportunityResponse(fresh(o), req)] : E(404, 'NOT_FOUND', 'ไม่พบรายการนี้');
  }, { public: true });
  on('POST', '/v1/opportunities/{id}/reports', ({ device, p, body }) => {
    const o = findOpportunity(p.id);
    if (!o) return E(404, 'NOT_FOUND', 'ไม่พบรายการนี้');
    if (!body || !['suspicious', 'wrong_info', 'expired', 'other'].includes(body.reason)) return E(400, 'VALIDATION', 'reason ไม่ถูกต้อง');
    const deviceHash = hashDevice(device), at = nowIso();
    if (sqliteProviders.has(o.provenance.provider)) {
      if (body.note !== undefined && typeof body.note !== 'string') return E(400, 'VALIDATION', 'note ต้องเป็นข้อความ');
      return jobCatalogue.report(p.id, deviceHash, body.reason, body.note, at, reportHide)
        ? [202] : E(404, 'NOT_FOUND', 'ไม่พบรายการนี้');
    }
    reports.push({ device: deviceHash, id: p.id, reason: body.reason, note: body.note, at });
    // A13: enough different devices saying "suspicious" hides the item until the team reviews it.
    const n = new Set(reports.filter(r => r.id === p.id && r.reason === 'suspicious').map(r => r.device)).size;
    if (n >= reportHide && !hiddenByReports.has(p.id)) { hiddenByReports.add(p.id); o.suspicious = true; o.suspiciousReasons = [...o.suspiciousReasons, REPORT_HIDE_REASON]; }
    return [202];
  });

  // Money
  on('GET', '/v1/money', ({ d }) => [200, { ...money.list(effectiveFacts(d), govData(d)), govLink: govOn ? d.gov.status : 'disabled' }]);
  // Check money from answers without storing anything (before consent). Same engine, no device state.
  on('POST', '/v1/money/preview', ({ body }) => {
    const { errors, clean } = money.validateFacts(body && body.facts);
    if (errors.length) return E(422, 'VALIDATION', 'ข้อมูลไม่ถูกต้อง', { missingFields: errors });
    const facts = Object.fromEntries(Object.entries(clean).filter(([, v]) => v !== undefined));
    const r = money.list(facts, null), next = r.items.find(i => i.status === 'need' && i.nextQuestion);
    return [200, { ...r, nextQuestion: next ? { ...next.nextQuestion, moneyId: next.id } : undefined, stored: false }];
  }, { public: true });
  on('GET', '/v1/money/{id}', ({ d, p }) => { const r = money.route(p.id, effectiveFacts(d), govData(d), d.docsReady[p.id]); return r ? [200, r] : E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้'); });
  on('PATCH', '/v1/money/{id}', ({ d, p, body }) => {
    const g = need(d, 'core'); if (g) return g;
    const prog = money.programs.find(x => x.id === p.id); if (!prog) return E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้');
    const ready = body && Array.isArray(body.documentsReady) ? body.documentsReady : null;
    if (!ready || ready.some(i => !Number.isInteger(i) || i < 0 || i >= prog.docs.length)) return E(422, 'VALIDATION', 'documentsReady ต้องเป็นลำดับเอกสารที่มีจริง');
    d.docsReady[p.id] = [...new Set(ready)]; return [200, money.route(p.id, effectiveFacts(d), govData(d), d.docsReady[p.id])];
  });

  // AI one-shot
  on('POST', '/v1/ai/rankings', async ({ d, device, body }) => {
    const ids = body && Array.isArray(body.opportunityIds) ? body.opportunityIds : [];
    if (!ids.length) return E(400, 'VALIDATION', 'ต้องมี opportunityIds อย่างน้อย 1 รายการ');
    const candidates = [...new Set(ids)].slice(0, 50).map(findOpportunity).filter(o => o && !o.suspicious);
    if (!has(d, 'ai')) { const r = require('./adapters/ai').rulesRank(d.profile, candidates); return [200, { aiStatus: 'skipped_no_consent', ranked: r }]; }
    const out = await aiFor(d).ai.rank(d.profile, candidates); logAi(device, 'rank', out);
    return [200, { aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId, ranked: out.ranked }];
  });
  on('POST', '/v1/ai/explanations', async ({ d, device, body }) => {
    if (!body || !['task_step', 'opportunity', 'money'].includes(body.subjectType) || !body.subjectId) return E(400, 'VALIDATION', 'ต้องมี subjectType และ subjectId');
    let subject;
    if (body.subjectType === 'task_step') { const t = d.tasks.find(x => x.id === body.subjectId); if (!t) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); subject = { type: 'task_step', title: t.title, step: t.steps[Math.min(t.doneCount, t.steps.length - 1)] }; }
    else if (body.subjectType === 'opportunity') { const o = findOpportunity(body.subjectId); if (!o) return E(404, 'NOT_FOUND', 'ไม่พบรายการนี้'); subject = { type: 'opportunity', opportunity: { title: o.title, conditions: o.conditions, category: o.category } }; }
    else { const r = money.route(body.subjectId, effectiveFacts(d), govData(d)); if (!r) return E(404, 'NOT_FOUND', 'ไม่พบรายการเงินนี้'); subject = { type: 'opportunity', opportunity: { title: r.title, conditions: r.reasons.map(x => x.text), category: 'money' } }; }
    if (!has(d, 'ai')) return [200, { aiStatus: 'skipped_no_consent', text: (await createAi({ baseUrl: '', apiKey: '' }).explain(subject)).text }];
    const out = await aiFor(d).ai.explain(subject); logAi(device, 'explain', out);
    return [200, { aiStatus: out.aiStatus, aiInvocationId: out.aiInvocationId, text: out.text }];
  });

  // AI assistant. The conversation owns the displayed question and uncommitted goal.
  const DIRECT_RE = /ลิงก์|ลิงค์|link|เว็บ|ติดต่อ|เบอร์|โทร|ช่องทาง|ทำไง|ต้องทำ|ทำอะไรต่อ|ขั้นตอน|บริบท|ควรได้|ได้อะไร|สิทธิ์อะไร|เงินอะไร|จากรัฐ/i;
  const choice = (fact, question, options, type = 'enum') => ({ fact, question, options, type });
  const intentStep = choice('intent', intentQuestion, intentOptions);
  const stepQuick = step => step ? [...(step.options || []), guard.skipQuickReply] : undefined;
  const planLinks = plans => plans.filter(plan => plan.outcome?.result !== 'received').map(plan => ({ taskId: plan.id, title: plan.title }));
  const benefitContext = topic => ({ taxYear: topic.taxYear, newExit: topic.newExit });
  const promptAge = /^(?:อายุ\s*)?\d{1,3}\s*(?:ปี)?(?:แล้ว)?(?:\s*(?:ค่ะ|ครับ|คะ))?$/;
  const safeForModel = value => typeof value === 'string' && !['injection', 'sensitive'].includes(guard.check(value).kind);

  function setStep(d, c, step) {
    if (!step) { c.expect = null; return; }
    const { key, ...publicStep } = step;
    const signature = JSON.stringify([c.topic?.id, c.topic?.mode, c.topic?.taxYear, c.topic?.newExit, key, publicStep]);
    if (c.stepSignature === signature && c.expect?.id) return;
    c.stepSignature = signature;
    c.expect = { ...publicStep, id: 'step' + d.seq++ };
  }

  function benefitCheck(d, c) {
    const topic = c.topic, id = topic.id;
    const { facts, conflicts } = profileFacts(d, benefitContext(topic));
    const available = fact => facts[fact] !== undefined;
    const skipped = c.skipped || [];
    const q = (fact, question) => {
      if (!fact || skipped.includes(fact)) return null;
      const step = money.question(fact);
      const wording = question || step.question;
      return { ...step, moneyId: id, question: conflicts[fact] ? 'ข้อมูลข้อนี้ไม่ตรงกัน ช่วยยืนยันอีกครั้งค่ะ ' + wording : wording, key: conflicts[fact] };
    };
    if (id === 'social_security_retirement') {
      let fact;
      if (!available('ageAtLeast55') && (!available('ageBand') || facts.ageBand === 'ต่ำกว่า 60')) fact = 'ageAtLeast55';
      else if (facts.ageAtLeast55 !== false) fact = ['coverageEnded', 'lifetimePaidMonths33And39'].find(key => !available(key) && !skipped.includes(key));
      return { step: q(fact), reply: 'ตรวจสิทธิชราภาพกับประกันสังคมโดยใช้สถานะผู้ประกันตนและเดือนสมทบสะสม ม.33 และ ม.39 ดูประวัติและสอบถามยอดจริงกับสำนักงานประกันสังคมค่ะ' };
    }
    if (id === 'old_age' && topic.mode === 'payment') {
      if (!available('oldAgeGets')) return { step: q('oldAgeGets', 'ตอนนี้ได้รับเบี้ยอยู่แล้วไหม?'), reply: 'ยังไม่ทราบสถานะการรับเบี้ยผู้สูงอายุ ติดต่อท้องถิ่นตามทะเบียนบ้านเพื่อตรวจได้ค่ะ' };
      if (facts.oldAgeGets) {
        const district = facts.registryDistrict ? 'ที่ ' + facts.registryDistrict : 'ตามทะเบียนบ้าน';
        return { reply: 'ติดตามการจ่ายเบี้ยผู้สูงอายุ ตรวจรายการโอนงวดนี้แล้วติดต่อท้องถิ่น' + district + ' เพื่อสอบถามรอบโอนและช่องทางแก้ไขค่ะ' };
      }
    }
    // ThaID contributes identity facts here. A legacy mock payment feed is separate from those claims.
    const routeFacts = id === 'disability' && topic.mode !== 'supplement' ? { ...facts, welfareCard: false } : facts;
    const route = money.route(id, routeFacts, null, d.docsReady[id]);
    if (!route) return { reply: 'ยังไม่มีเกณฑ์ของรายการนี้ในแอป ตรวจชื่อโครงการและช่องทางที่หน่วยงานประกาศค่ะ' };
    const suffix = id === 'tax_refund' ? ' ปีภาษี ' + ((topic.taxYear || Number(day().slice(0, 4))) + 543) : '';
    const tracking = id === 'old_age' && topic.mode === 'payment' ? 'ยังไม่ได้รับเบี้ย มาดูเกณฑ์ลงทะเบียนค่ะ\n' : '';
    const base = tracking + route.title + suffix;
    const fact = route.nextQuestion?.fact;
    const includeFact = id !== 'disability' || fact !== 'welfareCard' || topic.mode === 'supplement';
    const yearQuestion = id === 'tax_refund' && fact === 'taxWithheld' ? 'ปีภาษี ' + ((topic.taxYear || Number(day().slice(0, 4))) + 543) + ' ถูกหักภาษี ณ ที่จ่ายไหม?' : undefined;
    if (fact && includeFact && (route.status === 'need' || route.status === 'likely')) {
      const step = q(fact, yearQuestion);
      if (step) return { step };
      if (route.status === 'need') return { reply: base + ' ยังมีข้อมูลไม่พอสำหรับประเมิน ตรวจเกณฑ์และช่องทางกับ ' + route.payer + ' ค่ะ' };
    }
    if (route.status === 'unlikely') {
      const reason = id === 'disability' ? 'ต้องมีบัตรคนพิการที่ยังใช้ได้' : route.reasons.find(reason => reason.ok === false)?.text;
      return { reply: base + ' ยังไม่เข้าเกณฑ์จากข้อมูลที่มี' + (reason ? ' · ' + reason : '') };
    }
    if (id === 'tax_refund') {
      return { reply: base + '\nมีข้อมูลว่าถูกหักภาษี ณ ที่จ่าย ตรวจเอกสารหักภาษีและยื่นแบบกับกรมสรรพากรเพื่อดูผลและยอดคืนจริงค่ะ' };
    }
    if (route.alreadyReceiving) return { reply: base + '\nได้รับอยู่แล้ว ตรวจยอดและรอบจ่ายกับ ' + route.payer + ' ค่ะ' };
    const a = route.amount;
    return { reply: base + '\n' + (a.value !== undefined ? 'ประเมิน ' + moneyText(a.value) + ' ' + a.unit + ' ตามเกณฑ์ที่แอปมี ' : 'ยังประเมินยอดไม่ได้ ') + 'ตรวจเงื่อนไขและขั้นตอนยื่นกับ ' + route.payer + ' ค่ะ',
      action: route.claimable ? { tool: 'create_task', args: { moneyId: id } } : undefined };
  }

  function currentQuestion(d, c) {
    if (c.subjectAge !== undefined) return choice('subjectAge', 'อายุที่บอกเป็นอายุของคุณเองใช่ไหม?', ['อายุของฉัน', 'เป็นอายุคนอื่น']);
    if (!c.topic) return c.guided === false && c.expect?.fact !== 'intent' ? null : intentStep;
    if (c.topic.id === 'benefits') return choice('benefitTopic', 'อยากเช็กสิทธิเรื่องไหนก่อน?', benefitOptions);
    if (c.topic.id === 'program') return choice('programName', 'ขอชื่อโครงการหรือประกาศที่คุณเห็น เพื่อเช็กสิทธิของโครงการนั้นค่ะ', undefined, 'text');
    if (c.topic.id !== 'income') return benefitCheck(d, c).step;
    return c.incomeQuestion || null;
  }

  on('POST', '/v1/ai/conversations', ({ d, body }) => {
    const gate = need(d, 'ai'); if (gate) return gate;
    const id = 'conv' + d.seq++, guided = body?.mode !== 'free';
    const c = { history: [], pending: {}, expect: null, skipped: [], guided, queue: [] };
    d.conversations[id] = c;
    setStep(d, c, currentQuestion(d, c));
    return [201, { conversationId: id, greeting: guided ? intentQuestion : 'สวัสดีค่ะ ถามเรื่องเงินของคุณได้เลย',
      quickReplies: stepQuick(c.expect) || intentOptions, step: c.expect || undefined }];
  });

  on('POST', '/v1/ai/conversations/{id}/messages', async ({ d, device, p, body }) => {
    const gate = need(d, 'ai'); if (gate) return gate;
    const c = d.conversations[p.id]; if (!c) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    if (!body || typeof body.text !== 'string' || !body.text.trim() || (body.stepId !== undefined && typeof body.stepId !== 'string')) {
      return E(422, 'VALIDATION', 'ต้องมีข้อความและรหัสคำถามต้องเป็นข้อความ');
    }
    const raw = body.text.trim();
    const text = raw.slice(0, 1000);
    const displayed = c.expect;
    const previousAiReply = c.lastTurnUsedAi ? c.history.at(-1)?.content : undefined;
    c.lastTurnUsedAi = false;
    const turnNumber = c.turnNumber = (c.turnNumber || 0) + 1;
    assistantRequests.get(c)?.abort();
    const today = day();
    const savedPlans = () => d.tasks.filter(task => task.moneyId);
    const withQueuedTopic = options => c.queue?.length ? ['ไปเรื่องถัดไป', ...options] : options;
    const defaultReplies = () => withQueuedTopic(intentOptions);
    const planReplies = () => withQueuedTopic(['หางานใกล้บ้าน', 'เปลี่ยนเป้าหมาย', intentOptions[0]]);
    const jobReplies = () => withQueuedTopic(['ดูงานอื่น', intentOptions[1], intentOptions[0]]);
    const hasRegularJob = () => c.hasRegularJob === true || effectiveFacts(d).work === 'ทำงานประจำ';
    const sideHours = () => c.sideJobHours ?? partTimeHoursOf(d);
    const waiting = () => c.expect ? '\nกลับมาที่คำถาม: ' + c.expect.question : '';
    const turn = (reply, kind = 'in_scope', extra = {}) => [200, { aiStatus: 'guarded', reply,
      toolCalls: [], pendingActions: [], planLinks: [], memoryAdded: [], guard: { kind, policyVersion: guard.version },
      step: c.expect || undefined, quickReplies: stepQuick(c.expect) || defaultReplies(), ...extra }];
    c.skipped ||= [];
    c.queue ||= [];

    function details(out, tools, query = text) {
      const plans = savedPlans();
      const related = moneySummaryQuery.test(query) ? plans : matchingMoneyPlans(plans, { ...out, text: query });
      const alreadySaved = new Set(), pendingActions = [];
      for (const action of out.pending || []) {
        if (tools[action.tool]?.mode !== 'confirm') continue;
        if (action.tool === 'update_facts') {
          const facts = action.args?.facts;
          if (!facts || typeof facts !== 'object' || Array.isArray(facts) || !Object.keys(facts).length || money.validateFacts(facts).errors.length) continue;
        }
        const existing = action.tool === 'create_task' && plans.find(t => t.moneyId === action.args?.moneyId);
        if (existing) { alreadySaved.add(existing); continue; }
        if (action.tool === 'create_task' && action.args?.moneyId) {
          const facts = profileFacts(d, c.topic ? benefitContext(c.topic) : {}).facts;
          if (!money.route(action.args.moneyId, facts, govData(d))?.claimable) continue;
        }
        const id = 'pa' + d.seq++;
        c.pending[id] = { ...action, ...(action.tool === 'save_income_goal' ? { goalVersion: c.goalVersion } : {}) };
        pendingActions.push({ id, tool: action.tool, label: action.label || tools[action.tool].label(action.args || {}) });
      }
      const savedNote = [...alreadySaved].map(task => 'บันทึกแผน ' + task.title + ' ไว้แล้ว · ' + planPaymentStatus(task));
      return { reply: [out.reply, ...savedNote].join('\n'), toolCalls: (out.toolCalls || []).map(t => ({ tool: t.tool })),
        pendingActions, planLinks: planLinks(related), quickReplies: stepQuick(c.expect) || (c.queue.length ? defaultReplies() : out.quickReplies) || defaultReplies() };
    }

    function benefitReply(kind = 'in_scope', prefix = '') {
      const result = benefitCheck(d, c);
      setStep(d, c, currentQuestion(d, c));
      if (c.expect) return turn(prefix + c.expect.question, kind);
      const { reply, ...extra } = details({ reply: result.reply, pending: result.action ? [result.action] : [],
        toolCalls: money.programs.some(program => program.id === c.topic.id) ? [{ tool: 'get_money_route', args: { moneyId: c.topic.id } }] : [] },
      agentTools(d, device), result.reply);
      return turn(prefix + reply, kind, extra);
    }

    function incomeAsk(fact, question, options, kind = 'in_scope') {
      c.incomeQuestion = choice(fact, question, options, options ? 'enum' : 'text');
      setStep(d, c, c.incomeQuestion);
      return turn(question, kind);
    }

    function askJobDistrict(question = 'หางานแถวเขตไหนคะ? พิมพ์ชื่อเขต เช่น บางนา', options = ['ค้นทั้งกรุงเทพฯ']) {
      return incomeAsk('jobDistrict', question, options);
    }

    function askSideJobHours() {
      return incomeAsk('sideJobHours', 'คุณมีงานประจำอยู่แล้ว เราดูเฉพาะงานเสริมได้ค่ะ นอกเวลางานประจำ คุณว่างกี่ชั่วโมงต่อสัปดาห์?',
        ['ไม่เกิน 10', '10-20', 'ยังไม่แน่ใจ']);
    }

    function incomeIdeas() {
      c.incomeQuestion = null;
      setStep(d, c, null);
      const profile = d.profile || {};
      const tasks = c.topic.remote ? 'ดูงานที่ระบุว่าทำจากบ้านและตรวจผู้ว่าจ้าง หรือเริ่มจากงานรับทำตามทักษะที่ส่งงานออนไลน์ได้'
        : 'ลองดูงานพาร์ตไทม์ตามเวลาที่สะดวก หรืองานรับทำตามทักษะที่มี';
      const skills = c.topic.jobDetails?.skills || profile.skills?.join(', ');
      const hours = c.topic.jobDetails?.hours ?? profile.hoursPerWeek;
      const available = [skills ? 'ทักษะ ' + skills : '', hours !== undefined ? 'เวลาว่าง ' + hours + ' ชม./สัปดาห์' : ''].filter(Boolean);
      return turn((available.length ? 'จากข้อมูลที่ให้ไว้ (' + available.join(' · ') + ') ' : '') + tasks + ' ดูประกาศจริงในหน้าโอกาสค่ะ');
    }

    function goalReply(input, kind = 'in_scope') {
      const old = c.goal || {};
      const goal = c.goal = { ...old };
      if (input.denied || input.ambiguous || (input.amount !== undefined && (!Number.isInteger(input.amount) || input.amount <= 0 || input.amount > 1000000))) {
        delete goal.amount;
        c.goalVersion = (c.goalVersion || 0) + 1;
        return incomeAsk('goalAmount', input.ambiguous ? 'ยอดไหนคือจำนวนเงินที่อยากหาเพิ่ม?' : 'ระบุจำนวนเงินเป้าหมายใหม่ได้ไหม? เลือกดูทางเลือกก่อนได้ค่ะ', ['ดูทางเลือก'], kind);
      }
      if (input.amount !== undefined) goal.amount = input.amount;
      if (input.kind !== undefined) goal.kind = input.kind;
      if (input.deadline !== undefined) goal.deadline = input.deadline;
      if (input.expense) goal.expense = input.expense;
      if (goal.amount !== old.amount || goal.kind !== old.kind || goal.deadline !== old.deadline) c.goalVersion = (c.goalVersion || 0) + 1;
      if (input.skip) {
        if (c.incomeQuestion?.fact === 'goalExpense' || text === 'ดูทางเลือก') return incomeIdeas();
        if (c.incomeQuestion?.fact === 'goalPeriod' || c.incomeQuestion?.fact === 'goalDeadline') return incomeIdeas();
        return incomeAsk('goalExpense', 'มีค่าใช้จ่ายเรื่องไหนที่อยากให้เงินส่วนนี้ช่วยก่อน?', ['ดูทางเลือก'], 'skip');
      }
      if (!goal.amount) {
        const savedGoal = d.profile?.incomeGoalPerMonth;
        if (Number.isInteger(savedGoal) && savedGoal > 0 && savedGoal <= 1000000 && c.incomeQuestion?.fact !== 'goalAmount') {
          return incomeAsk('savedGoal', 'ใช้เป้าเดิมเดือนละ ' + moneyText(savedGoal) + ' บาท หรือเปลี่ยนเป้าหมาย?', ['ใช้เป้าเดิม', 'เปลี่ยนเป้าหมาย']);
        }
        return incomeAsk('goalAmount', 'อยากหาเงินเพิ่มประมาณเท่าไหร่?', ['ยังไม่แน่ใจ', 'ดูทางเลือก'], kind);
      }
      if (!goal.kind) return incomeAsk('goalPeriod', 'ต้องการ ' + moneyText(goal.amount) + ' บาทเป็นเงินก้อน หรืออยากมีเพิ่มเดือนละ ' + moneyText(goal.amount) + ' บาท?', ['เงินก้อน', 'รายเดือน'], kind);
      if (goal.deadline === null || goal.deadline < today) return incomeAsk('goalDeadline', 'กำหนดใช้เงินคือวันไหน? พิมพ์วันที่แบบ ปี-เดือน-วัน หรือบอกว่าใช้พรุ่งนี้ค่ะ', undefined, kind);
      const regular = hasRegularJob();
      const spareHours = regular ? sideHours() : undefined;
      if (goal.kind === 'monthly' && regular && spareHours === undefined) return askSideJobHours();
      c.incomeQuestion = null;
      setStep(d, c, null);
      if (goal.kind === 'once') {
        const deadline = goal.deadline ? ' ภายใน ' + new Intl.DateTimeFormat('th-TH', { dateStyle: 'long', timeZone: 'Asia/Bangkok' }).format(new Date(goal.deadline + 'T00:00:00Z')) : '';
        return turn('เป้าเงินก้อน ' + moneyText(goal.amount) + ' บาท' + (goal.expense ? ' สำหรับ' + goal.expense : '') + deadline +
          '\nลองดูงานรายครั้งที่จ่ายทันกำหนด หรือรับงานตามทักษะที่ทำเสร็จได้ในเวลาที่มี ดูเงื่อนไขจ่ายเงินในประกาศก่อนสมัครค่ะ', kind,
          { quickReplies: planReplies() });
      }
      const context = { includeBenefits: c.topic.includeBenefits === true, remote: c.topic.remote === true,
        sideJob: regular, spareHours };
      const tools = agentTools(d, device, context);
      const plan = tools.plan_income_goal.run({ target: goal.amount });
      const pending = goal.amount === d.profile?.incomeGoalPerMonth ? [] : [{ tool: 'save_income_goal', args: { target: goal.amount } }];
      const { reply, ...extra } = details({ reply: formatGoal(plan), pending, toolCalls: [{ tool: 'plan_income_goal' }] }, tools);
      const intro = regular ? 'แผนงานเสริมสำหรับเวลาว่าง ' + spareHours + ' ชั่วโมงต่อสัปดาห์ เช็กกะจริงกับผู้ประกาศก่อนสมัครค่ะ\n' : '';
      return turn(intro + reply, kind, { ...extra, quickReplies: planReplies() });
    }

    function selectTopic(topic, rest = []) {
      c.topic = topic;
      c.skipped = [];
      c.queue = rest;
      c.subjectAge = undefined;
      if (topic.id === 'income') {
        c.goal = {};
        c.goalVersion = (c.goalVersion || 0) + 1;
        c.incomeQuestion = null;
      }
    }

    async function runAssistant(query, kind, { deterministic = false, income = false, moreJobs = false, benefit } = {}) {
      const regular = income && hasRegularJob();
      const excludedJobs = moreJobs ? new Set(c.topic.jobResultIds) : new Set();
      const returnedJobs = new Set(excludedJobs);
      const spareHours = regular ? sideHours() : undefined;
      const tools = agentTools(d, device, { ...benefitContext(benefit || {}), remote: income && c.topic.remote,
        sideJob: regular, spareHours, excludedJobs, jobArea: income ? c.topic.jobArea : undefined });
      const allowed = income ? Object.fromEntries(Object.entries(tools).filter(([key]) =>
        ['search_opportunities', 'create_task', 'get_profile'].includes(key))) : { ...tools };
      delete allowed.save_income_goal;
      delete allowed.plan_income_goal;
      if (income) {
        delete allowed.get_profile;
        const searchJobs = allowed.search_opportunities.run;
        allowed.search_opportunities.run = args => {
          const result = searchJobs(args);
          for (const item of result.items) returnedJobs.add(item.id);
          return result;
        };
      }
      if (benefit) {
        const routeTool = allowed.get_money_route;
        for (const key of Object.keys(allowed)) if (!['get_money_route', 'create_task'].includes(key)) delete allowed[key];
        allowed.get_money_route = { ...routeTool, run: () => routeTool.run({ moneyId: benefit.id }) };
      }
      const narrowed = income ? moreJobs || query === 'หางานใกล้บ้าน' ? 'หางานใกล้บ้าน' : 'ช่วยคิดทางเลือกหารายได้จากทักษะ' + (c.topic.remote ? 'ที่ทำจากบ้าน' : '')
        + (c.topic.limitedTravel ? ' เดินทางไกลไม่สะดวก' : '') : benefit && !shortAnswer.test(query) ? 'ช่วยอธิบายขั้นตอนของ ' + money.programs.find(program => program.id === benefit.id).title : query;
      const stepPrompt = ['แอปเลือกหัวข้อและคำถามแล้ว ให้สรุปทางเลือกจากเครื่องมือโดยไม่ถามคัดกรองอีก',
        moreJobs && 'ค้นงานอื่นจาก search_opportunities หากไม่พบให้บอกว่ายังไม่พบงานอื่นในพื้นที่นี้',
        regular && 'ผู้ใช้มีงานประจำ เสนอเฉพาะงานเสริมจากผลค้นหา และให้ตรวจว่ากะไม่ชนงานประจำก่อนสมัคร',
        regular && spareHours === undefined && 'ยังไม่รู้เวลาว่าง ให้รายงานเฉพาะค่าจ้างตามประกาศต่อหน่วย และอย่าคำนวณรายได้ต่อเดือนจากจำนวนชั่วโมงหรือวันที่สมมติ'
      ].filter(Boolean).join(' ');
      const consent = d.conversations[p.id];
      const gov = d.gov;
      const controller = new AbortController();
      assistantRequests.set(c, controller);
      const fallback = async () => benefit ? { reply: benefitCheck(d, c).reply, aiStatus: 'fallback_rules' }
        : runRulesAgent({ text: narrowed, tools: allowed });
      let out;
      try {
        out = deterministic ? await runRulesAgent({ text: narrowed, tools: allowed })
          : await aiFor(d).agent.respond({ text: narrowed, tools: allowed,
            history: income ? [] : c.history, memory: [],
            profile: income ? { skills: d.profile?.skills?.filter?.(safeForModel),
              hoursPerWeek: regular ? spareHours : safeForModel(d.profile?.hoursPerWeek) ? d.profile.hoursPerWeek : undefined,
              constraints: safeForModel(d.profile?.constraints) ? d.profile.constraints : undefined } : {},
            signal: controller.signal, fallback,
            systemPrompt: guard.systemPrompt(stepPrompt) });
      } catch {
        if (!controller.signal.aborted) out = await fallback();
      } finally {
        if (assistantRequests.get(c) === controller) assistantRequests.delete(c);
      }
      if (!has(d, 'ai') || devices.get(device) !== d || d.conversations[p.id] !== consent) {
        return E(403, 'CONSENT_REQUIRED', 'เซสชันนี้ไม่มีสิทธิ์ใช้ AI แล้ว');
      }
      if (c.turnNumber !== turnNumber) return turn(c.expect?.question || 'มีข้อความใหม่ในบทสนทนาแล้วค่ะ', 'unclear');
      if (d.gov !== gov) {
        setStep(d, c, currentQuestion(d, c));
        if (benefit) return benefitReply('in_scope');
        if (!income) return runAssistant('เงินฉันอยู่ไหน', 'in_scope', { deterministic: true });
      }
      if (!out) out = await fallback();
      if (income && out.aiStatus === 'fallback_rules' && narrowed !== 'หางานใกล้บ้าน') {
        const [status, result] = incomeIdeas();
        return [status, { ...result, aiStatus: 'fallback_rules' }];
      }
      if (benefit) out = { ...out, pending: out.pending?.filter(action => action.args?.moneyId === benefit.id) };
      if (out.aiStatus === 'ok' && !income && !benefit
        && /(?:คุณ(?:ควร|จะ|มีสิทธิ์)|เข้าเกณฑ์|ได้แน่นอน).{0,16}(?:ได้เงิน|รับเงิน|รับเบี้ย)|ได้เงินแน่นอน/.test(out.reply)
        && !money.list(effectiveFacts(d), govData(d)).items.some(item => ['likely', 'verified'].includes(item.status))) {
        return runAssistant('เงินฉันอยู่ไหน', 'in_scope', { deterministic: true });
      }
      const { reply, ...extra } = details(out, allowed, query);
      if (income) {
        c.topic.jobResultIds = [...returnedJobs];
        extra.quickReplies = returnedJobs.size > excludedJobs.size ? jobReplies() : defaultReplies();
      }
      const memoryAdded = income || benefit ? [] : (out.memory || []).filter(note => safeForModel(note) && guard.check(note).kind === 'in_scope').map(note => {
        const item = { id: 'm' + d.seq++, text: note.slice(0, 200), source: 'ai', at: nowIso() };
        d.memory.push(item);
        return item;
      });
      if (out.aiStatus === 'ok') {
        c.history.push({ role: 'user', content: narrowed }, { role: 'assistant', content: reply });
        c.history = c.history.slice(-8);
        c.lastTurnUsedAi = true;
      }
      logAi(device, 'agent', out);
      return turn(reply + waiting(), kind, { ...extra, memoryAdded, aiStatus: deterministic ? 'guarded' : out.aiStatus });
    }

    const policy = guard.check(raw);
    const topics = topicRequests(text);
    const regularJobReported = policy.kind === 'in_scope' && regularJobStatement.test(text);
    const joinedRequest = /(?:แล้ว|และ|แต่|ช่วยหางานอื่น)/.test(text);
    const workSafety = /มัดจำ/.test(text) && /งาน|นายจ้าง/.test(text);
    const hardRefusal = ['sensitive', 'injection', 'guarantee'].includes(policy.kind);
    if (hardRefusal || policy.kind === 'off_topic' && !(topics.length && joinedRequest)
      || policy.kind === 'scam' && !(workSafety && topics.some(topic => topic.id === 'income') && joinedRequest)) {
      const next = workSafety ? ' ตรวจประกาศ ตรวจชื่อบริษัทกับช่องทางทางการ และดูงานอื่นที่ไม่ขอเงินก่อนค่ะ' : '';
      return turn(policy.reply + next + waiting(), policy.kind);
    }
    if (policy.kind === 'safe_advice') return turn(policy.reply + waiting());
    if (otherSubject.test(text) && !jobRequest.test(text)) {
      c.otherSubject = true;
      return turn('แอปเช็กสิทธิให้เจ้าของโปรไฟล์นี้ค่ะ ถ้าต้องการตรวจของตัวคุณเอง บอกได้เลย');
    }

    // Refresh against the current data while keeping the identifier of the question the user saw.
    setStep(d, c, currentQuestion(d, c));
    if (body.stepId && body.stepId !== c.expect?.id) {
      return turn(c.expect?.question || 'คำถามนี้ปิดแล้ว เลือกเรื่องที่อยากทำต่อได้เลยค่ะ', 'unclear');
    }
    const asked = c.expect;
    const sameQuestion = displayed?.id === asked?.id && asked;
    const resumeQueue = text === 'ไปเรื่องถัดไป' && c.queue.length;
    if (resumeQueue) topics.push(c.queue.shift(), ...c.queue);

    const plans = savedPlans();
    const named = matchingMoneyPlans(plans, { text });
    if (unpaidPlansQuery.test(text) || (planStatusQuery.test(text) && named.length)) {
      setStep(d, c, null);
      const links = planLinks(named.length ? named : plans);
      const reply = named.length ? named.map(task => task.title + ' · ' + planPaymentStatus(task)).join('\n')
        : links.length ? 'เปิดแผนที่บันทึกไว้และยังไม่มีการแจ้งว่าได้รับเงินได้จากปุ่มด้านล่างค่ะ' : 'ตอนนี้ไม่มีแผนที่บันทึกไว้และยังรอแจ้งว่าได้รับเงินค่ะ';
      return turn(reply, 'in_scope', { planLinks: links });
    }
    if (moneyGuide.test(text) || text === 'ดูรายการสิทธิทั้งหมด') {
      c.topic = null;
      setStep(d, c, null);
      return runAssistant(text === 'ดูรายการสิทธิทั้งหมด' ? 'เงินฉันอยู่ไหน' : text, 'in_scope', { deterministic: true });
    }

    if (regularJobReported) c.hasRegularJob = true;
    const explicit = topics[0];
    if (regularJobReported && !explicit && !asked?.moneyId) {
      if (c.topic?.id !== 'income') selectTopic({ id: 'income' }, c.queue);
      if (sideHours() === undefined) return askSideJobHours();
      if (c.goal?.amount && c.goal.kind) return goalReply({});
      return turn('คุณมีงานประจำอยู่แล้ว เลือกดูงานเสริมหรือกำหนดเป้ารายได้เพิ่มได้ค่ะ', 'in_scope',
        { quickReplies: withQueuedTopic(['หางานใกล้บ้าน', intentOptions[1]]) });
    }
    if (policy.kind === 'in_scope' && c.topic?.id === 'income' && c.topic.jobResultIds && moreJobRequest.test(text)) {
      c.incomeQuestion = null;
      setStep(d, c, null);
      return runAssistant(text, 'in_scope', { income: true, moreJobs: true });
    }
    if (sameQuestion?.fact === 'sideJobHours' && !explicit) {
      const answer = thaiDigits(text).replace(/\s*(?:ค่ะ|ครับ|คะ)$/, '').trim();
      const hours = HOURS[answer] ?? Number(/^(\d{1,2})(?:\s*(?:ชม\.?|ชั่วโมง)(?:\s*(?:ต่อ|\/)\s*สัปดาห์)?)?$/.exec(answer)?.[1]);
      if (hours > 0 && hours <= 40 && answer !== 'เต็มเวลา') {
        c.sideJobHours = hours;
        c.incomeQuestion = null;
        setStep(d, c, null);
        if (c.goal?.amount && c.goal.kind) return goalReply({});
        return turn('บันทึกไว้สำหรับการคุยครั้งนี้ว่าคุณว่าง ' + hours + ' ชั่วโมงต่อสัปดาห์ค่ะ', 'in_scope',
          { quickReplies: withQueuedTopic(['หางานใกล้บ้าน', intentOptions[1]]) });
      }
      if (answer === 'ยังไม่แน่ใจ') {
        return turn('ดูประกาศงานเสริมก่อนได้ค่ะ ฉันจะคำนวณรายได้เมื่อทราบเวลาว่างของคุณ', 'in_scope',
          { quickReplies: withQueuedTopic(['หางานใกล้บ้าน', intentOptions[0]]) });
      }
      return askSideJobHours();
    }
    if (explicit && explicit.id === 'income' && c.topic?.id === 'income' && !resumeQueue) {
      c.topic.remote ||= explicit.remote;
      c.topic.limitedTravel ||= explicit.limitedTravel;
    } else if (explicit) {
      selectTopic(explicit, topics.slice(1));
    }
    if (explicit?.id === 'benefits') {
      setStep(d, c, currentQuestion(d, c));
      return turn(c.expect.question);
    }
    if (explicit?.id === 'program') {
      setStep(d, c, currentQuestion(d, c));
      return turn(c.expect.question);
    }

    if (explicit?.id === 'income') {
      if (text === intentOptions[1] && !c.incomeQuestion && c.goal?.amount && c.goal.kind) {
        return turn('แผนตามเป้าที่คุยกันอยู่ด้านบนค่ะ เลือกดูงานใกล้บ้านหรือเปลี่ยนเป้าหมายได้เลย', 'in_scope',
          { quickReplies: planReplies() });
      }
      const incomeText = resumeQueue ? text : thaiDigits(text).slice(explicit.index);
      const input = resumeQueue ? explicit.goal : parseGoal(incomeText, today);
      if (input.amount !== undefined || input.kind || input.denied || input.ambiguous || input.skip || !jobRequest.test(incomeText)) return goalReply(input);
      if (workSafety) return turn('ระวังงานที่ขอมัดจำค่ะ ตรวจชื่อบริษัทกับช่องทางทางการก่อน ดูงานอื่นที่ระบุเงื่อนไขชัดและสมัครได้โดยไม่โอนเงิน');
      if (explicit.remote && !d.profile?.skills?.length) return incomeAsk('jobSkills', 'ถ้าจะทำงานจากบ้าน คุณถนัดงานอะไรบ้าง?', ['ดูทางเลือก']);
      if (explicit.remote && !d.profile?.hoursPerWeek) return incomeAsk('jobHours', 'คุณมีเวลาทำงานจากบ้านประมาณกี่ชั่วโมงต่อสัปดาห์?', ['ดูทางเลือก']);
      if (!c.topic.remote) {
        const named = districtsIn(text);
        c.topic.jobQuery = text;
        if (named.length > 1) return askJobDistrict('หมายถึงเขตไหนคะ?', named.map(district => district.name));
        const home = homeDistrict(d);
        c.topic.jobArea = named.length ? { district: named[0] } : c.topic.jobArea || (home && { district: home });
        if (!c.topic.jobArea) return askJobDistrict();
      }
      setStep(d, c, null);
      c.incomeQuestion = null;
      return runAssistant(text, 'in_scope', { income: true });
    }
    if (explicit) {
      const topic = c.topic;
      const foundYear = thaiDigits(text).match(/(?:ปีภาษี|ปี)\s*(\d{4})/);
      if (topic.id === 'tax_refund' && foundYear) topic.taxYear = Number(foundYear[1]) - (Number(foundYear[1]) >= 2400 ? 543 : 0);
      if (topic.id === 'unemployment') topic.newExit = /(?:ออกจากงาน|ออกงาน|ตกงาน|เลิกจ้าง).{0,24}(?:ครั้งใหม่|รอบใหม่|ล่าสุด)|(?:ครั้งใหม่|รอบใหม่|ล่าสุด).{0,24}(?:ออกจากงาน|ออกงาน|ตกงาน|เลิกจ้าง)/.test(text);
      if (self.test(text)) c.otherSubject = false;
      const age = /อายุ\s*[๐-๙\d]{1,3}\s*(?:ปี)?/.exec(text);
      if (age && topic.id === 'old_age') {
        const value = answerValue(money.question('ageBand'), age[0]);
        if (c.otherSubject && !self.test(text)) c.subjectAge = value;
        else if (value !== undefined) {
          const { facts } = profileFacts(d);
          if (facts.ageBand === undefined) svc.patchFacts(d, { ageBand: value });
        }
      }
      if (/^(?:ช่วย)?(?:ขอ|อธิบาย).*รายละเอียด/.test(text) && money.programs.some(program => program.id === topic.id)
        && !benefitCheck(d, c).step && money.route(topic.id, profileFacts(d, benefitContext(topic)).facts, null)?.claimable) {
        setStep(d, c, null);
        return runAssistant(text, 'in_scope', { benefit: topic });
      }
      return benefitReply();
    }

    if (/^(?:เตือนฉัน|ฉันไม่สะดวก)/.test(text) && policy.kind === 'in_scope') {
      setStep(d, c, null);
      return runAssistant(text, 'in_scope');
    }
    if (/^ช่วย(?:ดู|อธิบายผลเช็ก)เงินของฉัน/.test(text)) {
      setStep(d, c, null);
      return runAssistant('ช่วยดูเงินของฉันหน่อย', 'in_scope');
    }
    if (c.topic?.id === 'income') {
      if (sameQuestion?.fact === 'jobDistrict') {
        const named = districtsIn(text);
        if (text === 'ค้นทั้งกรุงเทพฯ' || guard.check(text, sameQuestion).kind === 'skip') c.topic.jobArea = { district: null };
        else if (named.length === 1) c.topic.jobArea = { district: named[0] };
        else if (named.length) return askJobDistrict('หมายถึงเขตไหนคะ?', named.map(district => district.name));
        else return askJobDistrict('ยังไม่รู้จักเขตนี้ พิมพ์ชื่อเขตในกรุงเทพฯ เช่น บางนา');
        c.incomeQuestion = null;
        setStep(d, c, null);
        return runAssistant(c.topic.jobQuery || 'หางานใกล้บ้าน', 'in_scope', { income: true });
      }
      if (sameQuestion?.fact === 'jobSkills' || sameQuestion?.fact === 'jobHours') {
        if (text === 'ดูทางเลือก' || guard.check(text, sameQuestion).kind === 'skip') return incomeIdeas();
        const skillText = sameQuestion.fact === 'jobSkills' ? text : undefined;
        const hours = sameQuestion.fact === 'jobHours' ? /^([๐-๙\d]{1,3})(?:\s*ชั่วโมง)?/.exec(text) : undefined;
        c.topic.jobDetails = { ...c.topic.jobDetails, ...(skillText ? { skills: skillText } : {}), ...(hours ? { hours: Number(thaiDigits(hours[1])) } : {}) };
        return incomeIdeas();
      }
      const input = parseGoal(sameQuestion?.fact === 'goalDeadline' && /^\d{4}-\d{2}-\d{2}$/.test(thaiDigits(text)) ? 'วันที่ ' + text : text, today);
      if (text === 'เปลี่ยนเป้าหมาย') {
        c.goal = {};
        return incomeAsk('goalAmount', 'อยากหาเงินเพิ่มประมาณเท่าไหร่?', ['ยังไม่แน่ใจ', 'ดูทางเลือก']);
      }
      if (text === 'ใช้เป้าเดิม' && sameQuestion?.fact === 'savedGoal') return goalReply({ amount: d.profile.incomeGoalPerMonth, kind: 'monthly' });
      if (input.kind || input.amount !== undefined || input.denied || input.skip || input.ambiguous
        || ((sameQuestion || c.goal?.amount) && (input.deadline !== undefined || input.expense))) return goalReply(input);
    }
    if (/^ยังไม่รู้ว่าอยากได้เท่าไหร่/.test(text)) {
      selectTopic({ id: 'income' });
      return goalReply({ skip: true });
    }

    if (sameQuestion) {
      const rule = guard.check(text, sameQuestion);
      if (rule.kind === 'explain') return turn('ข้อนี้ถามว่า: ' + asked.question + (asked.help ? '\n' + asked.help : ''), 'explain');
      if (rule.kind === 'skip') {
        c.skipped = [...c.skipped, asked.fact];
        if (asked.moneyId) return benefitReply('skip', 'ข้ามข้อนี้ไว้ก่อนค่ะ\n');
        if (asked.fact === 'subjectAge') {
          c.subjectAge = undefined;
          c.otherSubject = false;
          setStep(d, c, currentQuestion(d, c));
          return turn(c.expect?.question || intentQuestion, 'skip');
        }
        if (c.topic?.id === 'program') { selectTopic({ id: 'benefits' }); setStep(d, c, currentQuestion(d, c)); }
        return turn(c.expect?.question || intentQuestion, 'skip');
      }
      if (c.otherSubject && asked.fact !== 'subjectAge' && promptAge.test(thaiDigits(text))) {
        c.subjectAge = answerValue(money.question('ageBand'), text);
        if (c.subjectAge !== undefined) {
          setStep(d, c, currentQuestion(d, c));
          return turn(c.expect.question, 'unclear');
        }
      }
      if (asked.fact === 'subjectAge' && /^(อายุของฉัน|ใช่|เป็นอายุคนอื่น|ไม่ใช่)/.test(text)) {
        if (/^(อายุของฉัน|ใช่)/.test(text)) svc.patchFacts(d, { ageBand: c.subjectAge });
        c.subjectAge = undefined;
        c.otherSubject = false;
        if (c.topic && money.programs.some(program => program.id === c.topic.id)) return benefitReply('answer');
        setStep(d, c, currentQuestion(d, c));
        return turn(c.expect?.question || intentQuestion, 'answer');
      }
      if (asked.moneyId) {
        const value = asked.fact === 'work' && regularJobReported ? 'ทำงานประจำ' : answerValue(asked, text);
        if (value !== undefined) {
          const context = benefitContext(c.topic);
          const { conflicts } = profileFacts(d, context);
          const [status] = svc.patchFacts(d, { [asked.fact]: value }, { ...context, conflicts });
          if (status >= 400) return turn('คำตอบนี้ใช้ไม่ได้ ลองตอบอีกครั้งค่ะ\n' + asked.question, 'unclear');
          return benefitReply('answer', 'บันทึกคำตอบแล้วค่ะ\n');
        }
      }
      if (asked.fact === 'programName' && policy.kind !== 'off_topic') return turn('ยังจับคู่กับรายการที่มีในแอปไม่ได้ ลองตรวจชื่อและเงื่อนไขจากประกาศของหน่วยงานที่จัดโครงการค่ะ');
    }

    if (asked?.moneyId || asked?.fact === 'subjectAge') {
      if (DIRECT_RE.test(text) && !shortAnswer.test(text)) return turn('ยังต้องตอบคำถามข้อนี้เพื่อประเมินสิทธิค่ะ' + waiting());
      return turn(asked.question, 'unclear');
    }
    if (DIRECT_RE.test(text) && policy.kind === 'in_scope') return runAssistant(text, 'in_scope', { deterministic: true });
    if (!explicit && (monthly.test(text) || lumpSum.test(text)) && !expense.test(text)) {
      selectTopic({ id: 'income' });
      return goalReply(parseGoal(text, today));
    }
    if (expense.test(text)) {
      c.topic = null;
      setStep(d, c, intentStep);
      return turn('เข้าใจว่ากังวลเรื่อง' + text.match(expense)[0] + 'ค่ะ ' + intentQuestion, 'unclear');
    }
    if (c.guided === false && shortAnswer.test(text) && previousAiReply && /[?？]|แล้วหรือยัง|ไหม/.test(previousAiReply)) {
      return runAssistant(text, 'ai_scope', { benefit: c.topic || undefined });
    }
    if (c.guided === false && shortAnswer.test(text)) return turn(guard.offTopicReply + '\n' + guard.redirect, 'off_topic');
    if (!asked) c.topic = null;
    setStep(d, c, asked || intentStep);
    return turn(c.expect.question, 'unclear');
  });

  on('POST', '/v1/ai/conversations/{id}/actions/{actionId}', ({ d, device, p, body }) => {
    const gate = need(d, 'ai'); if (gate) return gate;
    const c = d.conversations[p.id]; if (!c) return E(404, 'NOT_FOUND', 'ไม่พบการคุยนี้');
    const done = c.decisions?.[p.actionId];
    const action = c.pending[p.actionId];
    if (!action && !done) return E(404, 'NOT_FOUND', 'ไม่พบคำขอนี้');
    if (!body || !['confirm', 'reject'].includes(body.decision)) return E(422, 'VALIDATION', 'decision ต้องเป็น confirm หรือ reject');
    if (done) return done.decision === body.decision ? done.response : E(409, 'CONFLICT', 'ยืนยันผลของข้อเสนอนี้ไปแล้ว');
    if (action.tool === 'save_income_goal' && action.goalVersion !== c.goalVersion) return E(409, 'CONFLICT', 'เป้าหมายเปลี่ยนแล้ว กรุณาใช้ข้อเสนอล่าสุด');
    let response = [200, { status: 'rejected' }];
    if (body.decision === 'confirm') {
      const [status, result] = agentTools(d, device)[action.tool].exec(action.args);
      if (status >= 300) return [status, result];
      response = [200, { status: 'done', result }];
    }
    delete c.pending[p.actionId];
    c.decisions ||= {};
    c.decisions[p.actionId] = { decision: body.decision, response };
    return response;
  });

  // Planner
  const hoursOf = d => HOURS[(d && d.profile && d.profile.hoursPerWeek) || ''];
  const partTimeHoursOf = d => d.profile?.hoursPerWeek === 'เต็มเวลา' ? undefined : hoursOf(d);
  on('GET', '/v1/plans/options', ({ d, q }) => [200, { items: planOptions(d, (q.get('opportunityIds') || '').split(',').filter(Boolean)) }]);
  on('GET', '/v1/plans/goal', ({ d, q }) => {
    const t = q.has('target') ? +q.get('target') : d.profile && d.profile.incomeGoalPerMonth;
    if (!(t > 0) || t > 1000000) return E(400, 'VALIDATION', 'ต้องมี target เป็นจำนวนเงินต่อเดือน (บาท) หรือบันทึกเป้ารายได้ในโปรไฟล์');
    return [200, goalPlan(d, Math.round(t))];
  });
  // "I want X baht this month": benefits the person likely qualifies for (sourced rates) + the best-fitting
  // earning options for their skills and free time, until the low end reaches the goal. Ranges, never a promise.
  function goalPlan(d, target, { includeBenefits = true, remote = false, sideJob: sideJobOnly = false, spareHours } = {}) {
    const knownFacts = effectiveFacts(d);
    const regular = sideJobOnly || knownFacts.work === 'ทำงานประจำ';
    const skills = d.profile?.skills || [], h = regular ? spareHours ?? partTimeHoursOf(d) : hoursOf(d);
    const facts = includeBenefits ? knownFacts : {};
    const mList = includeBenefits ? money.list(facts, govData(d)).items : [];
    const benefits = mList.filter(i => ['likely', 'verified'].includes(i.status) && i.kind === 'monthly' && typeof i.amount.value === 'number')
      .map(i => ({ kind: 'benefit', id: i.id, title: i.title, net: [i.amount.value, i.amount.value], numberSource: 'official', dataStatus: i.dataStatus,
        why: i.status === 'verified' ? 'ยืนยันจากหน่วยงาน' : 'เงินสวัสดิการที่น่าจะมีสิทธิ์ ยังไม่ยืนยัน', action: { type: 'money_route', id: i.id } }));
    const ideas = ref.skillIdeas.map(i => ({ kind: 'skill', id: i.id, title: i.title, net: [i.grossPerMonth[0] - i.costPerMonth[1], i.grossPerMonth[1] - i.costPerMonth[0]],
      numberSource: 'estimate', dataStatus: 'mock', requires: i.skills, matched: i.skills.filter(s => skills.includes(s)), assumptions: i.assumptions, why: 'ประมาณการ ยังไม่มีผู้ซื้อยืนยัน', action: { type: 'idea', id: i.id } }));
    const jobs = regular && h === undefined ? [] : jobOptions(d, { remote, regular, hours: h });
    // Skill matches first, then (for people 60+) jobs that accept older workers, then the higher low end.
    // Free time limits how many earning options fit.
    const older = facts.ageBand && facts.ageBand !== 'ต่ำกว่า 60';
    // Only options the person can do: no special skill needed, or at least one of their skills matches.
    const pool = (regular && h === undefined ? [] : [...ideas, ...jobs]).filter(x => !(x.requires || []).length || x.matched.length)
      .filter((x, i, a) => a.findIndex(y => y.title === x.title) === i)
      .sort((a, b) => (b.matched.length > 0) - (a.matched.length > 0) || (older ? (!!b.forOlder) - (!!a.forOlder) : 0) || b.net[0] - a.net[0]);
    const room = h === undefined ? 2 : h >= 40 ? 3 : h >= 15 ? 2 : 1;
    const parts = [...benefits];
    let low = benefits.reduce((s, x) => s + x.net[0], 0);
    for (const x of pool) { if (low >= target || parts.length - benefits.length >= room) break; parts.push(x); low += x.net[0]; }
    parts.forEach(x => { delete x.requires; delete x.forOlder; });
    const total = [parts.reduce((s, x) => s + x.net[0], 0), parts.reduce((s, x) => s + x.net[1], 0)];
    const missing = [];
    if (includeBenefits && !Object.keys(facts).length) missing.push({ id: 'money_check', text: 'ยังไม่ได้เช็คเงินที่ควรได้จากรัฐ อาจมีเงินเพิ่ม' });
    else if (mList.some(i => i.status === 'need')) missing.push({ id: 'money_check', text: 'ยังมีคำถามเรื่องเงินจากรัฐที่ยังไม่ได้ตอบ อาจมีเงินเพิ่ม' });
    if (!skills.length) missing.push({ id: 'skills', text: 'ยังไม่รู้ทักษะของคุณ บอกทักษะแล้วแผนจะตรงตัวขึ้น' });
    if (h === undefined) missing.push({ id: 'hours', text: regular ? 'บอกเวลาว่างนอกงานประจำก่อนประเมินรายได้เสริม' : 'ยังไม่รู้เวลาว่างต่อสัปดาห์ จึงคิดไว้ไม่เกิน 2 ทาง' });
    return { target, parts, total, gap: Math.max(0, target - total[0]), reach: total[0] >= target ? 'likely' : total[1] >= target ? 'maybe' : 'short',
      missing, hoursPerWeek: h, note: 'เป็นการวางแผนจากเกณฑ์ที่ประกาศ ค่าจ้างในประกาศ และประมาณการ ไม่ใช่รายได้ที่รับประกัน งานและลูกค้าต้องหาเองตามขั้นในแผน' };
  }
  // Monthly range for every job listing that states a wage, from the person's free time (default 20 h/week).
  // A full-time monthly job only fits with 30+ free hours. Travel cost is not deducted (said in assumptions).
  function jobOptions(d, { remote, regular, hours }) {
    const hw = hours ?? 20, skills = d.profile?.skills || [];
    const best = new Map();
    for (const o of opportunityValues()) {
      if (o.mapGroup !== 'job' || o.suspicious || o.money.basis !== 'listing' || typeof o.money.min !== 'number') continue;
      if (regular && !sideJob(o)) continue;
      if (remote && o.location.workMode !== 'remote' && !o.location.isRemote) continue;
      const shift = regular ? advertisedShiftHours(o) : undefined;
      if (shift > hw) continue;
      const unit = o.money.unit || '';
      let f, basis;
      if (/เดือน/.test(unit)) { if (hw < 30 && o.category === 'job_full') continue; f = 1; basis = 'ค่าจ้างรายเดือนตามประกาศ'; }
      else if (/วัน/.test(unit)) {
        const days = Math.min(6, regular ? Math.floor(hw / (shift || 8)) : Math.max(1, Math.round(hw / 8)));
        if (!days) continue;
        f = days * 4.33;
        basis = days + ' วัน/สัปดาห์ ตามเวลาว่าง ' + hw + ' ชม.';
      }
      else if (/ชั่วโมง/.test(unit)) {
        const billableHours = shift ? Math.floor(hw / shift) * shift : hw;
        f = billableHours * 4.33;
        basis = billableHours + ' ชม./สัปดาห์ ตามเวลาว่าง';
      }
      else continue;
      const net = [Math.round(o.money.min * f), Math.round((o.money.max || o.money.min) * f)];
      const x = { kind: 'job', id: o.id, title: o.title, net, numberSource: 'listing', dataStatus: o.provenance.dataStatus, forOlder: o.forOlder, requires: o.skills,
        matched: (o.skills || []).filter(s => skills.includes(s)), assumptions: [basis, 'ยังไม่หักค่าเดินทางและค่าใช้จ่าย' + (/ก่อนหัก/.test(unit) ? ' (' + unit + ')' : '')],
        why: 'ค่าจ้างตามประกาศ' + (o.provenance.dataStatus === 'mock' ? ' (ประกาศตัวอย่าง)' : '') + ' · ' + (o.organization || ''), action: { type: 'opportunity', id: o.id } };
      const k = normalizeJobText(o.title), prev = best.get(k);
      if (!prev || x.matched.length > prev.matched.length || (x.matched.length === prev.matched.length && x.net[0] > prev.net[0])) best.set(k, x);
    }
    return [...best.values()];
  }
  function planOptions(d, want = []) {
    const h = hoursOf(d);
    return ref.plans.filter(p => !want.length || want.includes(p.opportunityId)).map(p => {
      let x = { ...p }; const o = p.opportunityId && findOpportunity(p.opportunityId);
      if (h && o && o.money.basis === 'listing' && /วัน|ชั่วโมง/.test(o.money.unit || '')) {
        const units = /ชั่วโมง/.test(o.money.unit) ? h * 4.33 : (h / 6) * 4.33;
        x.grossPerMonth = [Math.round(o.money.min * units), Math.round(o.money.max * units)];
        x.assumptions = ['คิดจากเวลาว่างของคุณ ' + h + ' ชม./สัปดาห์', ...(p.assumptions || []).filter(a => !/วัน\/สัปดาห์/.test(a))];
      }
      return x.grossPerMonth ? { ...x, netPerMonth: [x.grossPerMonth[0] - x.costPerMonth[1], x.grossPerMonth[1] - x.costPerMonth[0]] } : x;
    });
  }
  on('GET', '/v1/plans/ideas', async ({ d }) => {
    const skills = (d.profile && d.profile.skills) || [];
    const pool = ref.skillIdeas.filter(i => !skills.length || i.skills.some(s => skills.includes(s)));
    const ideas = (pool.length ? pool : ref.skillIdeas);
    let order = ideas.map(i => i.id), aiStatus = 'fallback_rules';
    if (has(d, 'ai') && ai.provider !== 'rules') {
      const r = await aiFor(d).ai.rank(d.profile, ideas.map(i => ({ id: i.id, title: i.title, category: 'skill', mapGroup: 'skill', money: { basis: 'listing' }, conditions: i.assumptions, provenance: {} })));
      order = r.ranked.map(x => x.opportunityId); aiStatus = r.aiStatus;
    } else if (!has(d, 'ai')) aiStatus = 'skipped_no_consent';
    return [200, { aiStatus, items: order.map(id => ideas.find(i => i.id === id)).filter(Boolean).map(i => ({ id: i.id, title: i.title, track: 'C', grossPerMonth: i.grossPerMonth, costPerMonth: i.costPerMonth,
      netPerMonth: [i.grossPerMonth[0] - i.costPerMonth[1], i.grossPerMonth[1] - i.costPerMonth[0]], payDays: i.payDays, effort: i.effort, risk: i.risk, numberSource: 'estimate', assumptions: i.assumptions, matchedSkills: i.skills.filter(s => skills.includes(s)) })) }];
  });

  // Tasks
  const findTask = (d, id) => d.tasks.find(t => t.id === id);
  on('GET', '/v1/tasks', ({ d, q }) => {
    const status = q.get('status');
    const items = d.tasks.filter(t => !status || t.status === status).map(t => {
      const id = t.opportunityId;
      const opportunity = id ? (findOpportunity(id) ?? jobCatalogue?.getClosed(id)) : undefined;
      return { ...taskOut(t), category: opportunity?.category };
    });
    return [200, { items }];
  });
  on('POST', '/v1/tasks', ({ d, body }) => svc.createTask(d, body));
  on('GET', '/v1/tasks/{id}', ({ d, p }) => { const t = findTask(d, p.id); return t ? [200, taskOut(t)] : E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); });
  on('DELETE', '/v1/tasks/{id}', ({ d, device, p }) => { const i = d.tasks.findIndex(t => t.id === p.id); if (i < 0) return E(404, 'NOT_FOUND', 'ไม่พบงานนี้'); d.tasks.splice(i, 1); notifier.cancel(device, p.id); return [204]; });
  on('GET', '/v1/tasks/{id}/events', ({ d, p }) => findTask(d, p.id) ? [200, { items: d.events.filter(e => e.taskId === p.id).map(e => ({ id: e.id, type: e.type, at: e.at, undone: !!e.undone })) }] : E(404, 'NOT_FOUND', 'ไม่พบงานนี้'));
  on('POST', '/v1/tasks/{id}/events', ({ d, device, p, body, req }) => svc.taskEvent(d, device, p.id, body, req.headers['idempotency-key']));

  // Sources
  on('GET', '/v1/sources', () => [200, { items: allSourceStates() }], { public: true });
  on('POST', '/v1/sources/{provider}/refresh', ({ p }) => {
    const sqliteRefresh = sqliteRefreshJobs.get(p.provider);
    if (sqliteRefresh) {
      void jobs.run(sqliteRefresh.name);
      return [202];
    }
    if (p.provider === 'all') {
      for (const scheduled of sqliteRefreshJobs.values()) void jobs.run(scheduled.name);
    }
    if (p.provider !== 'all' && !sources.providers.includes(p.provider)) return E(404, 'NOT_FOUND', 'แหล่งนี้ไม่รองรับการดึง');
    void refresh(p.provider);
    return [202];
  }, { public: true });

  // Integrations (inbound)
  const validLocation = l => l && typeof l === 'object' && ['exact', 'city', 'none'].includes(l.precision)
    && (l.precision !== 'exact' || (Number.isFinite(l.lat) && Math.abs(l.lat) <= 90 && Number.isFinite(l.lng) && Math.abs(l.lng) <= 180));
  const validInput = i => i && i.externalId && i.title && i.category && i.mapGroup && i.money && ['official', 'listing', 'none'].includes(i.money.basis) && /^https?:\/\//.test(i.sourceUrl || '')
    && (!i.location || validLocation(i.location)) && (i.locations === undefined || (Array.isArray(i.locations) && i.locations.every(validLocation)))
    && (i.description === undefined || typeof i.description === 'string')
    && (i.summary === undefined || typeof i.summary === 'string')
    && (i.availability === undefined || ['open', 'upcoming', 'paused', 'closed', 'expired'].includes(i.availability))
    && (i.checkedAt === undefined || typeof i.checkedAt === 'string')
    && (i.documents === undefined || (Array.isArray(i.documents) && i.documents.every(d => typeof d === 'string')))
    && (i.contacts === undefined || (Array.isArray(i.contacts) && i.contacts.every(c => typeof c === 'string'
      || (c && typeof c.label === 'string' && ['purpose', 'type', 'destination', 'hoursText', 'instructions', 'districtCode', 'sourceUrl', 'checkedAt']
        .every(k => c[k] === undefined || typeof c[k] === 'string')))))
    && ['claim', 'job', 'income', 'grant'].every(k => i[k] === undefined || (i[k] && typeof i[k] === 'object' && !Array.isArray(i[k])))
    && (i.status === undefined || ['active', 'closed'].includes(i.status));
  on('POST', '/v1/integrations/opportunities/batch', ({ body }) => {
    if (typeof body?.provider !== 'string' || !body.provider || !Array.isArray(body.items)) return E(422, 'VALIDATION', 'ต้องมี provider และ items');
    if (body.items.length > 500) return E(422, 'VALIDATION', 'ส่งได้ครั้งละไม่เกิน 500 รายการ');
    const sqlSource = jobCatalogue?.source(body.provider);
    if (sqlSource || sqliteProviders.has(body.provider) || (jobCatalogue && body.items.some(item => item?.mapGroup === 'job'))) {
      try {
        const result = pushJobs(body.provider, body.dataStatus, body.items);
        sqliteProviders.add(body.provider);
        return [200, result];
      } catch (error) {
        if (!(error instanceof JobFeedError)) throw error;
        return E(422, 'VALIDATION', error.message);
      }
    }
    if (body.dataStatus === 'mock') return E(422, 'VALIDATION', 'ข้อมูล DEMO / MOCK ต้องใช้แหล่ง push ที่ลงทะเบียนใน SQLite');
    const status = ['live', 'curated', 'open_data'].includes(body.dataStatus) ? body.dataStatus : 'curated';
    const rejected = [], mergedInto = []; let accepted = 0;
    body.items.forEach((it, index) => {
      if (!validInput(it)) return rejected.push({ index, reason: 'ข้อมูลไม่ครบ หรือไม่มีลิงก์ต้นทาง หรือ exact ไม่มีพิกัด' });
      const r = upsert(body.provider, status, body.attribution || body.provider, it);
      r.merged ? mergedInto.push({ index, existingId: r.id }) : accepted++;
    });
    let st = srcState.find(s => s.provider === body.provider);
    if (!st) srcState.push(st = { provider: body.provider, name: body.provider, kind: 'ส่งเข้าผ่าน Integrations', attribution: body.attribution || body.provider, direction: 'push', state: 'ok' });
    Object.assign(st, { state: 'ok', lastFetchedAt: nowIso(), itemCount: [...opps.values()].filter(o => o.provenance.provider === body.provider).length });
    return [200, { accepted, rejected, merged: mergedInto }];
  }, { integration: true });
  on('POST', '/v1/integrations/webhooks/{provider}', ({ p, body }) => {
    const sqlSource = jobCatalogue?.source(p.provider);
    if (!sqlSource && !srcState.some(s => s.provider === p.provider)) return E(404, 'NOT_FOUND', 'ไม่รู้จักผู้ให้ข้อมูลนี้');
    if (!body || !['opportunity.closed', 'opportunity.updated'].includes(body.event)
        || typeof body.externalId !== 'string' || !body.externalId) return E(422, 'VALIDATION', 'event หรือ externalId ไม่ถูกต้อง');
    if (sqlSource || sqliteProviders.has(p.provider)) {
      try {
        const closing = body.event === 'opportunity.closed';
        const result = pushJobs(p.provider, undefined, closing ? [] : [{ ...body.data, externalId: body.externalId }],
          closing ? { closeId: body.externalId } : undefined);
        if (result.rejected.length) return E(422, 'VALIDATION', result.rejected[0].reason);
        sqliteProviders.add(p.provider);
        return [202];
      } catch (error) {
        if (!(error instanceof JobFeedError)) throw error;
        return E(422, 'VALIDATION', error.message);
      }
    }
    const id = p.provider + '_' + body.externalId;
    if (body.event === 'opportunity.closed') opps.delete(id);
    else { if (!validInput({ ...body.data, externalId: body.externalId })) return E(422, 'VALIDATION', 'data ไม่ครบ'); upsert(p.provider, 'curated', p.provider, { ...body.data, externalId: body.externalId }); }
    return [202];
  }, { integration: true });

  // Demo
  async function refreshDemoTangRat(device) {
    const d = devices.get(device);
    const profile = d?.demoProfile;
    const cached = profile?.records?.tangRat;
    if (!demoOn || !opts.demoTangRatEndpoint || !cached || profile.owner !== device) return { status: 'unavailable' };

    const result = await loadDemoTangRatCard(opts.demoTangRatEndpoint, opts.fetch || fetch);
    if (result.status === 'failed') return result;
    if (devices.get(device) !== d || d.demoProfile !== profile || profile.records.tangRat !== cached) return { status: 'superseded' };

    const { disabilityCard, asOf, expiresAt } = result.record;
    profile.records = { ...profile.records, tangRat: { ...cached, disabilityCard, asOf, checkedAt: asOf, expiresAt } };
    persist();
    return { status: 'refreshed' };
  }

  function selectDemoPersona(id, sources) {
    if (!Object.hasOwn(demoPersonas, id)) return {};
    if (sources === null) return { per: demoPersonas[id] };
    const selection = sources ? sources.split(',') : [];
    if (id !== 'gov-prefill' || selection.some(source => !govPrefillSourceIds.includes(source))) {
      return { error: E(400, 'VALIDATION', 'เลือกแหล่งข้อมูลตัวอย่างได้เฉพาะ ThaID ทางรัฐ ประกันสังคม และ D-MyTax ในโปรไฟล์ gov-prefill') };
    }
    return { per: govPrefillPersona(ref.thaid, selection, opts.demoSourceRecords) };
  }
  on('GET', '/v1/demo/personas/{id}', ({ p, q }) => {
    const { per, error } = selectDemoPersona(p.id, q.get('sources'));
    if (error) return error;
    if (!per?.sources) return E(404, 'NOT_FOUND', 'ไม่มีโปรไฟล์ตัวอย่างให้แสดง');
    return [200, { profile: per.profile, identity: per.identity, sources: per.sources, dataStatus: 'mock' }];
  }, { public: true });
  on('POST', '/v1/demo/personas/{id}', ({ device, p, q }) => {
    const { per, error } = selectDemoPersona(p.id, q.get('sources'));
    if (error) return error;
    if (!demoOn || !per) return E(404, 'NOT_FOUND', demoOn ? 'ไม่พบผู้ใช้ตัวอย่างนี้' : 'ปิดโหมดสาธิตอยู่');
    const supportsKeepPlans = p.id === 'gov-prefill' || Object.hasOwn(taxDemoPersonas, p.id);
    const previous = q.get('keepPlans') === 'true' && supportsKeepPlans ? devices.get(device) : undefined;
    if (devices.has(device)) cancelAssistantRequests(devices.get(device));
    devices.delete(device); const d = dev(device);
    if (previous) {
      const { tasks, events, docsReady, seq } = previous;
      Object.assign(d, { tasks, events, docsReady, seq });
    }
    d.consents.push({ id: 'c' + d.seq++, noticeVersion: NOTICE.version, ageConfirmed: true, purposes: Object.fromEntries(purposeIds.map(id => [id, id !== 'gov'])), at: nowIso() });
    d.profile = { ...per.profile }; const g = geo.geocode(per.profile.district); if (g) { d.profile.lat = g.lat; d.profile.lng = g.lng; }
    d.facts = { ...(per.initialAnswers || per.facts) };
    d.demoProfile = { owner: device, checkedAt: nowIso(), identity: per.identity, records: per.records };
    per.tasks.forEach(oid => svc.createTask(d, { opportunityId: oid }));
    return [200, { persona: p.id, label: per.label, profile: d.profile, facts: effectiveFacts(d), taskCount: d.tasks.length, dataStatus: 'mock',
      ...(per.sources ? { identity: per.identity, sources: per.sources } : {}) }];
  });

  // ---- scheduled jobs (B3) ----
  async function checkLinks(ctx) {
    const f = ctx.fetch || opts.fetch || fetch;
    const xs = [...opps.values()].filter(o => o.provenance.dataStatus !== 'mock' && /^https?:\/\//.test(o.provenance.sourceUrl || '')).slice(0, ctx.limit || 300);
    const count = { ok: 0, broken: 0, unknown: 0 };
    for (const o of xs) {
      let st = 'unknown';
      try {
        const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), 8000);
        const r = await f(o.provenance.sourceUrl, { method: 'HEAD', redirect: 'follow', signal: ctl.signal }); clearTimeout(t);
        st = r.status === 404 || r.status === 410 ? 'broken' : r.status < 400 ? 'ok' : 'unknown'; // 403/405 on HEAD is common, do not hide those
      } catch { /* network error or timeout: unknown, keep the item */ }
      o.provenance.linkStatus = st; o.provenance.linkCheckedAt = nowIso(); count[st]++;
    }
    persist();
    return 'checked ' + xs.length + ': ok ' + count.ok + ', broken ' + count.broken + ', unknown ' + count.unknown;
  }
  const reminderText = j => {
    const d = devices.get(j.deviceId), t = d && d.tasks.find(x => x.id === j.taskId);
    if (!t) return 'ถึงเวลาทำขั้นต่อไปแล้ว';
    if (t.status === 'snoozed') { t.status = 'active'; t.dueText = undefined; }
    return 'เตือน: ' + t.title + ' ขั้นต่อไป ' + t.steps[Math.min(t.doneCount, t.steps.length - 1)];
  };
  const jobs = createJobs([
    { name: 'sources_refresh', everyMinutes: refreshHours * 60, enabled: !!opts.live && autoJobSync, run: async () => { await refresh('all'); return srcState.filter(s => s.direction === 'pull').map(s => s.provider + ' ' + s.state).join(', '); } },
    ...[...sqliteRefreshJobs.values()].map(job => ({ ...job, enabled: autoJobSync })),
    { name: 'link_check', everyMinutes: 24 * 60, run: checkLinks },
    { name: 'reminders', everyMinutes: 1, run: ctx => { const n = notifier.dispatch(ctx.now ?? Date.now(), reminderText); if (n) persist(); return 'sent ' + n; } },
    { name: 'retention', everyMinutes: 24 * 60, enabled: retentionDays > 0, run: ctx => {
      const days = ctx.days ?? retentionDays; if (!(days > 0)) return 'off (RETENTION_DAYS not set)';
      const mode = ctx.mode || retentionMode, now = ctx.now ?? Date.now(), cut = now - days * 864e5, out = [];
      for (const [id, d] of devices) if (new Date(d.lastSeenAt || 0).getTime() < cut) { out.push(packDevice(id, d)); devices.delete(id); notifier.cancel(id); }
      // Archive keeps profile + activity only; identity (ThaID) and runtime state are never archived.
      if (out.length && mode === 'archive') store.archive(out.map(r => archiveRecord(r, 'retention ' + days + ' days', new Date(now).toISOString())));
      if (out.length) persist(); return (mode === 'archive' ? 'archived ' : 'deleted ') + out.length + ' devices not seen for ' + days + ' days';
    } }
  ]);

  // ---- HTTP ----
  const server = http.createServer(async (req, res) => {
    const u = new URL(req.url, 'http://x'), requestId = crypto.randomUUID();
    const send = (status, body, headers = {}) => {
      if (body && typeof body === 'object' && 'code' in body && 'message' in body && !('requestId' in body)) body = { ...body, requestId };
      res.writeHead(status, { 'X-Request-Id': requestId, 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Expose-Headers': 'X-Request-Id, X-Total-Count, ETag', 'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS', ...(body !== undefined ? { 'Content-Type': 'application/json; charset=utf-8' } : {}), ...headers });
      res.end(body !== undefined ? JSON.stringify(body) : undefined);
    };
    if (req.method === 'OPTIONS') return send(204);
    if (req.method === 'GET' && /^\/docs\/?$/.test(u.pathname)) {
      const f = path.join(DIR, '..', 'docs', 'backend', 'index.html');
      if (!fs.existsSync(f)) return send(404, { code: 'NOT_FOUND', message: 'ยังไม่ได้สร้างเอกสาร รัน npm run docs', status: 404, retryable: false });
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); return res.end(fs.readFileSync(f));
    }
    const sourceReport = /^\/docs\/sources\/((?:thai-senior-benefits|bangkok-benefits)-2026-11-27\.(html|md))$/.exec(u.pathname);
    const jobApplication = u.pathname === '/docs/mockups/job-application.html';
    const opportunityPage = demoOn && [BANGKOK_INFO_PATH, '/docs/mockups/opportunity-map.html'].includes(u.pathname);
    const districtMap = demoOn && u.pathname === '/docs/mockups/bangkok-district-map.json';
    if (req.method === 'GET' && (sourceReport || jobApplication || opportunityPage || districtMap)) {
      const file = districtMap ? path.join(DIR, 'fixtures', 'bangkok-district-map.json')
        : jobApplication || opportunityPage ? path.join(DIR, '..', 'docs', 'mockups', path.basename(u.pathname))
        : path.join(DIR, '..', 'docs', 'product', 'sources', sourceReport[1]);
      let content;
      try {
        content = await fs.promises.readFile(file);
      } catch (error) {
        return error.code === 'ENOENT' ? send(...E(404, 'NOT_FOUND', 'ไม่พบไฟล์ในโปรเจกต์')) : send(...E(500, 'INTERNAL', 'เปิดไฟล์ไม่ได้'));
      }
      const type = districtMap ? 'application/json' : path.extname(file) === '.html' ? 'text/html' : 'text/plain';
      res.writeHead(200, { 'Content-Type': type + '; charset=utf-8', 'Referrer-Policy': 'no-referrer' });
      return res.end(content);
    }
    let raw = ''; for await (const c of req) raw += c;
    let body; try { body = raw ? JSON.parse(raw) : undefined; } catch { return send(...E(400, 'VALIDATION', 'JSON ไม่ถูกต้อง')); }
    for (const r of R) {
      const m = r.method === req.method && u.pathname.match(r.re); if (!m) continue;
      if (r.integration && req.headers['x-api-key'] !== integrationKey) return send(...E(401, 'UNAUTHORIZED', 'ต้องมี X-Api-Key ที่ถูกต้อง'));
      const device = req.headers['x-device-id'];
      if (!r.public && !r.integration && (!device || device.length < 8)) return send(...E(400, 'MISSING_DEVICE', 'ต้องมี X-Device-Id'));
      try {
        const d = device ? dev(device) : null; if (d) d.lastSeenAt = nowIso();
        const [st, b, h] = await r.fn({ req, q: u.searchParams, p: m.groups || {}, body, device, d });
        if (req.method !== 'GET' && st < 400) persist();
        return send(st, b, h);
      }
      catch (e) { if (opts.debug) console.error(e); return send(...E(500, 'INTERNAL', 'ระบบขัดข้อง')); }
    }
    send(...E(404, 'NOT_FOUND', 'ไม่พบ endpoint นี้'));
  });
  server.ports = { ai, agent, notifier, refresh, refreshDemoTangRat, jobs, store, persist };
  if (jobCatalogue) server.once('close', () => jobCatalogue.close());
  if (opts.jobs !== false) {
    server.once('listening', () => {
      if (autoJobSync) {
        for (const scheduled of sqliteRefreshJobs.values()) void jobs.run(scheduled.name);
      }
      jobs.start();
    });
    server.on('close', () => jobs.stop());
  }
  return server;
}

module.exports = { createServer };
if (require.main === module) {
  const port = +(process.env.PORT || 8080);
  // `npm run mock` keeps data in contracts/.data/ (git-ignored) so a restart does not wipe the demo.
  const dataDir = process.env.APP_MODE === 'user' ? path.join(DIR, '.data', 'user') : path.join(DIR, '.data');
  const s = createServer({ live: process.env.LIVE === '1', debug: true, jobDbFile: process.env.JOB_DB_FILE,
    mockJobFeedFile: process.env.MOCK_JOB_FEED_FILE, jobicySync: process.env.JOBICY_SYNC === '1', jobFeedsFile: process.env.JOB_FEEDS_FILE,
    dataFile: process.env.DATA_FILE !== undefined ? process.env.DATA_FILE : path.join(dataDir, 'state.json'),
    aiLogFile: process.env.AI_LOG_FILE !== undefined ? process.env.AI_LOG_FILE : path.join(dataDir, 'ai-calls.jsonl') });
  s.listen(port, () => {
    // B2: phones on the same Wi-Fi can call the LAN address; for other networks use a tunnel (see docs/guide/run-demo-server.md).
    const lan = Object.values(require('os').networkInterfaces()).flat().filter(i => i && i.family === 'IPv4' && !i.internal).map(i => 'http://' + i.address + ':' + port);
    console.log('API on http://localhost:' + port + '  docs: /docs  AI: ' + s.ports.ai.provider + '  store: ' + s.ports.store.kind + '  commit: ' + COMMIT);
    console.log('Android emulator: http://10.0.2.2:' + port + (lan.length ? '  same Wi-Fi: ' + lan.join(', ') : ''));
  });
}
