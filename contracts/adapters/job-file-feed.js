const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { readFile } = require('node:fs/promises');
const { dirname, resolve } = require('node:path');
const { JobFeedError, JOB_REFRESH_MINUTES } = require('./job-sync');

const sha256 = value => createHash('sha256').update(value).digest('hex');
const utf8 = new TextDecoder('utf-8', { fatal: true });
const requiredColumns = ['externalId', 'title', 'category', 'sourceUrl'];
const maxIntervalMinutes = Math.floor(0x7fffffff / 60_000);
const partnerProviders = new Set(['jobthai', 'jobsdb', 'jobbkk', 'jobtopgun', 'fastwork']);
const partnerRefreshMinutes = 5;

function csvRows(text) {
  const field = /(?:"((?:[^"]|"")*)"|([^",\r\n]*))(,|\r\n|\n|\r|$)/y;
  const rows = [];
  let row = [];
  while (field.lastIndex < text.length || row.length) {
    const match = field.exec(text);
    if (!match) throw new JobFeedError('รูปแบบ CSV ไม่ถูกต้อง');
    row.push(match[1]?.replace(/""/g, '"') ?? match[2]);
    if (match[3] !== ',') {
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    }
  }
  return rows;
}

const optionalNumber = value => value?.trim() ? Number(value) : undefined;
const optionalList = value => value ? value.split('|') : undefined;

function csvJob(row) {
  return {
    externalId: row.externalId,
    title: row.title,
    organization: row.organization,
    category: row.category,
    mapGroup: 'job',
    sourceUrl: row.sourceUrl,
    status: row.status || undefined,
    postedAt: row.postedAt,
    updatedAt: row.updatedAt,
    expiresAt: row.expiresAt,
    location: {
      precision: row.precision || 'none',
      province: row.province,
      district: row.district,
      workMode: row.workMode || undefined,
      text: row.locationText,
      lat: optionalNumber(row.lat),
      lng: optionalNumber(row.lng)
    },
    money: {
      basis: row.moneyBasis || 'none',
      min: optionalNumber(row.moneyMin),
      max: optionalNumber(row.moneyMax),
      unit: row.moneyUnit,
      knownText: row.moneyKnownText
    },
    conditions: optionalList(row.conditions),
    skills: optionalList(row.skills),
    forOlder: row.forOlder?.trim() ? JSON.parse(row.forOlder.trim().toLowerCase()) : undefined
  };
}

function parseJobs(content, format) {
  try {
    const text = utf8.decode(content);
    if (format === 'json') {
      const value = JSON.parse(text);
      const items = Array.isArray(value) ? value : value?.items;
      if (!Array.isArray(items)) throw new JobFeedError('ฟีด JSON ต้องมีอาร์เรย์รายการงาน');
      return items;
    }
    const [header = [], ...rows] = csvRows(text);
    if (new Set(header).size !== header.length || !requiredColumns.every(column => header.includes(column))
        || rows.some(row => row.length !== header.length)) {
      throw new JobFeedError('หัวตารางหรือจำนวนคอลัมน์ของ CSV ไม่ถูกต้อง');
    }
    return rows.map(row => csvJob(Object.fromEntries(header.map((column, index) => [column, row[index]]))));
  } catch (error) {
    if (error instanceof JobFeedError) throw error;
    throw new JobFeedError('ฟีดต้องเป็นไฟล์ ' + format.toUpperCase() + ' ที่เข้ารหัส UTF-8');
  }
}

function makeFileLoader({ file, format, auth }, fetchImpl) {
  let retryAt = 0;
  return async (_trackedIds, source) => {
    const url = file ? null : URL.parse(source.fetch_url ?? '');
    if (!file && (!url || url.protocol !== 'https:' || url.username || url.password)) {
      throw new JobFeedError('ฟีดออนไลน์ต้องใช้ URL HTTPS ของแหล่งที่ลงทะเบียน');
    }
    const key = sha256(JSON.stringify([file ?? url.href, format]));
    let last;
    try { last = JSON.parse(source.sync_cursor); } catch { /* Older cursor formats are read from the beginning. */ }
    if (last?.key !== key) last = undefined;

    let content, etag, modified;
    if (file) {
      try { content = await readFile(file); }
      catch { throw new JobFeedError('อ่านไฟล์ฟีดงานไม่สำเร็จ'); }
    } else {
      if (Date.now() < retryAt) throw new JobFeedError('ต้นทางขอให้รอก่อนดึงไฟล์อีกครั้ง');
      const headers = { Accept: format === 'csv' ? 'text/csv' : 'application/json', 'User-Agent': 'MoneyAnywhere/1.0 (job feed)' };
      if (auth) {
        const credential = process.env[auth.env]?.trim();
        if (!credential || /[\r\n]/.test(credential)) throw new JobFeedError('ยังไม่มีข้อมูลยืนยันตัวตนที่ใช้เรียกฟีด');
        if (auth.type === 'bearer') headers.Authorization = 'Bearer ' + credential;
        else headers['X-Api-Key'] = credential;
      }
      if (last?.etag) headers['If-None-Match'] = last.etag;
      if (last?.modified) headers['If-Modified-Since'] = last.modified;
      let response;
      try {
        response = await fetchImpl(url.href, { headers, redirect: 'error', signal: AbortSignal.timeout(15000) });
      } catch {
        throw new JobFeedError('เชื่อมต่อฟีดงานไม่สำเร็จ');
      }
      if (response.status === 304 && (last?.etag || last?.modified)) return { items: [], unchanged: true };
      if (!response.ok) {
        const retry = response.headers.get('retry-after');
        if (retry && [429, 503].includes(response.status)) {
          retryAt = /^\d+$/.test(retry) ? Date.now() + Number(retry) * 1000 : Date.parse(retry);
        }
        throw new JobFeedError('ฟีดงานตอบ HTTP ' + response.status);
      }
      etag = response.headers.get('etag');
      modified = response.headers.get('last-modified');
      try { content = new Uint8Array(await response.arrayBuffer()); }
      catch { throw new JobFeedError('อ่านข้อมูลตอบกลับจากฟีดงานไม่สำเร็จ'); }
    }
    const hash = sha256(content);
    const cursor = JSON.stringify({ key, hash, etag, modified });
    if (hash === last?.hash) return { items: [], unchanged: true, cursor };
    return { items: parseJobs(content, format), cursor };
  };
}

function readJobFileFeeds(configFile, fetchImpl = fetch) {
  if (!configFile) return [];
  let config;
  try { config = JSON.parse(readFileSync(configFile, 'utf8').replace(/^\uFEFF/, '')); }
  catch { throw new Error('JOB_FEEDS_FILE ต้องเป็นไฟล์ JSON ที่อ่านได้'); }
  if (!Array.isArray(config)) throw new Error('JOB_FEEDS_FILE ต้องเป็นอาร์เรย์ของแหล่งข้อมูล');
  const providers = new Set();
  return config.flatMap(entry => {
    const { provider, format, file, auth, mock = false, enabled = true } = entry ?? {};
    const isPartner = partnerProviders.has(provider);
    const everyMinutes = entry?.everyMinutes ?? (isPartner ? partnerRefreshMinutes : JOB_REFRESH_MINUTES);
    if (typeof provider !== 'string' || !/^[a-z0-9][a-z0-9_]*$/.test(provider) || providers.has(provider)
        || !['csv', 'json'].includes(format) || (file != null && (typeof file !== 'string' || !file.trim()))
        || typeof enabled !== 'boolean' || typeof mock !== 'boolean' || (mock && (!provider.startsWith('mock_') || !file))
        || (auth != null && (file || !['bearer', 'api-key'].includes(auth.type)
          || typeof auth.env !== 'string' || !/^[A-Z][A-Z0-9_]*$/.test(auth.env)))
        || !Number.isInteger(everyMinutes) || everyMinutes < (isPartner ? partnerRefreshMinutes : 1)
        || everyMinutes > maxIntervalMinutes) {
      throw new Error('รายการแหล่งใน JOB_FEEDS_FILE ไม่ถูกต้องหรือรหัสแหล่งซ้ำ');
    }
    providers.add(provider);
    if (!enabled) return [];
    const location = file ? resolve(dirname(configFile), file) : undefined;
    return [{
      provider, mock, everyMinutes,
      minPollMinutes: isPartner && !location ? everyMinutes : undefined,
      load: makeFileLoader({ file: location, format, auth }, fetchImpl)
    }];
  });
}

module.exports = { readJobFileFeeds };
