// Notifier port. Memory adapter for the mock: due reminders are "delivered" into a sent log (and printed when debug).
// Swap for FCM (needs a Firebase project and the app's google-services.json) or on-device notifications later.
function createNotifier(opts = {}) {
  const jobs = [], sent = [];
  return {
    kind: 'mock',
    schedule(deviceId, taskId, at) { this.cancel(deviceId, taskId); jobs.push({ deviceId, taskId, at }); },
    cancel(deviceId, taskId) { for (let i = jobs.length - 1; i >= 0; i--) if (jobs[i].deviceId === deviceId && (!taskId || jobs[i].taskId === taskId)) jobs.splice(i, 1); },
    list(deviceId) { return jobs.filter(j => j.deviceId === deviceId); },
    all() { return jobs.slice(); },
    restore(list) { jobs.splice(0, jobs.length, ...(list || [])); },
    // Deliver everything due at `now`. Returns how many were sent.
    dispatch(now = Date.now(), text = () => 'ถึงเวลาทำขั้นต่อไปแล้ว') {
      let n = 0;
      for (let i = jobs.length - 1; i >= 0; i--) {
        if (new Date(jobs[i].at).getTime() > now) continue;
        const j = jobs.splice(i, 1)[0], msg = { ...j, text: text(j), sentAt: new Date(now).toISOString(), channel: 'mock' };
        sent.push(msg); n++;
        if (opts.debug) console.log('notify (mock) ' + j.deviceId + ' ' + j.taskId + ': ' + msg.text);
      }
      return n;
    },
    sent
  };
}
module.exports = { createNotifier };
