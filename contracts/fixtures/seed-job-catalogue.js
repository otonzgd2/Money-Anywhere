const { createHash } = require('node:crypto');
const catalogue = require('./opportunities-mock.json');
const { sources, scamRules } = require('./reference.json');
const { openJobDatabase, jobDedupKey, reviewScamSignals } = require('../adapters/job-catalogue');

function seedDemoJobs(file, now = new Date()) {
  const db = openJobDatabase(file);
  try {
    const jobs = catalogue.items.filter(item => item.mapGroup === 'job');
    const providers = new Map(sources.map(source => [source.provider, source]));
    const jobProviders = new Set(jobs.map(job => job.provider));
    const insertSource = db.prepare(
      "INSERT INTO job_source (provider, name, kind, direction, attribution, data_status, state)"
      + " VALUES (?, ?, ?, 'static', ?, 'mock', 'static') ON CONFLICT (provider) DO NOTHING"
    );
    const storedSource = db.prepare('SELECT direction, data_status FROM job_source WHERE provider = ?');
    const insertJob = db.prepare(
      'INSERT INTO job_posting (id, provider, external_id, title, organization, category, map_group, search_text, dedup_key,'
      + ' loc_precision, loc_text, lat, lng, money_basis, money_min, money_max, money_unit, money_known_text,'
      + ' conditions, skills, for_older, source_url, fetched_at, updated_at, suspicious, suspicious_reasons, content_hash)'
      + ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
      + ' ON CONFLICT (provider, external_id) DO NOTHING'
    );
    let inserted = 0;
    db.exec('BEGIN IMMEDIATE');
    try {
      for (const provider of jobProviders) {
        const source = providers.get(provider);
        if (!source || source.attribution !== 'DEMO / MOCK') {
          throw new Error('Expected a registered demo source: ' + provider);
        }
        insertSource.run(provider, source.name, source.kind, source.attribution + ' (' + provider + ')');
        const existing = storedSource.get(provider);
        if (existing.direction !== 'static' || existing.data_status !== 'mock') {
          throw new Error('Cannot seed demo jobs into a non-demo source: ' + provider);
        }
      }
      for (const item of jobs) {
        const { provider, externalId, title, organization, category, mapGroup, location, money, conditions, skills, forOlder, ageDays } = item;
        const reasons = reviewScamSignals(scamRules, [title, ...conditions, item.suspiciousText || ''].join(' '));
        // Seed is insert-only. This checksum identifies the complete fixture record, not an ingest comparison.
        const fixtureHash = createHash('sha256').update(JSON.stringify(item)).digest('hex');
        const result = insertJob.run(
          provider + '_' + externalId, provider, externalId, title, organization ?? null, category, mapGroup,
          (title + ' ' + (organization || '')).toLowerCase(), jobDedupKey(item),
          location.precision, location.text ?? null, location.lat ?? null, location.lng ?? null,
          money.basis, money.min ?? null, money.max ?? null, money.unit ?? null, money.knownText ?? null,
          JSON.stringify(conditions), JSON.stringify(skills), Number(forOlder),
          'https://example.org/mock/' + provider + '/' + externalId, now.toISOString(),
          new Date(now.getTime() - ageDays * 864e5).toISOString(), Number(reasons.length > 0), JSON.stringify(reasons), fixtureHash
        );
        inserted += result.changes;
      }
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
    return { providers: jobProviders.size, fixtures: jobs.length, inserted };
  } finally {
    db.close();
  }
}

module.exports = { seedDemoJobs };

if (require.main === module) {
  const file = process.argv[2];
  if (!file) {
    console.error('Usage: node contracts/fixtures/seed-job-catalogue.js <catalogue.db>');
    process.exitCode = 1;
  } else {
    const { providers, fixtures, inserted } = seedDemoJobs(file);
    console.log('DEMO / MOCK: ' + providers + ' sources, ' + fixtures + ' fixture jobs, ' + inserted + ' inserted');
  }
}
