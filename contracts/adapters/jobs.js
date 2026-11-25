// In-process scheduler (B3). Good enough for one Demo server; swap for cron or a queue later.
// Each job is { name, everyMinutes, run(ctx) }. Timers are unref'd so they never keep the process alive.
function createJobs(defs) {
  const state = defs.map(d => ({ name: d.name, everyMinutes: d.everyMinutes, enabled: d.enabled !== false, lastRunAt: undefined, lastResult: undefined }));
  const timers = [];
  async function run(name, ctx = {}) {
    const def = defs.find(d => d.name === name), st = state.find(s => s.name === name);
    if (!def) throw new Error('unknown job ' + name);
    try { st.lastResult = String(await def.run(ctx) ?? 'ok'); }
    catch (e) { st.lastResult = 'failed: ' + e.message; }
    st.lastRunAt = new Date().toISOString();
    return st.lastResult;
  }
  return {
    state,
    run,
    start() {
      for (const s of state) if (s.enabled && s.everyMinutes > 0) {
        const t = setInterval(() => run(s.name), s.everyMinutes * 60e3); t.unref(); timers.push(t);
      }
    },
    stop() { timers.splice(0).forEach(clearInterval); }
  };
}
module.exports = { createJobs };
