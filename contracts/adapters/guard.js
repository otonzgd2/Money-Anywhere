// Refusals and credential checks run before conversation routing and any model call.
const thaiDigits = text => String(text).replace(/[๐-๙]/g, digit => String(digit.charCodeAt(0) - 0x0E50));
const credentialName = /\b(?:otp|pin)\b|รหัสผ่าน|รหัส\s*(?:ยืนยัน|ใช้ครั้งเดียว)|เลขบัญชี/i;
const credentialValue = /\d{4,}|\b(?:otp|pin)\s*[:=]?\s*\d|(?:รหัสผ่าน|password)\s*(?:คือ|เป็น|[:=])\s*\S/i;
const safetyQuestion = /ปลอดภัย|ควรส่งไหม|ให้ส่ง.*ไหม|มิจฉาชีพ|หลอก|ควรทำอย่างไร/i;
function createGuard(policy) {
  const rules = policy.rules.map(r => ({ id: r.id, res: r.patterns.map(p => new RegExp(p, 'i')), reply: r.reply }));
  const NUM = /^\s*[\d,]+(\.\d+)?\s*(บาท|วัน|ปี|คน)?\s*(ค่ะ|ครับ|คะ)?\s*$/;
  const SKIP = new RegExp(policy.skipPattern || '^(ข้าม|ไม่แน่ใจ|ไม่รู้|ไม่ทราบ)');
  const CONFUSED = new RegExp(policy.confusedPattern || 'ไม่เข้าใจ|งง|หมายความว่า|หมายถึง|แปลว่า|คืออะไร|ถามอะไร|อธิบาย|ยกตัวอย่าง');
  const ZERO = /^(ไม่มี|ไม่ค้าง|ไม่เคย|ศูนย์|0)/;
  return {
    version: policy.version,
    mask(text) {
      return String(text || '')
        .replace(/((?:otp|pin|รหัส\s*(?:ยืนยัน|ใช้ครั้งเดียว))\s*(?:คือ|เป็น|[:=])?\s*)([\d๐-๙]+(?:[ -]+[\d๐-๙]+)*)/gi, '$1[ซ่อน]')
        .replace(/((?:รหัสผ่าน|password)\s*(?:(?:คือ|เป็น|[:=])\s*)?)(\S+)/gi, '$1[ซ่อน]')
        .replace(/((?:เลข)?(?:บัญชี|บัตร)\s*(?:เลขที่|คือ|เป็น|[:=])?\s*)([\d๐-๙](?:[\d๐-๙\s-]*[\d๐-๙])?)/gi, (all, prefix, value) => value.replace(/[^\d๐-๙]/g, '').length >= 4 ? prefix + '[ซ่อน]' : all)
        .replace(/(?<![\d๐-๙])(?:[\d๐-๙][ -]?){12}[\d๐-๙](?![\d๐-๙])/g, '[ซ่อน]');
    },
    check(text, expect) {
      const t = thaiDigits(text || '').trim();
      if (credentialName.test(t) && safetyQuestion.test(t) && !credentialValue.test(t)
        && !/\d(?:[-\s]?\d){3,}/.test(t)
        && !rules.find(r => r.id === 'injection').res.some(re => re.test(t))) {
        return { kind: 'safe_advice', reply: 'อย่าส่ง OTP, PIN หรือรหัสผ่านให้นายจ้าง ตรวจชื่อบริษัทและช่องทางรับสมัครกับบริษัทโดยตรงค่ะ' };
      }
      for (const r of rules) if (r.res.some(re => re.test(t))) return { kind: r.id, reply: r.reply };
      if (credentialName.test(t)) return { kind: 'sensitive', reply: rules.find(r => r.id === 'sensitive').reply };
      if (expect && expect.options && expect.options.includes(t)) return { kind: 'answer' };
      // "I don't understand the question": explain it (help text + options) instead of refusing.
      if (expect && CONFUSED.test(t)) return { kind: 'explain' };
      // A number question answered with "none": that is 0, not an unclear message.
      if (expect && expect.type === 'number' && ZERO.test(t)) return { kind: 'answer', value: '0' };
      // "Not sure / skip" while a question is open: move on to the next question, ask this one later.
      if (expect && SKIP.test(t)) return { kind: 'skip' };
      if (expect && expect.type === 'number' && NUM.test(t)) return { kind: 'answer', value: t };
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
    redirect: policy.redirect,
    skipQuickReply: policy.skipQuickReply || 'ไม่แน่ใจ ข้ามข้อนี้',
    scope: policy.scope,
    offTopicReply: (policy.rules.find(r => r.id === 'off_topic') || {}).reply || 'เรื่องนี้ฉันช่วยไม่ได้ค่ะ'
  };
}

// Turn the chosen option (or typed number) into the fact value the money engine expects.
function toFact(expect, text) {
  const t = String(text || '').trim();
  if (expect.type === 'number') return +t.replace(/[^\d.]/g, '');
  if (expect.type === 'bool') return t === expect.options[0];
  return t;
}
module.exports = { createGuard, toFact, thaiDigits };
