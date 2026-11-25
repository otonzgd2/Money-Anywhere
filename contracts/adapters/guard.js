// Assistant guard. Runs on every chat message BEFORE the LLM, using fixtures/assistant-policy.json.
// Order: refusals (injection, sensitive data, guarantees, scams/loans, off-topic) win over everything,
// then an answer to the question the assistant just asked, then in-scope topics. Anything else is
// redirected back to the current checklist step. Refused text never reaches the model or the chat history.
function createGuard(policy) {
  const rules = policy.rules.map(r => ({ id: r.id, res: r.patterns.map(p => new RegExp(p, 'i')), reply: r.reply }));
  const NUM = /^\s*[\d,]+(\.\d+)?\s*(บาท)?\s*$/;
  return {
    version: policy.version,
    check(text, expect) {
      const t = String(text || '').trim();
      for (const r of rules) if (r.res.some(re => re.test(t))) return { kind: r.id, reply: r.reply };
      if (expect && expect.options && expect.options.includes(t)) return { kind: 'answer' };
      if (expect && expect.type === 'number' && NUM.test(t)) return { kind: 'answer' };
      if (policy.inScope.some(w => t.includes(w))) return { kind: 'in_scope' };
      return { kind: 'unclear', reply: 'ฉันช่วยได้เฉพาะเรื่องเงินที่ควรได้ งาน และรายได้จากทักษะ' };
    },
    // System prompt for the LLM with the checklist and the current step filled in.
    systemPrompt(step) {
      return policy.systemPrompt
        .replace('{checklist}', policy.checklist.map((c, i) => (i + 1) + ') ' + c.title).join(' '))
        .replace('{step}', step || 'ตอบคำถามของผู้ใช้ตามขอบเขต')
        .replace('{scope}', policy.scope);
    },
    redirect: policy.redirect
  };
}

// Turn the chosen option (or typed number) into the fact value the money engine expects.
function toFact(expect, text) {
  const t = String(text || '').trim();
  if (expect.type === 'number') return +t.replace(/[^\d.]/g, '');
  if (expect.type === 'bool') return t === expect.options[0];
  return t;
}
module.exports = { createGuard, toFact };
