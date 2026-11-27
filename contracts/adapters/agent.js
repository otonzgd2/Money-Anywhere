// AI assistant (agent) port. The agent only sees what tools return for this one user.
// Tool modes: read = run immediately; confirm = becomes a pending action the user must approve;
// memory = the agent may save a short note the user can see and delete. Anything else is refused.
// Money figures in replies must come from tool results; others are removed.
const { createResponsesClient } = require('./responses');

const MONEY_RE = /(฿\s?\d[\d,.]*|\d[\d,.]*\s?(บาท|baht|THB))/gi;

function guardMoney(reply, toolJson) {
  const known = new Set((toolJson.match(/\d+(\.\d+)?/g) || []));
  return String(reply || '').replace(MONEY_RE, m => (known.has(m.replace(/[^\d.]/g, '')) ? m : '(ดูยอดในแอป)'));
}

function guardReferences(reply, results) {
  const urlLike = /(?:https?:\/\/|www\.)[^\s<>()\]]+|(?:[\w-]+\.)+(?:com|net|org|go\.th|co\.th|io)(?:\/[^\s<>()\]]*)?/gi;
  const phoneLike = /(?<!\d)(?:\+66[\s-]?|0)\d(?:[\s-]?\d){7,8}(?!\d)|(?<=โทร(?:หา|ที่)?\s*|เบอร์(?:โทร)?\s*)\d{3,4}(?!\d)/gi;
  const references = pattern => new Set(results.flatMap(value => value.match(pattern) || []));
  const links = references(urlLike), phones = references(phoneLike);
  return reply.replace(urlLike, value => links.has(value) ? value : 'ดูช่องทางในแอป')
    .replace(phoneLike, value => phones.has(value) ? value : 'ดูเบอร์ติดต่อในแอป');
}

const PREF_RE = /(ไม่สะดวก[^.?!]*|ไม่อยาก[^.?!]*|ชอบ[^.?!]*|ไม่มีรถ[^.?!]*|ขาไม่ดี[^.?!]*|ทำได้แค่[^.?!]*|ว่างแค่[^.?!]*)/;
const CLAIM_PREFIX = 'ดูวิธีรับ ';
const moneyGuide = /^(เงินฉันอยู่ไหน|เอกสารที่ยังขาด|ไปรับเงินยังไง|ดูวิธีรับ .+)[?？]?$/;
const moneySummaryQuery = /^เงินฉันอยู่ไหน[?？]?$/;
const unpaidPlansQuery = /ติดตามแผน|(?:แผน|รายการ).{0,25}(?:ยังไม่(?:ได้รับ|ได้|รับ)เงิน|ค้างอยู่)|ยังไม่(?:ได้รับ|ได้|รับ)เงิน.{0,20}(?:แผน|รายการ)/;
const planStatusQuery = /ถึงไหน|สถานะ|ได้เงิน(?:แล้ว)?หรือยัง|ยังไม่(?:ได้รับ|ได้|รับ)เงิน|แผนเดิม|เปิดแผน|ลิงก์แผน|ลิงค์แผน/;
const moneyNames = {
  old_age: ['เบี้ยผู้สูงอายุ', 'เงินผู้สูงอายุ'],
  unemployment: ['เงินว่างงาน', 'เงินทดแทนว่างงาน'],
  child_support: ['เงินอุดหนุนเด็ก', 'เงินเลี้ยงดูเด็ก'],
  disability: ['เบี้ยคนพิการ', 'เงินคนพิการ'],
  tax_refund: ['คืนภาษี'],
  unpaid_wages: ['ค่าจ้างค้าง', 'เงินเดือนค้าง'],
};
const claimable = item => ['likely', 'verified', 'check'].includes(item.status);

function matchingMoneyPlans(plans, { text, reply = '', toolCalls = [], pending = [], savedMoneyIds = [] }) {
  const content = (text + '\n' + reply).replace(/\s+/g, '');
  const ids = new Set(savedMoneyIds);
  [...toolCalls, ...pending]
    .filter(call => ['get_money_route', 'create_task'].includes(call.tool))
    .forEach(call => ids.add(call.args?.moneyId));
  return plans.filter(plan => ids.has(plan.moneyId) || [plan.title.split(' (')[0], ...(moneyNames[plan.moneyId] || [])]
    .some(name => content.includes(name.replace(/\s+/g, ''))));
}

function planPaymentStatus(plan) {
  switch (plan.outcome?.result) {
    case 'received': return 'คุณแจ้งว่าได้รับเงินแล้ว';
    case 'not_received': return 'คุณแจ้งว่ายังไม่ได้รับเงิน';
    case 'rejected': return 'คุณแจ้งว่าผลไม่ผ่าน';
    case 'other': return 'คุณแจ้งผลอื่นไว้';
    default: return 'ยังไม่มีการแจ้งว่าได้รับเงิน';
  }
}

// "I want X baht a month": find the amount in the text (the first number of 100 or more).
const GOAL_RE = /(อยากได้|เป้า|ต้องการ|หาเงิน|ให้ได้|อยากมี).{0,25}\d|\d[\d,]*\s*(บาท)?\s*(ต่อเดือน|\/เดือน|ต่อเดือน)|เดือนละ\s*\d/;
function goalTarget(text) {
  if (!GOAL_RE.test(text)) return null;
  const n = (String(text).replace(/(\d),(\d)/g, '$1$2').match(/\d+/g) || []).map(Number).find(x => x >= 100);
  return n || null;
}
const fmt = n => Math.round(n).toLocaleString('en-US');
const range = r => r[0] === r[1] ? fmt(r[0]) : fmt(r[0]) + '-' + fmt(r[1]);
const SRC = { official: 'อัตราทางการ', listing: 'ตามประกาศ', estimate: 'ประมาณการ' };
// Plain-text plan from plan_income_goal output. Every number comes from the tool result.
function formatGoal(p) {
  const lines = ['เป้า ' + fmt(p.target) + ' บาท/เดือน วางแผนได้แบบนี้'];
  p.parts.forEach((x, i) => lines.push((i + 1) + '. ' + x.title + ' ประมาณ ' + range(x.net) + ' บาท/เดือน (' + (SRC[x.numberSource] || x.numberSource) + (x.dataStatus === 'mock' ? ', ตัวอย่าง DEMO' : '') + ')' + (x.matched && x.matched.length ? ' ตรงทักษะ: ' + x.matched.join(', ') : '')));
  if (!p.parts.length) lines.push('ยังไม่มีทางที่คิดเป็นตัวเลขได้');
  lines.push('รวมประมาณ ' + range(p.total) + ' บาท/เดือน' + (p.reach === 'likely' ? ' ถึงเป้าถ้าทำตามแผน' : p.reach === 'maybe' ? ' อาจถึงเป้าถ้าได้ช่วงบน' : ' ยังขาดอีกราว ' + fmt(p.gap) + ' บาท'));
  p.missing.forEach(m => lines.push('• ' + m.text));
  lines.push('ไม่ใช่รายได้ที่รับประกัน ดูแผนเต็มได้ที่ หน้าแรก > แผนรายได้');
  return lines.join('\n');
}

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
  const target = goalTarget(t);
  if (target && tools.plan_income_goal) {
    reply = formatGoal(await use('plan_income_goal', { target }));
    quick = ['ไปรับเงินยังไง', 'หางานใกล้บ้าน', 'เอกสารที่ยังขาด'];
  } else if (/เอกสาร/.test(t)) {
    const m = await use('get_money_overview');
    const items = m.items.filter(claimable);
    const lines = [];
    for (const it of items) {
      const r = await use('get_money_route', { moneyId: it.id });
      const miss = r.documents.filter(d => !d.ready).map(d => d.text);
      if (miss.length) lines.push(it.title + ': ' + miss.join(', '));
    }
    reply = lines.length ? 'เอกสารที่ยังขาด\n' + lines.join('\n') : items.length ? 'เอกสารพร้อมแล้วทุกรายการที่แสดง' : notYet(m);
    quick = items.map(it => CLAIM_PREFIX + it.title);
  } else if (t.startsWith(CLAIM_PREFIX) || /^ไปรับเงินยังไง[?？]?$/.test(t)) {
    const m = await use('get_money_overview');
    const items = m.items.filter(claimable);
    const title = t.startsWith(CLAIM_PREFIX) ? t.slice(CLAIM_PREFIX.length).replace(/[?？]$/, '') : null;
    const selected = title ? items.find(it => it.title === title) : items.length === 1 ? items[0] : null;
    if (!selected) {
      reply = items.length ? 'เลือกรายการเพื่อดูที่ยื่นและขั้นตอนหลังยื่น' : notYet(m);
      quick = items.map(it => CLAIM_PREFIX + it.title);
    } else {
      const route = await use('get_money_route', { moneyId: selected.id });
      const channel = route.channels[0];
      reply = selected.title + '\n' + [channel.title, channel.detail, channel.url, route.after].filter(Boolean).join('\n');
      pending.push({ tool: 'create_task', args: { moneyId: selected.id }, label: 'บันทึกแผน: ' + selected.title });
      quick = ['เอกสารที่ยังขาด', ...items.filter(it => it !== selected).map(it => CLAIM_PREFIX + it.title)];
    }
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
  } else if (/เงิน|ได้เท่าไหร่|รอรับ|สิทธิ์|ควรได้|ได้อะไร|จากรัฐ/.test(t)) {
    const m = await use('get_money_overview');
    const s = m.summary, top = m.items.filter(claimable);
    reply = (s.counted ? 'เงินที่คุณอาจได้ ' + (s.monthly ? s.monthly + ' บาท/เดือน' : '') + (s.once ? (s.monthly ? ' และ ' : '') + s.once + ' บาท ครั้งเดียว' : '') + (s.allVerified ? ' (ยืนยันจากหน่วยงาน)' : ' (ประมาณจากเกณฑ์ ยังไม่ยืนยัน)') : notYet(m))
      + (top.length ? '\n' + top.map(i => '• ' + i.title + ' — ' + (i.status === 'check' ? 'ยังต้องเช็กยอดจริง' : typeof i.amount.value === 'number' ? i.amount.value + ' ' + i.amount.unit : 'ยังไม่ทราบยอด') + (i.dataStatus === 'mock' ? ' (DEMO)' : '')).join('\n') : '');
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
  const responses = configured && (opts.apiStyle ?? process.env.AI_API_STYLE) === 'responses'
    ? createResponsesClient({ baseUrl, apiKey, model, fetchImpl, timeoutMs: opts.timeoutMs || 15000 })
    : null;

  async function llm(messages, toolSpecs, signal) {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(baseUrl.replace(/\/$/, '') + '/chat/completions', { method: 'POST', signal: signal ? AbortSignal.any([signal, ctl.signal]) : ctl.signal,
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + apiKey },
        body: JSON.stringify({ model, temperature: 0, messages, tools: toolSpecs }) });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return (await res.json()).choices[0].message;
    } finally { clearTimeout(t); }
  }

  return {
    provider: configured ? 'openai_compatible' : 'rules',
    async respond({ text, history = [], memory = [], profile = {}, tools, systemPrompt, signal, fallback }) {
      if (!configured) return fallback ? fallback() : rulesAgent({ text, tools });
      const calls = [], pending = [], mem = [], savedMoneyIds = [], results = []; let toolJson = '';
      const specs = Object.entries(tools).map(([name, t]) => ({ type: 'function', function: { name, description: t.description, parameters: t.parameters } }));
      const responseTools = responses && specs.map(({ type, function: spec }) => ({ type, ...spec, strict: false }));
      // systemPrompt comes from fixtures/assistant-policy.json (scope + checklist + current step).
      const messages = [
        { role: 'system', content: systemPrompt || 'คุณคือผู้ช่วยของแอป Money Anywhere ตอบภาษาไทยสั้นๆ ใช้เฉพาะข้อมูลจากเครื่องมือ ห้ามแต่งตัวเลขเงิน สิทธิ์ หรือหน่วยงาน ห้ามรับประกันว่าจะได้เงินหรือได้งาน แอปไม่ยื่นแทนผู้ใช้ งานที่เปลี่ยนข้อมูลต้องรอผู้ใช้ยืนยัน' },
        { role: 'system', content: 'สิ่งที่ผู้ใช้เคยบอก: ' + (memory.join(' · ') || 'ไม่มี') + ' · โปรไฟล์: ' + JSON.stringify({ skills: profile.skills, hoursPerWeek: profile.hoursPerWeek, constraints: profile.constraints }) },
        ...history.slice(-8), { role: 'user', content: String(text) }];
      try {
        for (let step = 0; step < maxSteps; step++) {
          signal?.throwIfAborted();
          const response = responses && await responses(messages, { tools: responseTools }, signal);
          const msg = response ? {
            content: response.text,
            tool_calls: response.output
              .filter(item => item.type === 'function_call')
              .map(item => ({ id: item.call_id, function: { name: item.name, arguments: item.arguments } }))
          } : await llm(messages, specs, signal);
          signal?.throwIfAborted();
          if (!msg.tool_calls || !msg.tool_calls.length) {
            if (typeof msg.content !== 'string' || !msg.content.trim()) throw new Error('Empty model reply');
            const reply = guardReferences(guardMoney(msg.content, toolJson), results);
            return { aiStatus: 'ok', reply, toolCalls: calls, pending, memory: mem, quickReplies: [], savedMoneyIds };
          }
          if (response) {
            // Replay reasoning items alongside function calls in stateless requests.
            messages.push(...response.output);
          } else {
            messages.push({ role: 'assistant', content: msg.content || '', tool_calls: msg.tool_calls });
          }
          for (const tc of msg.tool_calls) {
            const name = tc.function.name, tool = tools[name]; let args = {};
            try { args = JSON.parse(tc.function.arguments || '{}'); } catch { args = {}; }
            let out;
            if (!tool) out = { error: 'tool not allowed' };
            else if (tool.mode === 'read') {
              out = await tool.run(args);
              calls.push({ tool: name, args });
              results.push(JSON.stringify(out));
            }
            else if (tool.mode === 'memory') { const note = String(args.text || '').slice(0, 200); if (note) mem.push(note); out = { saved: !!note }; calls.push({ tool: name, args }); }
            else {
              const task = tool.findSaved?.(args);
              if (task) { savedMoneyIds.push(task.moneyId); out = { status: 'already_saved', task }; }
              else { pending.push({ tool: name, args, label: tool.label(args) }); out = { status: 'waiting_for_user_confirmation' }; }
            }
            const s = JSON.stringify(out); toolJson += s;
            messages.push(response
              ? { type: 'function_call_output', call_id: tc.id, output: s }
              : { role: 'tool', tool_call_id: tc.id, content: s });
          }
        }
        throw new Error('too many steps');
      } catch (e) {
        signal?.throwIfAborted();
        const r = fallback ? await fallback() : await rulesAgent({ text, tools });
        return { ...r, error: e.message };
      }
    }
  };
}
module.exports = { createAgent, guardMoney, rulesAgent, goalTarget, formatGoal, moneyGuide,
  moneySummaryQuery, unpaidPlansQuery, planStatusQuery, matchingMoneyPlans, planPaymentStatus };
