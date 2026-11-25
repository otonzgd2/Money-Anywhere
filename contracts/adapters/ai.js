// AI port. One interface, two adapters: rules (always available) and an OpenAI-compatible chat API.
// Guardrails live here, so every caller gets them: candidates only, no money figures, timeout, fallback.
const MONEY_RE = /(฿\s?\d[\d,]*|\d[\d,]*\s?(บาท|baht|THB))/gi;

function stripMoney(s) { return String(s || '').replace(MONEY_RE, '').replace(/\s{2,}/g, ' ').trim(); }

function rulesRank(profile, candidates) {
  const p = profile || {}, skills = (p.skills || []).map(s => s.slice(0, 3)).filter(Boolean);
  const scored = candidates.map(o => {
    let s = 0; const why = [];
    if (o.money.basis !== 'none') { s += 2; why.push('มีตัวเลขค่าตอบแทนจากต้นทาง'); }
    if (skills.some(k => o.title.includes(k))) { s += 3; why.push('ตรงกับทักษะของคุณ'); }
    const g = (p.goals || []).join(' ');
    if ((g.includes('เงิน') && o.mapGroup === 'money') || (g.includes('งาน') && o.mapGroup === 'job') || (g.includes('ทักษะ') && o.mapGroup === 'skill')) { s += 2; why.push('ตรงกับเป้าหมาย'); }
    if ((o.provenance.ageDays || 0) > 30) { s -= 1; why.push('ข้อมูลเก่า ควรตรวจที่ต้นทาง'); }
    const missing = []; if (!p.district) missing.push('พื้นที่'); if (!p.hoursPerWeek) missing.push('เวลาว่าง');
    return { o, s, reason: why.join(' · ') || 'อยู่ในหมวดที่คุณเลือก', missing };
  }).sort((a, b) => b.s - a.s);
  const n = scored.length;
  return scored.map((x, i) => ({ opportunityId: x.o.id, fit: i < n / 3 ? 'high' : i < 2 * n / 3 ? 'good' : 'fair', reason: x.reason, missingInfo: x.missing }));
}

function rulesExplain(subject) {
  if (subject.type === 'task_step') return 'ขั้นนี้: ' + subject.step + ' ลองทำทีละข้อ ถ้ายังติด ให้ติดต่อผู้ประกาศหรือหน่วยงานโดยตรง แอปไม่ดำเนินการแทนคุณ';
  const o = subject.opportunity;
  return 'สรุป: ' + o.title + '. เงื่อนไข: ' + ((o.conditions || []).join(', ') || 'ดูที่ประกาศต้นทาง') + '. สิทธิ์หรือการรับเข้าทำงานจริงตัดสินโดยผู้ประกาศหรือหน่วยงาน';
}

function createAi(opts = {}) {
  const baseUrl = opts.baseUrl !== undefined ? opts.baseUrl : process.env.AI_BASE_URL;
  const apiKey = opts.apiKey !== undefined ? opts.apiKey : process.env.AI_API_KEY;
  const model = opts.model || process.env.AI_MODEL || 'default';
  const timeoutMs = opts.timeoutMs || 8000;
  const fetchImpl = opts.fetch || fetch;
  const configured = !!(baseUrl && apiKey);
  let calls = 0;

  async function chat(system, user) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(baseUrl.replace(/\/$/, '') + '/chat/completions', {
        method: 'POST', signal: ctl.signal,
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + apiKey },
        body: JSON.stringify({ model, temperature: 0, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: system }, { role: 'user', content: user }] })
      });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const j = await res.json();
      return JSON.parse(j.choices[0].message.content);
    } finally { clearTimeout(t); }
  }

  return {
    provider: configured ? 'openai_compatible' : 'rules',
    async rank(profile, candidates) {
      const id = 'ai-' + (++calls) + '-' + Date.now().toString(36);
      if (!configured) return { aiStatus: 'fallback_rules', aiInvocationId: id, ranked: rulesRank(profile, candidates) };
      try {
        const out = await chat(
          'คุณช่วยจัดอันดับโอกาสหารายได้ให้ผู้ใช้ ตอบเป็น JSON {"ranked":[{"opportunityId":"","fit":"high|good|fair","reason":"","missingInfo":[]}]} ใช้เฉพาะ opportunityId ที่ให้ไป ห้ามใส่ตัวเลขเงิน ห้ามรับประกันผลลัพธ์',
          JSON.stringify({ profile, candidates: candidates.map(o => ({ id: o.id, title: o.title, category: o.category, conditions: o.conditions, hasMoney: o.money.basis !== 'none' })) }));
        const allowed = new Set(candidates.map(o => o.id)), seen = new Set();
        const ranked = (out.ranked || []).filter(r => allowed.has(r.opportunityId) && !seen.has(r.opportunityId) && seen.add(r.opportunityId))
          .map(r => ({ opportunityId: r.opportunityId, fit: ['high', 'good', 'fair'].includes(r.fit) ? r.fit : 'fair', reason: stripMoney(r.reason) || 'ตรงกับโปรไฟล์ของคุณ', missingInfo: Array.isArray(r.missingInfo) ? r.missingInfo.map(String) : [] }));
        if (!ranked.length) throw new Error('empty ranking');
        // Candidates the AI skipped are appended by rules so nothing silently disappears.
        const rest = rulesRank(profile, candidates.filter(o => !seen.has(o.id)));
        return { aiStatus: 'ok', aiInvocationId: id, ranked: ranked.concat(rest) };
      } catch (e) { return { aiStatus: 'fallback_rules', aiInvocationId: id, ranked: rulesRank(profile, candidates), error: e.message }; }
    },
    async explain(subject) {
      const id = 'ai-' + (++calls) + '-' + Date.now().toString(36);
      if (!configured) return { aiStatus: 'fallback_rules', aiInvocationId: id, text: rulesExplain(subject) };
      try {
        const out = await chat('อธิบายเป็นภาษาไทยง่ายๆ สั้นๆ สำหรับผู้สูงอายุ ตอบเป็น JSON {"text":""} ห้ามรับประกันเงินหรืองาน ห้ามบอกว่าจะยื่นแทนผู้ใช้', JSON.stringify(subject));
        const text = stripMoney(out.text);
        if (!text) throw new Error('empty text');
        return { aiStatus: 'ok', aiInvocationId: id, text };
      } catch (e) { return { aiStatus: 'fallback_rules', aiInvocationId: id, text: rulesExplain(subject), error: e.message }; }
    }
  };
}

module.exports = { createAi, stripMoney, rulesRank };
