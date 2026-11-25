// "Where is my money" engine. Deterministic and data-driven: programs, conditions and amounts live in
// fixtures/reference.json (moneyPrograms), so rules are versioned and testable without code changes.
// The result never claims official eligibility. Only a government adapter can return status "verified".
const OPS = {
  eq: (a, b) => a === b, neq: (a, b) => a !== b,
  gt: (a, b) => typeof a === 'number' && a > b, gte: (a, b) => typeof a === 'number' && a >= b,
  lt: (a, b) => typeof a === 'number' && a < b, in: (a, b) => Array.isArray(b) && b.includes(a)
};

function amountOf(p, facts) {
  const a = p.amount || { type: 'none' };
  if (a.type === 'table') { const v = a.table[facts[a.fact]]; return v ? { basis: 'rate', value: v, unit: a.unit, note: a.note } : { basis: 'none', note: a.note, needsFact: facts[a.fact] === undefined ? a.fact : undefined }; }
  if (a.type === 'pct_capped') { const w = facts[a.fact]; return typeof w === 'number' && w > 0 ? { basis: 'calc', value: Math.round(Math.min(w, a.cap) * a.pct), unit: a.unit, note: a.note } : { basis: 'none', note: 'ใส่ข้อมูลเพื่อคำนวณ', needsFact: a.fact }; }
  if (a.type === 'product') {
    const missing = a.facts.find(f => typeof facts[f] !== 'number');
    return missing ? { basis: 'none', note: 'ใส่ข้อมูลเพื่อคำนวณ', needsFact: missing } : { basis: 'calc', value: a.facts.reduce((x, f) => x * facts[f], 1), unit: a.unit, note: a.note };
  }
  return { basis: 'none', note: a.note || 'ไม่ทราบยอด' };
}

function createMoney(ref) {
  const programs = ref.moneyPrograms, factDefs = ref.facts;
  const question = f => ({ fact: f, question: factDefs[f].question, type: factDefs[f].type, options: factDefs[f].options });

  function evaluate(p, facts, govData) {
    const g = govData && govData[p.id];
    if (g) return { status: 'verified', reasons: [{ ok: true, text: 'ข้อมูลจากหน่วยงานผ่าน ThaID' }], amount: { basis: 'verified', value: g.amount, unit: p.kind === 'monthly' ? 'บาท/เดือน' : 'บาท', note: g.text }, dataStatus: g.mock ? 'mock' : 'live' };
    const reasons = [];
    for (const c of p.conditions) {
      if (facts[c.fact] === undefined) return { status: 'need', reasons, nextQuestion: question(c.fact), amount: amountOf(p, facts), dataStatus: 'mock' };
      const ok = OPS[c.op](facts[c.fact], c.value); reasons.push({ ok, text: c.label });
      if (!ok) return { status: 'unlikely', reasons, amount: { basis: 'none', note: 'ตามข้อมูลที่ให้มา ไม่น่าจะมีสิทธิ์' }, dataStatus: 'mock' };
    }
    (p.unknowns || []).forEach(t => reasons.push({ ok: null, text: t }));
    const amount = amountOf(p, facts);
    return { status: p.resultIfMet || 'likely', reasons, amount, nextQuestion: amount.needsFact ? question(amount.needsFact) : undefined, dataStatus: 'mock' };
  }

  const item = (p, e) => ({ id: p.id, title: p.title, icon: p.icon, kind: p.kind, payer: p.payer, status: e.status, amount: strip(e.amount), reasons: e.reasons, nextQuestion: e.nextQuestion, rulesVersion: p.version, dataStatus: e.dataStatus });
  const strip = a => { const { needsFact, ...rest } = a; return rest; };

  return {
    programs,
    list(facts, govData) {
      const items = programs.map(p => item(p, evaluate(p, facts, govData)));
      const counted = items.filter(i => ['likely', 'verified'].includes(i.status) && typeof i.amount.value === 'number');
      const sum = k => counted.filter(i => i.kind === k).reduce((s, i) => s + i.amount.value, 0);
      return { summary: { monthly: sum('monthly'), once: sum('once'), allVerified: counted.length > 0 && counted.every(i => i.status === 'verified'), counted: counted.length, pending: items.filter(i => ['need', 'check'].includes(i.status)).length }, items };
    },
    route(id, facts, govData, docsReady = []) {
      const p = programs.find(x => x.id === id); if (!p) return null;
      const e = evaluate(p, facts, govData), base = item(p, e);
      const letter = p.letter ? p.letter.replace('{unpaidDays}', facts.unpaidDays ?? '...').replace('{amount}', typeof e.amount.value === 'number' ? e.amount.value.toLocaleString('th-TH') + ' บาท' : '...') : undefined;
      return { ...base, documents: p.docs.map((t, i) => ({ index: i, text: t, ready: docsReady.includes(i) })), channels: p.channels, after: p.after, ifNo: p.ifNo, letterTemplate: letter, claimable: !['unlikely', 'need'].includes(e.status), sourceNote: 'เกณฑ์ อัตรา เอกสาร และช่องทางเป็นตัวอย่าง ต้องตรวจกับหน่วยงานก่อนใช้จริง' };
    },
    validateFacts(patch) {
      const errors = [], clean = {};
      for (const [k, v] of Object.entries(patch || {})) {
        const d = factDefs[k]; if (!d) { errors.push(k + ': ไม่รู้จัก'); continue; }
        if (v === null) { clean[k] = undefined; continue; }
        if (d.type === 'enum' && !d.options.includes(v)) errors.push(k + ': ต้องเป็นหนึ่งใน ' + d.options.join(', '));
        else if (d.type === 'bool' && typeof v !== 'boolean') errors.push(k + ': ต้องเป็น true/false');
        else if (d.type === 'number' && (typeof v !== 'number' || v < d.min || v > d.max)) errors.push(k + ': ต้องเป็นตัวเลข ' + d.min + '-' + d.max);
        else clean[k] = v;
      }
      return { errors, clean };
    },
    claimSteps(id) { const p = programs.find(x => x.id === id); return p ? ['เตรียมเอกสาร', p.channels[0].title, 'ติดตามผล', 'ได้รับเงิน (ผู้ใช้แจ้ง)'] : null; }
  };
}
module.exports = { createMoney };
