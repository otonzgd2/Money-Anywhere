// "Where is my money" engine. Deterministic and data-driven: programs, conditions and amounts live in
// fixtures/reference.json (moneyPrograms), so rules are versioned and testable without code changes.
// The result never claims official eligibility. Only a government adapter can return status "verified".
const OPS = {
  eq: (a, b) => a === b, neq: (a, b) => a !== b,
  gt: (a, b) => typeof a === 'number' && a > b, gte: (a, b) => typeof a === 'number' && a >= b,
  lt: (a, b) => typeof a === 'number' && a < b, in: (a, b) => Array.isArray(b) && b.includes(a),
  present: a => typeof a === 'string' && a.trim().length > 0
};

function amountOf(p, facts) {
  const a = p.amount || { type: 'none' };
  if (a.type === 'table') { const v = a.table[facts[a.fact]]; return v ? { basis: 'rate', value: v, unit: a.unit, note: a.note } : { basis: 'none', note: a.note, needsFact: facts[a.fact] === undefined ? a.fact : undefined }; }
  if (a.type === 'fixed') return { basis: 'rate', value: a.value, unit: a.unit, note: a.note };
  if (a.type === 'rate_plus') {
    // Base rate shown at once; the bonus is added only when its fact is known (e.g. +200 with a State Welfare Card).
    const known = facts[a.plus.fact] !== undefined, add = facts[a.plus.fact] === a.plus.when ? a.plus.value : 0;
    return { basis: 'rate', value: a.base + add, unit: a.unit, note: a.note + (add ? ' ' + a.plus.note : ''), needsFact: known ? undefined : a.plus.fact };
  }
  if (a.type === 'pct_capped') {
    // pctBy picks the rate from another fact (e.g. dismissed 60% vs resigned 30%); noteBy explains that rate.
    const w = facts[a.fact], key = a.pctBy ? facts[a.pctBy.fact] : undefined;
    const pct = a.pctBy ? a.pctBy.table[key] : a.pct, note = (a.noteBy && a.noteBy[key]) || a.note;
    if (typeof pct !== 'number') return { basis: 'none', note: 'อัตราขึ้นกับคำตอบข้ออื่น', needsFact: a.pctBy.fact };
    return typeof w === 'number' && w > 0 ? { basis: 'calc', value: Math.round(Math.min(w, a.cap) * pct), unit: a.unit, note } : { basis: 'none', note: 'ใส่ข้อมูลเพื่อคำนวณ · ' + note, needsFact: a.fact };
  }
  if (a.type === 'product') {
    const missing = a.facts.find(f => typeof facts[f] !== 'number');
    return missing ? { basis: 'none', note: 'ใส่ข้อมูลเพื่อคำนวณ', needsFact: missing } : { basis: 'calc', value: a.facts.reduce((x, f) => x * facts[f], 1), unit: a.unit, note: a.note };
  }
  return { basis: 'none', note: a.note || 'ไม่ทราบยอด' };
}

function createMoney(ref) {
  const programs = ref.moneyPrograms, factDefs = ref.facts;
  const question = f => ({ fact: f, question: factDefs[f].question, type: factDefs[f].type, options: factDefs[f].options, help: factDefs[f].help });

  function evaluate(p, facts, govData) {
    const g = govData && govData[p.id];
    if (g) return { status: 'verified', reasons: [{ ok: true, text: 'ข้อมูลจากหน่วยงานผ่าน ThaID' }], amount: { basis: 'verified', value: g.amount, unit: p.kind === 'monthly' ? 'บาท/เดือน' : 'บาท', note: g.text }, dataStatus: g.mock ? 'mock' : 'live' };
    const reasons = [];
    if (p.id === 'old_age' && facts.oldAgeGets === true || p.id === 'disability' && facts.disabilityGets === true) {
      const h = p.haveIf || { label: 'ได้รับอยู่แล้ว', note: 'ติดต่อท้องถิ่นตามทะเบียนบ้านเพื่อตรวจรอบและยอดโอน' };
      return { status: 'check', alreadyReceiving: true, reasons: [{ ok: true, text: h.label }, { ok: null, text: h.note }],
        amount: { ...amountOf(p, facts), note: h.note, needsFact: undefined }, dataStatus: 'curated' };
    }
    for (const c of p.conditions) {
      if (facts[c.fact] === undefined) return { status: 'need', reasons, nextQuestion: question(c.fact), amount: amountOf(p, facts), dataStatus: 'curated' };
      const ok = OPS[c.op](facts[c.fact], c.value); reasons.push({ ok, text: c.label });
      if (!ok) return { status: 'unlikely', reasons, amount: { basis: 'none', note: 'ตามข้อมูลที่ให้มา ไม่น่าจะมีสิทธิ์' }, dataStatus: 'curated' };
    }
    // haveIf: money the person may already receive. Not new money: shown as "check the amount", never counted.
    if (p.haveIf) {
      const h = p.haveIf;
      if (facts[h.fact] === undefined) return { status: 'need', reasons, nextQuestion: question(h.fact), amount: amountOf(p, facts), dataStatus: 'curated' };
      if (facts[h.fact] === h.value) {
        const a = amountOf(p, facts);
        return { status: 'check', alreadyReceiving: true, reasons: [...reasons, { ok: true, text: h.label }, { ok: null, text: h.note }], amount: { ...a, note: h.note, needsFact: undefined }, dataStatus: 'curated' };
      }
    }
    (p.unknowns || []).forEach(t => reasons.push({ ok: null, text: t }));
    const amount = amountOf(p, facts);
    // curated = criteria and rates come from the public sources listed on the program; the user's answers are self-reported.
    return { status: p.resultIfMet || 'likely', reasons, amount, nextQuestion: amount.needsFact ? question(amount.needsFact) : undefined, dataStatus: 'curated' };
  }

  const item = (p, e) => ({ id: p.id, title: p.title, icon: p.icon, kind: p.kind, payer: p.payer, status: e.status, amount: strip(e.amount), reasons: e.reasons, nextQuestion: e.nextQuestion, rulesVersion: p.version, dataStatus: e.dataStatus, alreadyReceiving: e.alreadyReceiving || undefined });
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
      return { ...base, documents: p.docs.map((t, i) => ({ index: i, text: t, ready: docsReady.includes(i) })), channels: p.channels, contactGuide: p.contactGuide,
        after: p.after, ifNo: p.ifNo, letterTemplate: letter, claimable: !['unlikely', 'need'].includes(e.status), sources: p.sources || [], sourceNote: 'เกณฑ์ อัตรา เอกสาร และช่องทางรวบรวมจากแหล่งสาธารณะที่ระบุ ตรวจล่าสุด ' + p.version + ' ยังไม่ใช่การยืนยันสิทธิ์ ตรวจกับหน่วยงานก่อนยื่น แอปไม่รับประกันว่าจะได้เงิน' };
    },
    validateFacts(patch) {
      const errors = [], clean = {};
      for (const [k, v] of Object.entries(patch || {})) {
        const d = factDefs[k]; if (!d) { errors.push(k + ': ไม่รู้จัก'); continue; }
        if (v === null) { clean[k] = undefined; continue; }
        if (d.type === 'enum' && !d.options.includes(v)) errors.push(k + ': ต้องเป็นหนึ่งใน ' + d.options.join(', '));
        else if (d.type === 'bool' && typeof v !== 'boolean') errors.push(k + ': ต้องเป็น true/false');
        else if (d.type === 'number' && (!Number.isFinite(v) || v < d.min || v > d.max)) errors.push(k + ': ต้องเป็นตัวเลข ' + d.min + '-' + d.max);
        else if (d.type === 'text' && (typeof v !== 'string' || !/^[\p{Script=Thai}\s]{2,40}$/u.test(v.trim()))) errors.push(k + ': ระบุชื่อพื้นที่');
        else clean[k] = v;
      }
      return { errors, clean };
    },
    question,
    claimSteps(id) { const p = programs.find(x => x.id === id); return p ? ['เตรียมเอกสาร', p.channels[0].title, 'ติดตามผล', 'ได้รับเงิน (ผู้ใช้แจ้ง)'] : null; }
  };
}
module.exports = { createMoney };
