// Storage port (ADR-001). The server keeps working state in memory and hands a snapshot here after each change.
//   memory: nothing is written, state is lost on restart (contract tests).
//   file:   one JSON file, written atomically (Demo). Set DATA_FILE.
// A Postgres adapter later implements the same load/save pair (e.g. one JSONB row per device).
const fs = require('fs');
const path = require('path');

// Maps (idempotency cache) do not survive JSON, so tag them.
const replacer = (k, v) => v instanceof Map ? { __map: [...v] } : v;
const reviver = (k, v) => v && typeof v === 'object' && Array.isArray(v.__map) ? new Map(v.__map) : v;

function createStore(opts = {}) {
  const file = opts.file !== undefined ? opts.file : process.env.DATA_FILE;
  if (!file) return { kind: 'memory', load: () => null, save: () => {} };
  return {
    kind: 'file',
    file,
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
    }
  };
}
module.exports = { createStore };
