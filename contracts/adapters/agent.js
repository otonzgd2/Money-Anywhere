// AI assistant (agent) port. The agent only sees what tools return for this one user.
// Tool modes: read = run immediately; confirm = becomes a pending action the user must approve;
// memory = the agent may save a short note the user can see and delete. Anything else is refused.
// Money figures in replies must come from tool results; others are removed.
const MONEY_RE = /(฿\s?\d[\d,]*|\d[\d,]*\s?(บาท|baht|THB))/gi;

function guardMoney(reply, toolJson) {
  const known = new Set((toolJson.match(/\d+(\.\d+)?/g) || []));
  return String(reply || '').replace(MONEY_RE, m => (known.has(m.replace(/[^\d.]/g, '')) ? m : '(ดูยอดในแอป)'));
}

const PREF_RE = /(ไม่สะดวก[^.?!]*|ไม่อยาก[^.?!]*|ชอบ[^.?!]*|ไม่มีรถ[^.?!]*|ขาไม่ดี[^.?!]*|ทำได้แค่[^.?!]*|ว่างแค่[^.?!]*)/;

// Nothing to claim yet: say how far the person is, without naming programs they have not qualified for.
function notYet(m) {
  const open = m.items.filter(i => i.status === 'need').length;
  return open ? 'ตอนนี้ยังบอกไม่ได้ว่าควรได้เงินอะไร ต้องตอบคำถามอีกประมาณ ' + open + ' เรื่องก่อน' : 'จากคำตอบตอนนี้ ยังไม่พบเงินที่น่าจะมีสิทธิ์';
}

async function rulesAgent({ text, tools }) {
  const calls = [], pending = [], memory = [];
  const use = async (name, args = {}) => { const r = await tools[name].run(args); calls.push({ tool: name, args }); return r; };
  const t = String(text || '');
  const pref = t.match(PREF_RE);
  if (pref) memory.push(pref[1].trim());
  let reply, quick = ['เงินฉันอยู่ไหน', 'เอกสารที่ยังขาด', 'หางานใกล้บ้าน', 'เตือนฉันพรุ่งนี้'];
  if (/เอกสาร/.test(t)) {
    const m = await use('get_money_overview');
    const lines = [];
    for (const it of m.items.filter(i => ['likely', 'verified', 'check'].includes(i.status))) {
      const r = await use('get_money_route', { moneyId: it.id });
      const miss = r.documents.filter(d => !d.ready).map(d => d.text);
      if (miss.length) lines.push(it.title + ': ' + miss.join(', '));
    }
    reply = lines.length ? 'เอกสารที่ยังขาด\n' + lines.join('\n') : 'เอกสารครบทุกรายการที่น่าจะมีสิทธิ์แล้ว';
  } else if (/งาน/.test(t)) {
    const r = await use('search_opportunities', { group: 'job', limit: 3 });
    if (!r.items.length) reply = 'ยังไม่พบงานใกล้คุณ ลองขยายระยะในหน้าโอกาส';
    else {
      reply = 'งานใกล้คุณ:\n' + r.items.map((o, i) => (i + 1) + '. ' + o.title + (o.money.basis !== 'none' ? ' (' + o.money.min + '-' + o.money.max + ' ' + o.money.unit + ' ตามประกาศ)' : '')).join('\n');
      pending.push({ tool: 'create_task', args: { opportunityId: r.items[0].id }, label: 'บันทึก "' + r.items[0].title + '" ไว้ในแผนของฉัน' });
    }
  } else if (/เตือน|เลื่อน|พรุ่งนี้/.test(t)) {
    const r = await use('list_tasks');
    const a = r.items.find(x => x.status === 'active');
    if (a) { reply = 'จะตั้งเตือนเรื่อง "' + a.title + '" พรุ่งนี้'; pending.push({ tool: 'snooze_task', args: { taskId: a.id, until: 'tomorrow' }, label: 'เตือน "' + a.title + '" พรุ่งนี้' }); }
    else reply = 'ยังไม่มีงานที่กำลังทำอยู่';
  } else if (/เงิน|ได้เท่าไหร่|รอรับ|สิทธิ์/.test(t)) {
    const m = await use('get_money_overview');
    const s = m.summary, top = m.items.filter(i => ['likely', 'verified'].includes(i.status));
    const need = m.items.find(i => i.status === 'need');
    reply = (s.counted ? 'เงินที่คุณอาจได้ ' + (s.monthly ? s.monthly + ' บาท/เดือน' : '') + (s.once ? ' และ ' + s.once + ' บาท ครั้งเดียว' : '') + (s.allVerified ? ' (ยืนยันจากหน่วยงาน)' : ' (ประมาณจากเกณฑ์ ยังไม่ยืนยัน)') : 'ยังไม่พบเงินที่น่าจะมีสิทธิ์')
      + (top.length ? '\nเริ่มที่: ' + top.map(i => i.title).join(', ') : '')
      + (need ? '\nตอบอีกข้อเพื่อเช็ค ' + need.title + ': ' + need.nextQuestion.question : '');
    quick = ['เอกสารที่ยังขาด', 'ไปรับเงินยังไง', 'หางานใกล้บ้าน'];
  } else if (/ลิงก์|ลิงค์|link|เว็บ|ติดต่อ|เบอร์|โทร|ช่องทาง/i.test(t)) {
    // Contacts and links come only from the program's published channels, never from the model.
    const m = await use('get_money_overview');
    const list = m.items.filter(i => ['likely', 'verified', 'check'].includes(i.status));
    const lines = [];
    for (const it of list.slice(0, 2)) {
      const r = await use('get_money_route', { moneyId: it.id });
      lines.push(it.title + ':\n' + r.channels.map(c => '• ' + c.title + (c.detail ? ' ' + c.detail : '') + (c.url ? ' ' + c.url : '')).join('\n'));
    }
    reply = lines.length ? 'ช่องทางติดต่อ (จากประกาศของหน่วยงาน)\n' + lines.join('\n') : notYet(m) + ' แล้วจะบอกช่องทางติดต่อของหน่วยงานที่ต้องไปยื่นให้';
  } else if (/ยังไง|อย่างไร|ไปรับ|ทำไง|ต้องทำ|ทำอะไร|ขั้นตอน/.test(t)) {
    const m = await use('get_money_overview');
    const first = m.items.find(i => ['likely', 'verified', 'check'].includes(i.status));
    if (!first) reply = notYet(m) + ' แล้วจะบอกว่าได้เงินอะไร เท่าไหร่ เอาเอกสารอะไรไปยื่นที่ไหน';
    else { const r = await use('get_money_route', { moneyId: first.id }); reply = first.title + ': ยื่นที่ ' + r.channels[0].title + ' · ' + r.after; pending.push({ tool: 'create_task', args: { moneyId: first.id }, label: 'สร้างแผนรับ "' + first.title + '" ทีละขั้น' }); }
  } else if (pref) {
    reply = 'จำไว้แล้ว จะใช้ประกอบการแนะนำครั้งต่อไป ลบได้ที่แท็บ ฉัน';
  } else {
    reply = 'ถามได้เลย เช่น เงินฉันอยู่ไหน เอกสารที่ยังขาด หรือหางานใกล้บ้าน';
  }
  return { aiStatus: 'fallback_rules', reply, toolCalls: calls, pending, memory, quickReplies: quick };
}

function createAgent(opts = {}) {
  const baseUrl = opts.baseUrl !== undefined ? opts.baseUrl : process.env.AI_BASE_URL;
  const apiKey = opts.apiKey !== undefined ? opts.apiKey : process.env.AI_API_KEY;
  const model = opts.model || process.env.AI_MODEL || 'default';
  const fetchImpl = opts.fetch || fetch, timeoutMs = opts.timeoutMs || 10000, maxSteps = 4;
  const configured = !!(baseUrl && apiKey);

  async function llm(messages, toolSpecs) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(baseUrl.replace(/\/$/, '') + '/chat/completions', { method: 'POST', signal: ctl.signal,
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + apiKey },
        body: JSON.stringify({ model, temperature: 0, messages, tools: toolSpecs }) });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return (await res.json()).choices[0].message;
    } finally { clearTimeout(t); }
  }

  return {
    provider: configured ? 'openai_compatible' : 'rules',
    async respond({ text, history = [], memory = [], profile = {}, tools, systemPrompt }) {
      if (!configured) return rulesAgent({ text, tools });
      const calls = [], pending = [], mem = []; let toolJson = '';
      const specs = Object.entries(tools).map(([name, t]) => ({ type: 'function', function: { name, description: t.description, parameters: t.parameters } }));
      // systemPrompt comes from fixtures/assistant-policy.json (scope + checklist + current step).
      const messages = [
        { role: 'system', content: systemPrompt || 'คุณคือผู้ช่วยของแอป Money Anywhere ตอบภาษาไทยสั้นๆ ใช้เฉพาะข้อมูลจากเครื่องมือ ห้ามแต่งตัวเลขเงิน สิทธิ์ หรือหน่วยงาน ห้ามรับประกันว่าจะได้เงินหรือได้งาน แอปไม่ยื่นแทนผู้ใช้ งานที่เปลี่ยนข้อมูลต้องรอผู้ใช้ยืนยัน' },
        { role: 'system', content: 'สิ่งที่ผู้ใช้เคยบอก: ' + (memory.join(' · ') || 'ไม่มี') + ' · โปรไฟล์: ' + JSON.stringify({ district: profile.district, skills: profile.skills, goals: profile.goals, hoursPerWeek: profile.hoursPerWeek }) },
        ...history.slice(-8), { role: 'user', content: String(text) }];
      try {
        for (let step = 0; step < maxSteps; step++) {
          const msg = await llm(messages, specs);
          if (!msg.tool_calls || !msg.tool_calls.length) {
            return { aiStatus: 'ok', reply: guardMoney(msg.content, toolJson), toolCalls: calls, pending, memory: mem, quickReplies: [] };
          }
          messages.push({ role: 'assistant', content: msg.content || '', tool_calls: msg.tool_calls });
          for (const tc of msg.tool_calls) {
            const name = tc.function.name, tool = tools[name]; let args = {};
            try { args = JSON.parse(tc.function.arguments || '{}'); } catch { args = {}; }
            let out;
            if (!tool) out = { error: 'tool not allowed' };
            else if (tool.mode === 'read') { out = await tool.run(args); calls.push({ tool: name, args }); }
            else if (tool.mode === 'memory') { const note = String(args.text || '').slice(0, 200); if (note) mem.push(note); out = { saved: !!note }; calls.push({ tool: name, args }); }
            else { pending.push({ tool: name, args, label: tool.label(args) }); out = { status: 'waiting_for_user_confirmation' }; }
            const s = JSON.stringify(out); toolJson += s;
            messages.push({ role: 'tool', tool_call_id: tc.id, content: s });
          }
        }
        throw new Error('too many steps');
      } catch (e) { const r = await rulesAgent({ text, tools }); return { ...r, error: e.message }; }
    }
  };
}
module.exports = { createAgent, guardMoney, rulesAgent };
