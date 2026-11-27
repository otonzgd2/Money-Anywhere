const { readFileSync, statSync } = require('node:fs');
const { join } = require('node:path');

const REPORT_HIDE_REASON = 'ผู้ใช้หลายคนแจ้งว่าน่าสงสัย ซ่อนไว้รอทีมตรวจ';
const BANGKOK_DEMO_PROVIDER = 'mock_bangkok_catalogue';
const BANGKOK_INFO_PATH = '/docs/mockups/opportunity-info.html';
const normalizeJobText = value => String(value || '').toLowerCase().replace(/\(.*?\)/g, '').replace(/[^\p{L}\p{M}\p{N}]+/gu, '');
const jobDedupKey = ({ title, organization }) => normalizeJobText(title) + '|' + normalizeJobText(organization);
const reviewScamSignals = (rules, text) => rules.filter(rule => new RegExp(rule.pattern).test(text)).map(rule => rule.reason);
const enabledSource = "(s.data_status = 'mock' OR (s.approved = 1 AND s.can_store = 1 AND s.can_redisplay = 1))";

function listingKey(sourceUrl, dataStatus) {
  const url = URL.parse(sourceUrl);
  if (!url) return null;
  url.hash = '';
  // Keep all query parameters. They may contain a requisition or branch ID.
  return (dataStatus === 'mock' ? 'mock:' : 'real:') + url.href;
}

function collapseJobListings(items) {
  const groups = new Map();
  for (const item of items) {
    if (item.mapGroup !== 'job') continue;
    const { provider, sourceUrl, dataStatus } = item.provenance;
    const key = listingKey(sourceUrl, dataStatus);
    if (!key) continue;
    let group = groups.get(key);
    if (!group) groups.set(key, group = new Map());
    if (!group.has(provider)) group.set(provider, { item, provider, sourceUrl });
  }
  const grouped = new Map();
  for (const group of groups.values()) {
    if (group.size < 2) continue;
    const [first, ...duplicates] = group.values();
    grouped.set(first.item.id, {
      ...first.item,
      provenance: { ...first.item.provenance, sourceLinks: [...group.values()].map(({ provider, sourceUrl }) => ({ provider, sourceUrl })) }
    });
    for (const { item } of duplicates) grouped.set(item.id, null);
  }
  return items.map(item => grouped.has(item.id) ? grouped.get(item.id) : item).filter(Boolean);
}

function openJobDatabase(file) {
  if (!statSync(file, { throwIfNoEntry: false })?.isFile()) {
    throw new Error('SQLite job catalogue does not exist: ' + file);
  }
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(file);
  try {
    db.exec('PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 3000');
    const hasWorkMode = () => db.prepare("SELECT name FROM pragma_table_info('job_posting') WHERE name = 'work_mode'").get();
    if (!hasWorkMode()) {
      db.exec('BEGIN IMMEDIATE');
      try {
        if (!hasWorkMode()) {
          db.exec(readFileSync(join(__dirname, '../../docs/entities/database-script/002_job_location_filters.sql'), 'utf8'));
        }
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    }
    return db;
  } catch (error) {
    db.close();
    throw error;
  }
}

// SQLite stores nullable fields as NULL, while the API omits absent optional fields.
function toOpportunity(row) {
  return {
    id: row.id,
    title: row.title,
    organization: row.organization ?? undefined,
    category: row.category,
    mapGroup: row.map_group,
    location: {
      precision: row.loc_precision,
      text: row.loc_text ?? undefined,
      province: row.province ?? undefined,
      district: row.district ?? undefined,
      workMode: row.work_mode ?? (row.provider === 'jobicy' ? 'remote' : undefined),
      isRemote: row.work_mode === 'remote' || row.provider === 'jobicy' ? true : undefined,
      lat: row.lat ?? undefined,
      lng: row.lng ?? undefined
    },
    money: {
      basis: row.money_basis,
      min: row.money_min ?? undefined,
      max: row.money_max ?? undefined,
      unit: row.money_unit ?? undefined,
      knownText: row.money_known_text ?? undefined
    },
    conditions: JSON.parse(row.conditions),
    provenance: {
      provider: row.provider,
      dataStatus: row.data_status,
      sourceUrl: row.source_url,
      postedAt: row.posted_at ?? undefined,
      updatedAt: row.updated_at ?? undefined,
      expiresAt: row.expires_at ?? undefined,
      fetchedAt: row.fetched_at,
      attribution: row.attribution,
      linkStatus: row.link_status,
      linkCheckedAt: row.link_checked_at ?? undefined
    },
    suspicious: Boolean(row.suspicious),
    suspiciousReasons: JSON.parse(row.suspicious_reasons),
    checklistTemplateId: row.category,
    skills: JSON.parse(row.skills),
    forOlder: Boolean(row.for_older)
  };
}

function openJobCatalogue(file, { includeBangkokDemo = true } = {}) {
  const db = openJobDatabase(file);
  try {
    const isBangkokDemo = "(s.provider = '" + BANGKOK_DEMO_PROVIDER + "' AND s.data_status = 'mock')";
    const visibleSources = enabledSource + (includeBangkokDemo ? '' : ' AND NOT ' + isBangkokDemo);
    const visibleGroup = "(p.map_group = 'job'" + (includeBangkokDemo ? ' OR ' + isBangkokDemo : '') + ')';
    const visibleListings = "FROM job_posting p JOIN job_source s ON s.provider = p.provider"
      + " WHERE " + visibleSources + " AND " + visibleGroup + " AND p.status = 'active'";
    const selectJobs = 'SELECT p.*, s.data_status, s.attribution ' + visibleListings;
    const list = db.prepare(selectJobs + ' ORDER BY p.rowid');
    const get = db.prepare(selectJobs + ' AND p.id = ?');
    const duplicate = db.prepare('SELECT p.id ' + visibleListings
      + " AND NOT " + isBangkokDemo + " AND p.dedup_key = ? AND p.provider <> ? ORDER BY p.rowid LIMIT 1");
    const sources = db.prepare(
      "SELECT s.provider, s.name, s.kind, s.direction, s.attribution, s.state,"
      + " s.last_fetched_at, s.error, COUNT(p.id) AS item_count"
      + " FROM job_source s LEFT JOIN job_posting p ON p.provider = s.provider AND " + visibleGroup
      + " WHERE " + visibleSources + " GROUP BY s.provider ORDER BY s.rowid"
    );
    const insertReport = db.prepare('INSERT INTO job_report (job_id, device_hash, reason, note, at)'
      + ' SELECT p.id, ?, ?, ?, ? ' + visibleListings + ' AND p.id = ?');
    const hideReportedJob = db.prepare(
      "UPDATE job_posting SET hidden_by_reports = 1, suspicious = 1,"
      + " suspicious_reasons = json_insert(suspicious_reasons, '$[#]', ?)"
      + " WHERE id = ? AND hidden_by_reports = 0 AND"
      + " (SELECT COUNT(DISTINCT device_hash) FROM job_report WHERE job_id = ? AND reason = 'suspicious') >= ?"
    );

    return {
      all: () => list.all().map(toOpportunity),
      get(id) {
        if (id == null) return undefined;
        const row = get.get(id);
        return row && toOpportunity(row);
      },
      findDuplicate: (key, provider) => duplicate.get(key, provider),
      providers: () => db.prepare('SELECT provider FROM job_source').all().map(row => row.provider),
      source: provider => readJobSource(db, provider),
      sources: () => sources.all().map(row => ({
        provider: row.provider, name: row.name, kind: row.kind, direction: row.direction, attribution: row.attribution,
        state: row.state, itemCount: row.item_count, lastFetchedAt: row.last_fetched_at ?? undefined, error: row.error ?? undefined
      })),
      report(id, deviceHash, reason, note, at, threshold) {
        db.exec('BEGIN IMMEDIATE');
        try {
          const { changes } = insertReport.run(deviceHash, reason, note ?? null, at, id);
          if (changes && reason === 'suspicious') hideReportedJob.run(REPORT_HIDE_REASON, id, id, threshold);
          db.exec('COMMIT');
          return Boolean(changes);
        } catch (error) {
          db.exec('ROLLBACK');
          throw error;
        }
      },
      close: () => db.close()
    };
  } catch (error) {
    db.close();
    throw error;
  }
}

function readJobSource(db, provider) {
  return db.prepare('SELECT s.*, ' + enabledSource + ' AS enabled FROM job_source s WHERE s.provider = ?').get(provider);
}

module.exports = { BANGKOK_DEMO_PROVIDER, BANGKOK_INFO_PATH, openJobDatabase, openJobCatalogue, readJobSource, enabledSource, collapseJobListings, listingKey,
  normalizeJobText, jobDedupKey, reviewScamSignals, REPORT_HIDE_REASON };
