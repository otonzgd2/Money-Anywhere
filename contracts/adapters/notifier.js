// Notifier port. Memory adapter for the mock; swap for FCM or on-device notifications later.
function createNotifier() {
  const jobs = [];
  return {
    schedule(deviceId, taskId, at) { this.cancel(deviceId, taskId); jobs.push({ deviceId, taskId, at }); },
    cancel(deviceId, taskId) { for (let i = jobs.length - 1; i >= 0; i--) if (jobs[i].deviceId === deviceId && (!taskId || jobs[i].taskId === taskId)) jobs.splice(i, 1); },
    list(deviceId) { return jobs.filter(j => j.deviceId === deviceId); }
  };
}
module.exports = { createNotifier };
