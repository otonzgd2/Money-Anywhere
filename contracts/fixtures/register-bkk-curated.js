const { openJobDatabase } = require('../adapters/job-catalogue');

const [file, reviewer, checkedOn] = process.argv.slice(2);
const date = new Date(checkedOn);
if (!file || !reviewer?.trim() || !/^\d{4}-\d{2}-\d{2}$/.test(checkedOn)
    || Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== checkedOn) {
  console.error('Usage: node contracts/fixtures/register-bkk-curated.js <catalogue.db> "<reviewer>" <YYYY-MM-DD>');
  process.exit(1);
}

const db = openJobDatabase(file);
try {
  const checkedBy = reviewer.trim();
  const attribution = 'ทะเบียนแหล่งประกาศงานกรุงเทพฯ · ตรวจโดย ' + checkedBy + ' · ' + checkedOn;
  const result = db.prepare(`
    INSERT INTO job_source (
      provider, name, kind, direction, attribution, data_status, can_store, can_redisplay, approved, checked_by, checked_on
    ) VALUES ('bkk_curated', 'ประกาศงานกรุงเทพฯ ที่ตรวจแล้ว', 'ฟีด CSV ที่ทีมตรวจ', 'pull', ?, 'curated', 1, 1, 1, ?, ?)
    ON CONFLICT(provider) DO UPDATE SET
      attribution = excluded.attribution,
      can_store = excluded.can_store,
      can_redisplay = excluded.can_redisplay,
      approved = excluded.approved,
      checked_by = excluded.checked_by,
      checked_on = excluded.checked_on
    WHERE job_source.direction = 'pull' AND job_source.data_status = 'curated'
      AND (job_source.checked_on IS NULL OR job_source.checked_on <= excluded.checked_on)
  `).run(attribution, checkedBy, checkedOn);
  if (result.changes !== 1) throw new Error('bkk_curated มีชนิดข้อมูลไม่ตรงกัน หรือมีวันตรวจใหม่กว่า');
  console.log('ลงทะเบียน bkk_curated แล้ว (' + checkedOn + ')');
} finally {
  db.close();
}
