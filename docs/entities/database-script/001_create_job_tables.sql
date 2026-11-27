-- Initial SQLite schema for the job catalogue.
-- Sources: database-spec/job_source.md, job_posting.md, and job_report.md.
-- Enable foreign keys on each connection that writes to this database.
PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

-- One row per provider, with source permissions and sync state.
CREATE TABLE IF NOT EXISTS job_source (
  provider         TEXT NOT NULL PRIMARY KEY, -- Stable provider code.
  name             TEXT NOT NULL, -- Display name.
  kind             TEXT NOT NULL, -- Source type label.
  direction        TEXT NOT NULL CHECK (direction IN ('pull', 'push', 'static')), -- How data arrives.
  attribution      TEXT NOT NULL, -- Source credit to display.
  data_status      TEXT NOT NULL CHECK (data_status IN ('live', 'curated', 'open_data', 'mock')), -- Default provenance status.
  fetch_url        TEXT, -- Endpoint for pull sources.
  state            TEXT NOT NULL DEFAULT 'idle' CHECK (state IN ('ok', 'failed', 'loading', 'static', 'idle')), -- Latest fetch state.
  last_fetched_at  TEXT, -- Last successful fetch in UTC.
  error            TEXT, -- Latest fetch error with secrets removed.
  terms_url        TEXT, -- Link to the source terms.
  can_store        INTEGER CHECK (can_store IN (0, 1)), -- Permission to store; NULL means unchecked.
  can_redisplay    INTEGER CHECK (can_redisplay IN (0, 1)), -- Permission to display; NULL means unchecked.
  commercial_use   INTEGER CHECK (commercial_use IN (0, 1)), -- Commercial permission; NULL means unchecked.
  approved         INTEGER NOT NULL DEFAULT 0 CHECK (approved IN (0, 1)), -- Source use approval.
  checked_by       TEXT, -- Person who checked the terms.
  checked_on       TEXT, -- Date when the terms were checked.
  sync_cursor      TEXT, -- Source cursor, ETag, or Last-Modified value.
  last_run_id      TEXT, -- Identifier of the last completed sync.
  last_run_at      TEXT, -- Start time of the latest sync attempt.
  last_run_stat    TEXT CHECK (last_run_stat IS NULL OR json_valid(last_run_stat)) -- JSON summary of the last completed sync.
);

-- One row per opportunity; the public ID remains provider_externalId.
CREATE TABLE IF NOT EXISTS job_posting (
  id                  TEXT NOT NULL PRIMARY KEY, -- Public opportunity ID.
  provider            TEXT NOT NULL REFERENCES job_source(provider), -- Source provider.
  external_id         TEXT NOT NULL, -- Identifier assigned by the provider.
  title               TEXT NOT NULL, -- Posting title.
  organization        TEXT, -- Employer or publisher name.
  category            TEXT NOT NULL, -- Opportunity taxonomy category.
  map_group           TEXT NOT NULL, -- Group used by the map and list filters.
  search_text         TEXT NOT NULL, -- Normalized title and organization for search.
  dedup_key           TEXT NOT NULL, -- Normalized title and organization for cross-provider matching.

  loc_precision       TEXT NOT NULL DEFAULT 'none' CHECK (loc_precision IN ('exact', 'city', 'none')), -- Precision of the location.
  loc_text            TEXT, -- Location label or address.
  lat                 REAL, -- Latitude.
  lng                 REAL, -- Longitude.

  money_basis         TEXT NOT NULL CHECK (money_basis IN ('official', 'listing', 'none')), -- Origin of the payment figures.
  money_min           REAL, -- Lower amount in Thai baht.
  money_max           REAL, -- Upper amount in Thai baht.
  money_unit          TEXT, -- Pay period or unit.
  money_known_text    TEXT, -- Information available when the amount is unknown.

  conditions          TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(conditions)), -- Conditions as JSON text.
  skills              TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(skills)), -- Required skills as JSON text.
  for_older           INTEGER NOT NULL DEFAULT 0 CHECK (for_older IN (0, 1)), -- Whether older applicants are welcome.

  source_url          TEXT NOT NULL, -- Original link.
  posted_at           TEXT, -- Publication time in UTC.
  updated_at          TEXT, -- Last update at the source in UTC.
  expires_at          TEXT, -- Closing or expiration time in UTC.
  fetched_at          TEXT NOT NULL, -- Last fetch or receipt time in UTC.
  link_status         TEXT NOT NULL DEFAULT 'unknown' CHECK (link_status IN ('ok', 'broken', 'unknown')), -- Last known link status.
  link_checked_at     TEXT, -- Last link check time in UTC.

  suspicious          INTEGER NOT NULL DEFAULT 0 CHECK (suspicious IN (0, 1)), -- Suspicion flag.
  suspicious_reasons  TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(suspicious_reasons)), -- Reasons as JSON text.
  hidden_by_reports   INTEGER NOT NULL DEFAULT 0 CHECK (hidden_by_reports IN (0, 1)), -- Whether enough distinct devices reported the item.

  status              TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'needs_review', 'closed', 'expired')), -- Posting lifecycle state.
  content_hash        TEXT NOT NULL, -- Hash used to detect changes during ingest.
  seen_run_id         TEXT, -- Last sync run in which the source returned this item.
  version             INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1), -- Current version number.
  prev_snapshot       TEXT CHECK (prev_snapshot IS NULL OR json_valid(prev_snapshot)), -- Previous version as JSON text.
  review_reason       TEXT CHECK (review_reason IS NULL OR review_reason IN ('new', 'changed', 'missing')), -- Why the posting needs review.
  verified_at         TEXT, -- Last human verification time in UTC.
  verified_by         TEXT, -- Person who verified the posting.

  UNIQUE (provider, external_id),
  CHECK (loc_precision <> 'exact' OR (lat IS NOT NULL AND lng IS NOT NULL)),
  CHECK (status <> 'needs_review' OR review_reason IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_job_filter ON job_posting (status, suspicious, map_group, category);
CREATE INDEX IF NOT EXISTS idx_job_geo    ON job_posting (lat, lng) WHERE loc_precision = 'exact';
CREATE INDEX IF NOT EXISTS idx_job_dedup  ON job_posting (dedup_key);
CREATE INDEX IF NOT EXISTS idx_job_prov   ON job_posting (provider, seen_run_id);
CREATE INDEX IF NOT EXISTS idx_job_review ON job_posting (status, provider) WHERE status = 'needs_review';

-- One row per report. Store a device hash rather than the raw device ID.
CREATE TABLE IF NOT EXISTS job_report (
  id           INTEGER PRIMARY KEY AUTOINCREMENT, -- Report ID.
  job_id       TEXT NOT NULL REFERENCES job_posting(id) ON DELETE CASCADE, -- Reported posting.
  device_hash  TEXT NOT NULL, -- SHA-256 device hash prefix (12 hex characters).
  reason       TEXT NOT NULL CHECK (reason IN ('suspicious', 'wrong_info', 'expired', 'other')), -- Report category.
  note         TEXT, -- Optional note for reviewers.
  at           TEXT NOT NULL -- Report receipt time in UTC.
);

CREATE INDEX IF NOT EXISTS idx_report_job ON job_report (job_id, reason);

COMMIT;
