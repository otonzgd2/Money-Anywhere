const { setTimeout: delay } = require('node:timers/promises');
const { JobFeedError } = require('./job-sync');

const JOBICY_SOURCE = Object.freeze({
  provider: 'jobicy',
  name: 'Jobicy',
  kind: 'ประกาศงาน Remote จาก Jobicy Public API',
  attribution: 'Jobicy',
  direction: 'pull',
  dataStatus: 'live',
  minPollMinutes: 60,
  fetchUrl: 'https://jobicy.com/api/jobs',
  termsUrl: 'https://jobicy.com/jobs-rss-feed#fair-use',
  approved: true,
  canStore: 1,
  canRedisplay: 1,
  commercialUse: 1,
  checkedBy: 'Codex',
  checkedOn: '2026-11-27'
});

const GEO_SCOPE = 'anywhere,thailand';
const PAGE_SIZE = 100;
const MAX_PAGES = 20;
const categoriesByType = new Map([
  ['full-time', 'job_full'], ['part-time', 'job_part'], ['temporary', 'job_part'],
  ['internship', 'job_part'], ['contract', 'freelance'], ['freelance', 'freelance']
]);
const salaryPeriods = { hourly: 'ชั่วโมง', daily: 'วัน', weekly: 'สัปดาห์', monthly: 'เดือน', yearly: 'ปี' };

function toJob(raw) {
  const link = typeof raw.url === 'string' && URL.parse(raw.url);
  if (!link || link.origin !== 'https://jobicy.com' || !link.pathname.startsWith('/jobs/')
      || typeof raw.jobTitle !== 'string' || !raw.jobTitle.trim()
      || typeof raw.companyName !== 'string' || !raw.companyName.trim()
      || typeof raw.pubDate !== 'string' || !Number.isFinite(Date.parse(raw.pubDate))) {
    throw new JobFeedError('Jobicy ส่งรายละเอียดประกาศไม่ครบหรือมีลิงก์ต้นทางผิดรูปแบบ');
  }
  const type = raw.jobType.find(value => categoriesByType.has(value.toLowerCase()));
  if (!type) return undefined;
  const period = salaryPeriods[raw.salaryPeriod];
  const hasSalary = raw.salaryMin != null || raw.salaryMax != null;
  const money = raw.salaryCurrency === 'THB' && period && hasSalary
    ? { basis: 'listing', min: raw.salaryMin, max: raw.salaryMax, unit: 'บาท/' + period }
    : { basis: 'none', knownText: hasSalary ? 'ดูค่าจ้างและสกุลเงินที่ประกาศต้นทาง' : 'ต้นทางไม่ระบุค่าจ้าง' };

  return {
    externalId: String(raw.id),
    title: raw.jobTitle,
    organization: raw.companyName,
    category: categoriesByType.get(type.toLowerCase()),
    mapGroup: 'job',
    location: { precision: 'none', text: 'งานทางไกล · ' + raw.jobGeo, workMode: 'remote' },
    money,
    conditions: ['พื้นที่ที่เปิดรับตามประกาศ Jobicy: ' + raw.jobGeo],
    postedAt: new Date(raw.pubDate).toISOString(),
    sourceUrl: link.href
  };
}

function createJobicyFeed(fetchImpl = fetch) {
  let retryAt = 0;

  async function getData(url) {
    if (Date.now() < retryAt) throw new JobFeedError('Jobicy ขอให้รอก่อนเรียก API อีกครั้ง');
    const request = () => fetchImpl(url.href, {
      headers: { Accept: 'application/json', 'User-Agent': 'MoneyAnywhere/1.0 (Jobicy feed)' },
      signal: AbortSignal.timeout(15000)
    });
    let response;
    try {
      response = await request().catch(async error => {
        if (error.cause?.code !== 'ECONNRESET') throw error;
        await delay(750);
        return request();
      });
    } catch {
      throw new JobFeedError('เชื่อมต่อ Jobicy ไม่สำเร็จ');
    }
    if (!response.ok) {
      if ([429, 503].includes(response.status)) {
        const wait = response.headers.get('Retry-After');
        const seconds = Number(wait);
        const next = wait !== null && Number.isFinite(seconds) ? Date.now() + seconds * 1000 : Date.parse(wait ?? '');
        retryAt = Number.isFinite(next) ? next : Date.now() + 60000;
      }
      throw new JobFeedError('Jobicy ตอบ HTTP ' + response.status);
    }
    let body;
    try {
      body = await response.json();
    } catch {
      throw new JobFeedError('Jobicy ส่งผลลัพธ์ที่ไม่ใช่ JSON');
    }
    if (body?.success !== true || !Array.isArray(body.jobs)) throw new JobFeedError('ผลลัพธ์ Jobicy ไม่ครบ');
    return body;
  }

  return async trackedIds => {
    const url = new URL(JOBICY_SOURCE.fetchUrl);
    url.search = new URLSearchParams({ geo: GEO_SCOPE, count: String(PAGE_SIZE) });
    const cursors = new Set();
    const items = new Map();
    const statuses = new Map();
    const tracked = new Set(trackedIds);
    while (true) {
      const page = await getData(url);
      const { hasMore, nextCursor } = page;
      if (page.jobCount !== page.jobs.length || typeof hasMore !== 'boolean'
          || (hasMore ? typeof nextCursor !== 'string' || !nextCursor || cursors.has(nextCursor) : nextCursor !== null)) {
        throw new JobFeedError('Jobicy ส่งข้อมูลแบ่งหน้าไม่ครบ');
      }
      for (const raw of page.jobs) {
        if (!Number.isSafeInteger(raw?.id) || raw.id < 1 || typeof raw.jobGeo !== 'string'
            || !Array.isArray(raw.jobType) || !raw.jobType.every(type => typeof type === 'string')) {
          throw new JobFeedError('Jobicy ส่งรหัสประกาศ พื้นที่ หรือประเภทงานผิดรูปแบบ');
        }
        const id = String(raw.id);
        const eligible = raw.jobGeo.split(',').some(region => ['anywhere', 'thailand'].includes(region.trim().toLowerCase()));
        const item = eligible ? toJob(raw) : undefined;
        if (item) items.set(id, item);
        else if (tracked.has(id)) statuses.set(id, 'out_of_scope');
      }
      if (!hasMore) break;
      cursors.add(nextCursor);
      if (cursors.size >= MAX_PAGES) throw new JobFeedError('Jobicy ส่งรายการเกินจำนวนหน้าที่รองรับต่อรอบ');
      url.searchParams.set('cursor', nextCursor);
      await delay(1000);
    }

    // The feed has a rolling publication window. Only the status endpoint can confirm closure.
    const absentIds = trackedIds.filter(id => !items.has(id) && !statuses.has(id));
    for (let offset = 0; offset < absentIds.length; offset += PAGE_SIZE) {
      const batch = absentIds.slice(offset, offset + PAGE_SIZE);
      const remaining = new Set(batch);
      const statusUrl = new URL('/api/jobs/status', JOBICY_SOURCE.fetchUrl);
      statusUrl.searchParams.set('ids', batch.join(','));
      const response = await getData(statusUrl);
      for (const item of response.jobs) {
        const id = String(item?.id);
        if (!remaining.delete(id) || !['active', 'closed', 'unknown'].includes(item.status)) {
          throw new JobFeedError('Jobicy ส่งสถานะประกาศที่ไม่ตรงกับรายการที่ขอตรวจ');
        }
        statuses.set(id, item.status);
      }
      if (remaining.size) throw new JobFeedError('Jobicy ส่งสถานะประกาศไม่ครบ');
      if (offset + PAGE_SIZE < absentIds.length) await delay(1000);
    }
    return { items: [...items.values()], statuses };
  };
}

module.exports = { JOBICY_SOURCE, createJobicyFeed };
