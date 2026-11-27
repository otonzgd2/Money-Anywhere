const { createHash, randomUUID } = require('node:crypto');
const { readFile } = require('node:fs/promises');
const { openJobDatabase, readJobSource, enabledSource, listingKey, jobDedupKey, reviewScamSignals, REPORT_HIDE_REASON } = require('./job-catalogue');

const DEMO_JOB_PROVIDER = 'mock_doe';
const JOB_REFRESH_MINUTES = 60;
const MISSING_THRESHOLD = 0.5;
const WORK_MODES = new Set(['onsite', 'hybrid', 'remote']);
const CONTENT_FIELDS = [
  'title', 'organization', 'category', 'map_group', 'loc_precision', 'loc_text', 'lat', 'lng',
  'money_basis', 'money_min', 'money_max', 'money_unit', 'money_known_text',
  'conditions', 'skills', 'for_older', 'expires_at', 'source_url'
];
const LOCATION_FIELDS = ['province', 'district', 'work_mode'];
const POSTING_FIELDS = [...CONTENT_FIELDS, ...LOCATION_FIELDS, 'search_text', 'dedup_key', 'posted_at', 'updated_at', 'fetched_at',
  'suspicious', 'suspicious_reasons', 'content_hash', 'seen_run_id', 'status', 'review_reason'];

class JobFeedError extends Error {}

function cleanText(value) {
  if (value == null) return null;
  if (typeof value !== 'string') throw new JobFeedError('ช่องข้อความไม่ใช่ข้อความ');
  return value.trim().replace(/\s+/g, ' ') || null;
}

function textList(value = []) {
  if (!Array.isArray(value) || !value.every(item => typeof item === 'string')) {
    throw new JobFeedError('เงื่อนไขและทักษะต้องเป็นรายการข้อความ');
  }
  return value.map(cleanText).filter(Boolean);
}

function dateValue(value) {
  const text = cleanText(value);
  if (text === null) return null;
  const time = Date.parse(text);
  if (!/^\d{4}-\d{2}-\d{2}(?:T.*(?:Z|[+-]\d{2}:\d{2}))?$/.test(text) || !Number.isFinite(time)) {
    throw new JobFeedError('วันที่ต้องเป็น ISO-8601');
  }
  return new Date(time).toISOString();
}

function boundedNumber(value, min, max = Infinity) {
  if (value == null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new JobFeedError('ค่าจ้างหรือพิกัดอยู่นอกช่วงที่ใช้ได้');
  }
  return value;
}

function contentHash(row) {
  const values = CONTENT_FIELDS.map(field => {
    const value = row[field];
    if (field === 'conditions') return textList(JSON.parse(value));
    if (field === 'skills') return textList(JSON.parse(value)).sort();
    return typeof value === 'string' ? cleanText(value) : value;
  });
  // Retain the old hash for existing rows whose source has not sent structured location fields.
  if (LOCATION_FIELDS.some(field => row[field] != null)) values.push(...LOCATION_FIELDS.map(field => row[field]));
  return createHash('sha256').update(JSON.stringify(values)).digest('hex');
}

function normalizeJob(item, context) {
  const { now, categories, scamRules, source, allowMockLink } = context;
  if (item == null || typeof item !== 'object') throw new JobFeedError('ประกาศต้องเป็นข้อมูลหนึ่งรายการ');
  const externalId = item.externalId;
  const title = cleanText(item.title);
  if (typeof externalId !== 'string' || !/^[A-Za-z0-9._-]+$/.test(externalId) || !title
      || item.mapGroup !== 'job' || !categories.has(item.category)) {
    throw new JobFeedError('รหัสประกาศ ชื่องาน หรือหมวดงานไม่ถูกต้อง');
  }
  const status = item.status ?? 'active';
  if (!['active', 'closed'].includes(status)) throw new JobFeedError('สถานะประกาศไม่ถูกต้อง');
  if (item.forOlder !== undefined && typeof item.forOlder !== 'boolean') {
    throw new JobFeedError('ข้อมูลการรับผู้สูงอายุต้องเป็น boolean');
  }

  const location = item.location ?? { precision: 'none' };
  const workMode = location.workMode ?? (location.isRemote === true ? 'remote' : null);
  const lat = boundedNumber(location.lat, -90, 90);
  const lng = boundedNumber(location.lng, -180, 180);
  if (!['none', 'city', 'exact'].includes(location.precision)
      || (location.precision === 'exact' && (lat === null || lng === null))) {
    throw new JobFeedError('ระดับตำแหน่งหรือพิกัดไม่ถูกต้อง');
  }
  if (workMode !== null && !WORK_MODES.has(workMode)) throw new JobFeedError('รูปแบบการทำงานไม่ถูกต้อง');

  const money = item.money;
  if (!money || !['official', 'listing', 'none'].includes(money.basis)) {
    throw new JobFeedError('ที่มาของค่าจ้างไม่ถูกต้อง');
  }
  const min = boundedNumber(money.min, 0);
  const max = boundedNumber(money.max, 0);
  if ((money.basis === 'none' && (min !== null || max !== null))
      || (min !== null && max !== null && min > max)) {
    throw new JobFeedError('ช่วงค่าจ้างไม่ถูกต้อง');
  }
  const sourceUrl = cleanText(item.sourceUrl)
    ?? (allowMockLink ? 'https://example.org/mock/' + source.provider + '/' + externalId : null);
  const parsedUrl = sourceUrl && URL.parse(sourceUrl);
  if (!parsedUrl || !['http:', 'https:'].includes(parsedUrl.protocol) || parsedUrl.username || parsedUrl.password) {
    throw new JobFeedError('ลิงก์ต้นทางต้องเป็น HTTP หรือ HTTPS');
  }

  const organization = cleanText(item.organization);
  const conditions = textList(item.conditions);
  const skills = textList(item.skills);
  const expiresAt = dateValue(item.expiresAt);
  const reasons = reviewScamSignals(scamRules, [title, ...conditions, cleanText(item.suspiciousText)].join(' '));
  return {
    externalId,
    title, organization, category: item.category, map_group: item.mapGroup,
    search_text: (title + ' ' + (organization || '')).toLowerCase(),
    dedup_key: jobDedupKey({ title, organization }),
    loc_precision: location.precision, loc_text: cleanText(location.text), lat, lng,
    province: cleanText(location.province), district: cleanText(location.district), work_mode: workMode,
    money_basis: money.basis, money_min: min, money_max: max,
    money_unit: cleanText(money.unit), money_known_text: cleanText(money.knownText),
    conditions: JSON.stringify(conditions), skills: JSON.stringify(skills), for_older: Number(item.forOlder ?? false),
    source_url: sourceUrl, posted_at: dateValue(item.postedAt), updated_at: dateValue(item.updatedAt),
    fetched_at: now, expires_at: expiresAt,
    status: status === 'closed' || !expiresAt || expiresAt > now ? status : 'expired',
    review_reason: null,
    suspicious: Number(reasons.length > 0), suspicious_reasons: JSON.stringify(reasons)
  };
}

async function readMockFeed(file) {
  let payload;
  try {
    const text = await readFile(file, 'utf8');
    payload = JSON.parse(text.replace(/^\uFEFF/, ''));
  } catch {
    throw new JobFeedError('อ่านไฟล์ DEMO / MOCK ไม่สำเร็จ หรือไฟล์ไม่ใช่ JSON');
  }
  if (!Array.isArray(payload?.items) || payload.items.some(item => !item || typeof item.provider !== 'string')) {
    throw new JobFeedError('ฟีด DEMO / MOCK ต้องมี items และ provider ของแต่ละรายการ');
  }
  return { items: payload.items.filter(item => item.provider === DEMO_JOB_PROVIDER) };
}

function writeJobRun(db, source, jobs, { statuses, snapshot = false, now, startedAt = now, result, cursor, unchanged } = {}) {
  const provider = source.provider;
  db.exec('BEGIN IMMEDIATE');
  try {
    const current = readJobSource(db, provider);
    if (!current?.enabled || current.direction !== source.direction || current.data_status !== source.data_status) {
      throw new JobFeedError('แหล่งข้อมูล ' + provider + ' ยังไม่เปิดให้นำเข้า');
    }
    if (current.last_run_id !== source.last_run_id) {
      db.exec('COMMIT');
      return null;
    }
    const previous = unchanged ? [] : db.prepare("SELECT * FROM job_posting WHERE provider = ? AND map_group = 'job'").all(provider);
    const byId = new Map(previous.map(row => [row.external_id, row]));
    const active = previous.filter(row => row.status === 'active');
    const missing = snapshot && !statuses ? active.filter(row => !jobs.has(row.external_id)) : [];
    if (missing.length && missing.length / active.length >= MISSING_THRESHOLD) {
      throw new JobFeedError('จำนวนประกาศที่หายตั้งแต่ 50% คงข้อมูลจากรอบล่าสุด');
    }

    const insert = db.prepare('INSERT INTO job_posting (id, provider, external_id, ' + POSTING_FIELDS.join(', ')
      + ') VALUES (' + Array(POSTING_FIELDS.length + 3).fill('?').join(', ') + ')');
    const update = db.prepare('UPDATE job_posting SET ' + POSTING_FIELDS.map(field => field + ' = ?').join(', ')
      + ", link_status = CASE WHEN source_url = ? THEN link_status ELSE 'unknown' END,"
      + ' link_checked_at = CASE WHEN source_url = ? THEN link_checked_at END, version = version + 1, prev_snapshot = ? WHERE id = ?');
    const seen = db.prepare('UPDATE job_posting SET seen_run_id = ?, fetched_at = ?, content_hash = ?,'
      + ' suspicious = ?, suspicious_reasons = ? WHERE id = ?');
    const markMissing = db.prepare("UPDATE job_posting SET status = 'needs_review', review_reason = 'missing' WHERE id = ?");
    const runId = randomUUID();
    const stats = { new: 0, changed: 0, unchanged: 0, missing: missing.length };
    if (unchanged) stats.feedUnchanged = true;
    const published = new Map();
    if (result) {
      const rows = db.prepare("SELECT p.id, p.source_url, s.data_status FROM job_posting p JOIN job_source s USING (provider)"
        + " WHERE p.provider <> ? AND p.map_group = 'job' AND p.status = 'active' AND p.suspicious = 0"
        + " AND p.link_status <> 'broken' AND (p.expires_at IS NULL OR p.expires_at > ?)"
        + ' AND ' + enabledSource + ' ORDER BY p.rowid').all(provider, now);
      for (const row of rows) {
        const key = listingKey(row.source_url, row.data_status);
        if (!published.has(key)) published.set(key, row.id);
      }
    }
    for (const job of jobs.values()) {
      const old = byId.get(job.externalId);
      job.content_hash = contentHash(job);
      job.seen_run_id = runId;
      const sameContent = old && contentHash(old) === job.content_hash;
      if (source.data_status === 'curated' && job.status === 'active' && !(sameContent && old.status === 'active')) {
        job.status = 'needs_review';
        job.review_reason = sameContent && old.review_reason ? old.review_reason : old ? 'changed' : 'new';
      }
      if (old?.hidden_by_reports) {
        job.suspicious = 1;
        job.suspicious_reasons = JSON.stringify([...JSON.parse(job.suspicious_reasons), REPORT_HIDE_REASON]);
      }

      if (!old) {
        job.updated_at ??= job.posted_at ?? now;
        insert.run(provider + '_' + job.externalId, provider, job.externalId, ...POSTING_FIELDS.map(field => job[field]));
        stats.new++;
      } else if (old.status === job.status && old.review_reason === job.review_reason && sameContent) {
        seen.run(runId, now, job.content_hash, job.suspicious, job.suspicious_reasons, old.id);
        stats.unchanged++;
      } else {
        job.posted_at ??= old.posted_at;
        job.updated_at ??= now;
        update.run(...POSTING_FIELDS.map(field => job[field]), job.source_url, job.source_url, JSON.stringify(old), old.id);
        stats.changed++;
      }
      if (result) {
        const existingId = published.get(listingKey(job.source_url, source.data_status));
        if (existingId && job.status === 'active' && !job.suspicious) result.merged.push({ index: job.index, existingId });
        else result.accepted++;
      }
    }
    for (const row of missing) markMissing.run(row.id);
    if (statuses) {
      const stateChange = db.prepare('UPDATE job_posting SET status = ?, review_reason = ?, version = version + 1, prev_snapshot = ? WHERE id = ?');
      let transitions = 0;
      for (const [id, remoteStatus] of statuses) {
        const old = byId.get(id);
        if (!old || jobs.has(id)) continue;
        const next = remoteStatus === 'active' || remoteStatus === 'closed' ? remoteStatus : 'needs_review';
        const reason = next === 'needs_review' ? (remoteStatus === 'out_of_scope' ? 'changed' : 'missing') : null;
        if (old.status !== next || old.review_reason !== reason) {
          stateChange.run(next, reason, JSON.stringify(old), old.id);
          transitions++;
        }
      }
      stats.reconciled = statuses.size;
      stats.statusChanged = transitions;
    }
    db.prepare("UPDATE job_source SET state = 'ok', error = NULL, last_run_id = ?, last_run_at = ?,"
      + ' last_fetched_at = ?, last_run_stat = ?, sync_cursor = ? WHERE provider = ?')
      .run(runId, startedAt, now, JSON.stringify(stats), cursor ?? source.sync_cursor, provider);
    db.exec('COMMIT');
    return stats;
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}

function createJobSync({ jobDbFile, source, load, categories, scamRules, clock = Date.now }) {
  const { provider, direction, dataStatus } = source;
  let running;
  async function refresh() {
    const db = openJobDatabase(jobDbFile);
    try {
      db.prepare('INSERT INTO job_source (provider, name, kind, direction, attribution, data_status, fetch_url, terms_url,'
        + ' can_store, can_redisplay, commercial_use, approved, checked_by, checked_on)'
        + ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (provider) DO NOTHING')
        .run(provider, source.name, source.kind, direction, source.attribution, dataStatus, source.fetchUrl ?? null,
          source.termsUrl ?? null, source.canStore ?? null, source.canRedisplay ?? null, source.commercialUse ?? null, Number(!!source.approved),
          source.checkedBy ?? null, source.checkedOn ?? null);
      const sourceState = readJobSource(db, provider);
      if (!sourceState.enabled || sourceState.direction !== direction || sourceState.data_status !== dataStatus) {
        throw new JobFeedError('แหล่งข้อมูล ' + provider + ' ยังไม่เปิดให้ซิงก์');
      }
      const start = clock();
      const startedAt = new Date(start).toISOString();
      const cutoff = source.minPollMinutes ? new Date(start - source.minPollMinutes * 60_000).toISOString() : null;
      const { changes } = db.prepare("UPDATE job_source SET state = 'loading', error = NULL, last_run_at = ?"
        + ' WHERE provider = ? AND last_run_id IS ? AND (? IS NULL OR last_run_at IS NULL OR last_run_at <= ?)')
        .run(startedAt, provider, sourceState.last_run_id, cutoff, cutoff);
      if (!changes) return 'skipped: source refreshed recently or another refresh already committed';
      try {
        const tracked = db.prepare("SELECT external_id FROM job_posting WHERE provider = ? AND map_group = 'job'"
          + " AND (status = 'active' OR (status = 'needs_review' AND review_reason = 'missing'))").all(provider);
        const { items, statuses, cursor, unchanged } = await load(tracked.map(row => row.external_id), sourceState);
        const now = new Date(clock()).toISOString();
        const jobs = new Map();
        for (const item of items) {
          const job = normalizeJob(item, { now, categories, scamRules, source: sourceState, allowMockLink: source.allowMockLink });
          if (jobs.has(job.externalId)) throw new JobFeedError('พบรหัสประกาศซ้ำในฟีด ' + provider);
          jobs.set(job.externalId, job);
        }
        const stats = writeJobRun(db, sourceState, jobs, { statuses, snapshot: source.snapshot, now, startedAt, cursor, unchanged });
        return stats ? JSON.stringify(stats) : 'skipped: another refresh already committed';
      } catch (error) {
        const message = error instanceof JobFeedError ? error.message : 'บันทึกข้อมูล ' + provider + ' ลง SQLite ไม่สำเร็จ';
        db.prepare("UPDATE job_source SET state = 'failed', error = ? WHERE provider = ? AND last_run_id IS ? AND last_run_at = ?")
          .run(message, provider, sourceState.last_run_id, startedAt);
        throw new JobFeedError(message);
      }
    } finally {
      db.close();
    }
  }
  return () => {
    running ??= refresh().finally(() => { running = undefined; });
    return running;
  };
}

function createJobPush({ jobDbFile, categories, scamRules }) {
  return function push(provider, dataStatus, items, { closeId } = {}) {
    const db = openJobDatabase(jobDbFile);
    try {
      const source = readJobSource(db, provider);
      if (!source?.enabled || source.direction !== 'push' || (dataStatus != null && dataStatus !== source.data_status)) {
        throw new JobFeedError('แหล่งนี้ยังไม่เปิดรับประกาศ หรือ dataStatus ไม่ตรงกับทะเบียน');
      }
      const now = new Date().toISOString();
      const jobs = new Map();
      const result = { accepted: 0, rejected: [], merged: [] };
      items.forEach((item, index) => {
        try {
          const job = normalizeJob(item, { now, categories, scamRules, source });
          if (jobs.has(job.externalId)) throw new JobFeedError('พบรหัสประกาศซ้ำในชุดนี้');
          jobs.set(job.externalId, { ...job, index });
        } catch (error) {
          if (!(error instanceof JobFeedError)) throw error;
          result.rejected.push({ index, reason: error.message });
        }
      });
      if (jobs.size || closeId != null) {
        const statuses = closeId == null ? undefined : new Map([[closeId, 'closed']]);
        if (!writeJobRun(db, source, jobs, { now, result, statuses })) {
          throw new JobFeedError('มีรอบนำเข้าของแหล่งนี้เสร็จก่อนหน้า กรุณาส่งชุดเดิมอีกครั้ง');
        }
      }
      return result;
    } finally {
      db.close();
    }
  };
}

function createDemoJobSync({ feedFile, source, ...options }) {
  return createJobSync({
    ...options,
    source: { ...source, provider: DEMO_JOB_PROVIDER, direction: 'static', dataStatus: 'mock', snapshot: true, allowMockLink: true,
      attribution: 'DEMO / MOCK (' + DEMO_JOB_PROVIDER + ')' },
    load: () => readMockFeed(feedFile)
  });
}

module.exports = { createJobSync, createDemoJobSync, createJobPush, JobFeedError, DEMO_JOB_PROVIDER, JOB_REFRESH_MINUTES, WORK_MODES };
