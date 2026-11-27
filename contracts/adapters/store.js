// Storage port (ADR-001). The server keeps working state in memory and hands a snapshot here after each change.
//   memory: nothing is written, state is lost on restart (contract tests).
//   file:   one JSON file, written atomically (Demo). Set DATA_FILE.
// A Postgres adapter later implements the same load/save/archive trio.
//
// Layout v2 (docs/design/data-storage.md): every device record is split into COLLECTIONS so each part can move
// to its own server or database later without changing the API. Today all collections live in one file.
//   identity  data from the government connection (ThaID). Never archived; deleted on disconnect.
//   profile   what the person told us: profile, facts, settings, documents ready
//   activity  consents (history), tasks, task events, AI memory items
//   runtime   short-lived working state: sessions, conversations, idempotency cache, counters
// Retention (RETENTION_DAYS, RETENTION_MODE) archives or deletes devices that were not seen for N days.
// Archive keeps only profile + activity, one JSON line per device in ARCHIVE_FILE (default DATA_FILE + .archive.jsonl).
const fs = require('fs');
const path = require('path');

const COLLECTIONS = {
  identity: ['gov', 'demoProfile'],
  profile: ['profile', 'facts', 'answerDetails', 'taxAnswers', 'settings', 'docsReady'],
  activity: ['consents', 'tasks', 'events', 'memory'],
  runtime: ['sessions', 'conversations', 'idem', 'seq', 'lastSeenAt', 'aiUse']
};
const ARCHIVED = ['profile', 'activity'];
const LAYOUT = 2;

// Unknown keys go to runtime, so a new field is never lost when the layout is older than the code.
function packDevice(id, d) {
  const known = new Set(Object.values(COLLECTIONS).flat());
  const rec = { id };
  for (const [c, keys] of Object.entries(COLLECTIONS)) rec[c] = Object.fromEntries(keys.filter(k => d[k] !== undefined).map(k => [k, d[k]]));
  for (const [k, v] of Object.entries(d)) if (!known.has(k)) rec.runtime[k] = v;
  return rec;
}
function unpackDevice(rec) {
  return [rec.id, Object.assign({}, ...Object.keys(COLLECTIONS).map(c => rec[c] || {}))];
}
// Reads layout 1 ([id, device] pairs) and layout 2 (packed records).
function readDevices(saved) {
  if (!saved || !Array.isArray(saved.devices)) return [];
  return saved.devices.map(x => Array.isArray(x) ? x : unpackDevice(x));
}
function archiveRecord(rec, reason, at) {
  return { archivedAt: at, reason, layout: LAYOUT, id: rec.id, ...Object.fromEntries(ARCHIVED.map(c => [c, rec[c]])) };
}

// Maps (idempotency cache) do not survive JSON, so tag them.
const replacer = (k, v) => v instanceof Map ? { __map: [...v] } : v;
const reviver = (k, v) => v && typeof v === 'object' && Array.isArray(v.__map) ? new Map(v.__map) : v;

function createStore(opts = {}) {
  const file = opts.file !== undefined ? opts.file : process.env.DATA_FILE;
  if (!file) {
    const archived = [];
    return { kind: 'memory', layout: LAYOUT, load: () => null, save: () => {}, archive: recs => { archived.push(...recs); }, archived };
  }
  const archiveFile = opts.archiveFile || process.env.ARCHIVE_FILE || file + '.archive.jsonl';
  return {
    kind: 'file',
    layout: LAYOUT,
    file,
    archiveFile,
    load() {
      if (!fs.existsSync(file)) return null;
      try { return JSON.parse(fs.readFileSync(file, 'utf8'), reviver); }
      catch (e) {
        // A broken file must not stop the demo: keep it aside and start empty.
        const bad = file + '.broken-' + Date.now();
        fs.renameSync(file, bad);
        console.error('store: could not read ' + file + ', moved to ' + bad + ': ' + e.message);
        return null;
      }
    },
    save(snapshot) {
      fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
      const tmp = file + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(snapshot, replacer));
      fs.renameSync(tmp, file);
    },
    archive(recs) {
      if (!recs.length) return;
      fs.mkdirSync(path.dirname(path.resolve(archiveFile)), { recursive: true });
      fs.appendFileSync(archiveFile, recs.map(r => JSON.stringify(r, replacer)).join('\n') + '\n');
    }
  };
}
module.exports = { createStore, packDevice, unpackDevice, readDevices, archiveRecord, COLLECTIONS, ARCHIVED, LAYOUT };
