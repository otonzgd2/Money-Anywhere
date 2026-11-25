// Opportunity source port (pull). Each adapter: fetch(fetchImpl) -> OpportunityInput[] in common fields.
const ADAPTERS = {
  greenhouse: {
    url: 'https://boards-api.greenhouse.io/v1/boards/agoda/jobs',
    map: j => (j.jobs || []).map(x => ({ externalId: String(x.id), title: x.title, organization: x.company_name, category: 'job_full', mapGroup: 'job',
      location: { precision: 'city', text: x.location && x.location.name }, money: { basis: 'none', knownText: 'API ไม่ส่งค่าจ้างมา ดูที่ประกาศต้นทาง' },
      conditions: ['ต้นทางระบุที่ตั้งระดับเมือง จึงไม่ปักหมุด'], sourceUrl: x.absolute_url, updatedAt: x.updated_at }))
  },
  lever: {
    url: 'https://api.lever.co/v0/postings/Coda?mode=json',
    map: j => (Array.isArray(j) ? j : []).map(x => ({ externalId: x.id, title: x.text, organization: 'Coda', category: 'job_full', mapGroup: 'job',
      location: { precision: 'city', text: x.categories && x.categories.location }, money: { basis: 'none', knownText: 'API ไม่ส่งค่าจ้างมา ดูที่ประกาศต้นทาง' },
      conditions: ['ต้นทางระบุที่ตั้งระดับเมือง จึงไม่ปักหมุด'], sourceUrl: x.hostedUrl, updatedAt: x.createdAt ? new Date(x.createdAt).toISOString() : undefined }))
  }
};
// Keep only Bangkok rows with a link. Agoda lists some rows as "Bangkok, Malaysia", which are dropped.
const inBangkok = r => /bangkok/i.test((r.location && r.location.text) || '') && !/malaysia/i.test(r.location.text) && r.sourceUrl && r.title;

async function pull(provider, fetchImpl = fetch, timeoutMs = 10000) {
  const a = ADAPTERS[provider]; if (!a) throw new Error('unknown provider ' + provider);
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const res = await fetchImpl(a.url, { signal: ctl.signal });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const rows = a.map(await res.json());
    return { total: rows.length, items: rows.filter(inBangkok) };
  } finally { clearTimeout(t); }
}

module.exports = { pull, providers: Object.keys(ADAPTERS) };
