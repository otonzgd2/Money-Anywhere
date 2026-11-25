// Generates docs/backend/index.html from the contracts. Edit the contracts, then run: npm run docs
// Sources: openapi.yaml, app-config.sample.json, app-config.schema.json, fixtures/reference.json
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const D = __dirname;
const api = yaml.load(fs.readFileSync(path.join(D, 'openapi.yaml'), 'utf8'));
const cfg = JSON.parse(fs.readFileSync(path.join(D, 'app-config.sample.json'), 'utf8'));
const schema = JSON.parse(fs.readFileSync(path.join(D, 'app-config.schema.json'), 'utf8'));
const ref = JSON.parse(fs.readFileSync(path.join(D, 'fixtures', 'reference.json'), 'utf8'));
const OUT = path.join(D, '..', 'docs', 'backend', 'index.html');

const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const slug = s => String(s).replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').toLowerCase();
const METHODS = ['get', 'post', 'put', 'patch', 'delete'];

// ---- index operations ----
const ops = [];
for (const [p, item] of Object.entries(api.paths)) for (const m of METHODS) if (item[m]) ops.push({ path: p, method: m.toUpperCase(), ...item[m] });
const opByMP = Object.fromEntries(ops.map(o => [o.method + ' ' + o.path, o]));
const actionOf = {}; // "METHOD path" -> [action ids]
for (const [id, a] of Object.entries(cfg.actions)) (actionOf[a.method + ' ' + a.path] = actionOf[a.method + ' ' + a.path] || []).push(id);

// ---- where each action / route is used ----
const usedAt = {}; // action id -> Set(route ids)
const linksFrom = {}; // route id -> Set(target route ids)
const widgetsOf = {}; // route id -> [{type,label,bindings:[{kind,id,label}]}]
const add = (m, k, v) => (m[k] = m[k] || new Set()).add(v);
function collect(rid, w, out) {
  const b = [];
  if (w.data) { b.push({ kind: 'data', id: w.data }); add(usedAt, w.data, rid); }
  const bind = (x, label) => {
    if (!x) return;
    if (x.action) { b.push({ kind: 'action', id: x.action, label }); add(usedAt, x.action, rid); }
    if (x.route) { b.push({ kind: 'route', id: x.route, label }); add(linksFrom, rid, x.route); }
    if (x.then && x.then.route) { b.push({ kind: 'then', id: x.then.route, label }); add(linksFrom, rid, x.then.route); }
  };
  bind(w.onTap, w.label);
  (w.actions || []).forEach(a => bind(a, a.label));
  out.push({ type: w.type, label: w.label, flag: w.flag, when: w.when, bindings: b });
  (w.items || []).forEach(c => collect(rid, c, out));
}
for (const [rid, r] of Object.entries(cfg.routes)) { widgetsOf[rid] = []; r.sections.forEach(w => collect(rid, w, widgetsOf[rid])); }
// Actions used outside screens: app start, and undo of another action.
const BOOT = { 'config.get': 'เปิดแอป' };
Object.entries(BOOT).forEach(([a, l]) => add(usedAt, a, '@' + l));
for (const [id, a] of Object.entries(cfg.actions)) if (a.undoAction) (usedAt[id] || []).forEach(r => add(usedAt, a.undoAction, r));

// ---- route -> tab ----
const tabOf = {};
cfg.tabs.forEach(t => { tabOf[t.route] = t.id; (t.activeFor || []).forEach(r => { tabOf[r] = tabOf[r] || t.id; }); });
const groups = cfg.tabs.map(t => ({ id: t.id, label: t.label, icon: t.icon, routes: Object.keys(cfg.routes).filter(r => tabOf[r] === t.id) }));
groups.push({ id: 'outside', label: 'นอกแท็บ (เริ่มต้น, เต็มจอ)', icon: '', routes: Object.keys(cfg.routes).filter(r => !tabOf[r]) });
const ICON = { home: '🏠', sparkle: '✨', list: '📋', person: '👤', '': '🚪' };

// ---- rendering helpers ----
const mbadge = m => '<span class="m m-' + m.toLowerCase() + '">' + m + '</span>';
const refName = r => r.split('/').pop();
function typeOf(s) {
  if (!s) return '';
  if (s.$ref) return '<a href="#schema-' + slug(refName(s.$ref)) + '">' + esc(refName(s.$ref)) + '</a>';
  if (s.type === 'array') return typeOf(s.items) + '[]';
  if (s.enum) return '<code>' + s.enum.map(esc).join(' | ') + '</code>';
  if (s.type === 'object' && s.properties) return 'object';
  return esc(s.type || 'any') + (s.format ? ' <span class="mut">(' + esc(s.format) + ')</span>' : '');
}
function propsTable(s) {
  if (!s) return '';
  if (s.$ref) return '<p>รูปแบบ: ' + typeOf(s) + '</p>';
  if (s.type === 'array') return '<p>รายการของ ' + typeOf(s.items) + '</p>';
  const req = new Set(s.required || []);
  const rows = Object.entries(s.properties || {}).map(([k, v]) => '<tr><td><code>' + esc(k) + '</code>' + (req.has(k) ? ' <span class="req">จำเป็น</span>' : '') + '</td><td>' + typeOf(v) + '</td><td>' + esc(v.description || '') + '</td></tr>');
  return rows.length ? '<table><tr><th>ฟิลด์</th><th>ชนิด</th><th>คำอธิบาย</th></tr>' + rows.join('') + '</table>' : '<p class="mut">' + esc(s.description || 'ไม่มีฟิลด์') + '</p>';
}
const routeLink = r => r[0] === '@' ? '<span class="pill">' + esc(r.slice(1)) + '</span>' : '<a class="rt" href="#route-' + slug(r) + '">' + esc(r) + '</a>';
const actionLink = a => '<a class="ac" href="#action-' + slug(a) + '">' + esc(a) + '</a>';
function opOfAction(a) { const x = cfg.actions[a]; return x && opByMP[x.method + ' ' + x.path]; }
const opAnchor = o => 'op-' + slug(o.operationId);

// ---- sections ----
const T = [];
T.push(`<section id="overview"><h2>ภาพรวม</h2>
<p>หลังบ้านแยก 3 ชั้น ปุ่มบนหน้าจออ้างแค่ <b>action id</b> ส่วน action id รู้ว่าเรียก API ไหน การย้ายเมนูหรือปุ่มจึงแก้แค่ไฟล์ config ไม่กระทบ API</p>
<div class="flow">
  <div class="box b1"><b>แอป Flutter</b><span>widget ${schema.$defs.widget.properties.type.enum.length} แบบ วาดตาม config</span></div><div class="arr">→</div>
  <div class="box b2"><b>Layout config</b><span>${cfg.tabs.length} แท็บ · ${Object.keys(cfg.routes).length} หน้า · ${cfg.filters.length} ตัวกรอง</span><small>แก้บ่อย</small></div><div class="arr">→</div>
  <div class="box b3"><b>Action catalog</b><span>${Object.keys(cfg.actions).length} action id → endpoint</span><small>แก้น้อย</small></div><div class="arr">→</div>
  <div class="box b4"><b>Resource API</b><span>${ops.length} operations · ${api.tags.length} บริการ</span><small>แก้น้อยที่สุด</small></div><div class="arr">→</div>
  <div class="box b5"><b>แหล่งข้อมูล / AI / DB</b><span>${ref.sources.length} แหล่ง · AI มี fallback</span></div>
</div>
<table><tr><th>อยากทำ</th><th>แก้ไฟล์</th><th>ส่วน</th></tr>
<tr><td>ย้ายปุ่ม ย้ายเมนู เพิ่มหน้า เปลี่ยนแท็บ</td><td><code>contracts/app-config.sample.json</code></td><td><code>tabs</code>, <code>routes</code></td></tr>
<tr><td>เพิ่มหรือย้ายตัวกรอง</td><td><code>contracts/app-config.sample.json</code></td><td><code>filters</code> (bar = บนจอ, sheet = ในแผ่นตัวกรอง)</td></tr>
<tr><td>เปลี่ยน endpoint ของ action</td><td><code>contracts/app-config.sample.json</code></td><td><code>actions</code></td></tr>
<tr><td>เพิ่ม API หรือฟิลด์ข้อมูล</td><td><code>contracts/openapi.yaml</code></td><td><code>paths</code>, <code>components.schemas</code></td></tr>
<tr><td>เพิ่มหมวด ทักษะ ขั้นตอน กฎหลอกลวง</td><td><code>contracts/fixtures/reference.json</code></td><td>taxonomies, checklists, scamRules</td></tr>
<tr><td>เพิ่มชนิด widget ใหม่</td><td><code>contracts/app-config.schema.json</code> + โค้ดแอป</td><td><code>$defs.widget.type</code></td></tr></table>
<div class="cmd"><b>หลังแก้ทุกครั้ง</b> (ในโฟลเดอร์ <code>contracts/</code>):<pre>npm run check     # ตรวจ config, OpenAPI, schema, ทดสอบทุก API แล้วสร้างหน้านี้ใหม่
npm run mock      # เปิด mock API ที่ http://localhost:8080 (เอกสารที่ /docs)</pre></div>
</section>`);

// Front: by tab
let F = '<section id="front"><h2>แยกตามหน้า (ฟร้อน)</h2><p class="mut">แต่ละแท็บมีหน้าอะไร แต่ละหน้ามี widget อะไร ใช้ API ไหน กดชื่อ action หรือ API เพื่อดูรายละเอียด</p><div class="tabsum">'
  + groups.map(g => '<a href="#tab-' + g.id + '" class="tabchip">' + (ICON[g.icon] || '🚪') + ' ' + esc(g.label) + ' <span>' + g.routes.length + ' หน้า</span></a>').join('') + '</div>';
for (const g of groups) {
  F += '<div class="tabgrp" id="tab-' + g.id + '"><h3>' + (ICON[g.icon] || '🚪') + ' ' + esc(g.label) + '</h3>';
  for (const rid of g.routes) {
    const r = cfg.routes[rid];
    const apis = new Map();
    widgetsOf[rid].forEach(w => w.bindings.filter(b => b.kind === 'data' || b.kind === 'action').forEach(b => { const o = opOfAction(b.id); if (o) apis.set(o.operationId, { o, a: b.id, kind: b.kind }); }));
    F += '<div class="card" id="route-' + slug(rid) + '"><div class="ch"><b>' + esc(r.title) + '</b> <code>' + esc(rid) + '</code>' + (r.params ? ' <span class="mut">ต้องมี: ' + r.params.map(esc).join(', ') + '</span>' : '') + (r.showTabs === false ? ' <span class="pill">เต็มจอ</span>' : '') + '</div>';
    F += '<div class="cols"><div><div class="lab">Widget บนหน้านี้</div><ul class="wl">' + (widgetsOf[rid].length ? widgetsOf[rid].map(w => '<li><code>' + esc(w.type) + '</code>' + (w.label ? ' ' + esc(w.label) : '') + (w.flag ? ' <span class="pill">flag: ' + esc(w.flag) + '</span>' : '') + (w.when ? ' <span class="pill">เมื่อ ' + esc(w.when) + '</span>' : '')
      + (w.bindings.length ? '<div class="bd">' + w.bindings.map(b => b.kind === 'data' ? '📥 อ่าน ' + actionLink(b.id) : b.kind === 'action' ? '⚡ ' + (b.label ? esc(b.label) + ' → ' : '') + actionLink(b.id) : '➡️ ' + (b.label && b.kind === 'route' ? esc(b.label) + ' → ' : b.kind === 'then' ? 'แล้วไป ' : '') + routeLink(b.id)).join('<br>') + '</div>' : '') + '</li>').join('') : '<li class="mut">ไม่มี</li>') + '</ul></div>';
    F += '<div><div class="lab">API ที่หน้านี้ใช้</div>' + (apis.size ? [...apis.values()].map(({ o, a }) => '<div class="apirow">' + mbadge(o.method) + ' <a href="#' + opAnchor(o) + '"><code>' + esc(o.path) + '</code></a><div class="mut">' + esc(o.summary) + ' · ' + esc((o.tags || [])[0]) + '</div></div>').join('') : '<p class="mut">ไม่เรียก API</p>') + '</div></div></div>';
  }
  F += '</div>';
}
F += '</section>';
T.push(F);

// API by service
let A = '<section id="api"><h2>API ตามบริการ</h2><p class="mut">ทั้งหมด ' + ops.length + ' operations จัดตาม resource ไม่ใช่ตามหน้าจอ ข้อผิดพลาดใช้รูปแบบ <a href="#schema-error">Error</a> เดียวกันทุกที่</p>';
for (const tg of api.tags) {
  const list = ops.filter(o => (o.tags || [])[0] === tg.name);
  A += '<div class="svc" id="svc-' + slug(tg.name) + '"><h3>' + esc(tg.name) + ' <span class="mut">' + esc(tg.description) + ' · ' + list.length + '</span></h3>';
  for (const o of list) {
    const acts = actionOf[o.method + ' ' + o.path] || [];
    const pages = new Set(); acts.forEach(a => (usedAt[a] || []).forEach(r => pages.add(r)));
    const params = (o.parameters || []).map(p => '<tr><td><code>' + esc(p.name) + '</code>' + (p.required ? ' <span class="req">จำเป็น</span>' : '') + '</td><td>' + esc(p.in) + '</td><td>' + typeOf(p.schema) + (p.schema && p.schema.default !== undefined ? ' <span class="mut">ค่าเริ่มต้น ' + esc(JSON.stringify(p.schema.default)) + '</span>' : '') + '</td></tr>').join('');
    const reqSchema = o.requestBody && o.requestBody.content['application/json'].schema;
    const resps = Object.entries(o.responses).map(([code, r]) => { const s = r.content && r.content['application/json'] && r.content['application/json'].schema; const isErr = r.$ref; return '<span class="code c' + code[0] + '">' + code + '</span> ' + (isErr ? '<a href="#schema-error">Error</a>' : s ? typeOf(s.type === 'object' && s.properties ? { type: 'object' } : s) : '<span class="mut">' + esc(r.description || 'ไม่มี body') + '</span>'); }).join(' &nbsp; ');
    A += '<details class="op" id="' + opAnchor(o) + '"><summary>' + mbadge(o.method) + ' <code>' + esc(o.path) + '</code> <span class="sum">' + esc(o.summary) + '</span></summary><div class="opb">'
      + '<div class="kv"><span>operationId</span><code>' + esc(o.operationId) + '</code></div>'
      + '<div class="kv"><span>action id</span>' + (acts.length ? acts.map(actionLink).join(', ') : '<span class="mut">ไม่มี (ใช้ภายใน)</span>') + '</div>'
      + '<div class="kv"><span>ใช้ที่หน้า</span>' + (pages.size ? [...pages].map(routeLink).join(', ') : '<span class="mut">ยังไม่ได้วางบนหน้าใด</span>') + '</div>'
      + (o.description ? '<p>' + esc(o.description) + '</p>' : '')
      + (params ? '<div class="lab">Parameters</div><table><tr><th>ชื่อ</th><th>อยู่ที่</th><th>ชนิด</th></tr>' + params + '</table>' : '')
      + (reqSchema ? '<div class="lab">Request body</div>' + propsTable(reqSchema) : '')
      + '<div class="lab">Responses</div><p>' + resps + '</p></div></details>';
  }
  A += '</div>';
}
A += '</section>';
T.push(A);

// Action catalog
T.push('<section id="actions"><h2>Action catalog</h2><p class="mut">ชั้นกลางระหว่างหน้าจอกับ API แก้ endpoint ที่นี่ หน้าจอไม่ต้องรู้</p><table><tr><th>action id</th><th>เรียก</th><th>อ่าน tag</th><th>ล้าง tag (หน้าอื่นจะโหลดใหม่)</th><th>ใช้ที่หน้า</th></tr>'
  + Object.entries(cfg.actions).map(([id, a]) => { const o = opByMP[a.method + ' ' + a.path]; return '<tr id="action-' + slug(id) + '"><td><code>' + esc(id) + '</code>' + (a.confirm ? '<div class="mut">ถามก่อน: ' + esc(a.confirm) + '</div>' : '') + (a.undoAction ? '<div class="mut">เลิกทำด้วย ' + actionLink(a.undoAction) + '</div>' : '') + '</td><td>' + mbadge(a.method) + ' ' + (o ? '<a href="#' + opAnchor(o) + '"><code>' + esc(a.path) + '</code></a>' : '<code>' + esc(a.path) + '</code> <span class="req">ไม่พบใน API</span>') + '</td><td>' + esc(a.provides || '') + '</td><td>' + esc((a.invalidates || []).join(', ')) + '</td><td>' + [...(usedAt[id] || [])].map(routeLink).join(', ') + '</td></tr>'; }).join('') + '</table></section>');

// Filters
T.push('<section id="filters"><h2>ตัวกรอง</h2><table><tr><th>ตัวกรอง</th><th>ชนิด</th><th>ส่งเป็น</th><th>อยู่ที่</th><th>ค่าเริ่มต้น</th><th>ตัวเลือก</th></tr>'
  + cfg.filters.map(f => '<tr><td>' + esc(f.label) + '</td><td>' + esc(f.type) + '</td><td><code>' + esc(f.param) + '</code></td><td>' + (f.placement === 'bar' ? 'บนจอ' : 'ในแผ่นตัวกรอง') + '</td><td><code>' + esc(JSON.stringify(f.default)) + '</code></td><td>' + (f.options || []).map(x => esc(x.label)).join(', ') + '</td></tr>').join('') + '</table></section>');

// Schemas
T.push('<section id="schemas"><h2>รูปแบบข้อมูล</h2>' + Object.entries(api.components.schemas).map(([n, s]) => '<details class="op" id="schema-' + slug(n) + '"><summary><b>' + esc(n) + '</b> <span class="sum">' + esc(s.description || (s.enum ? 'ค่า: ' + s.enum.join(', ') : '')) + '</span></summary><div class="opb">' + (s.enum ? '<p><code>' + s.enum.map(esc).join(' | ') + '</code></p>' : propsTable(s)) + '</div></details>').join('') + '</section>');

// Reference data
T.push('<section id="reference"><h2>ข้อมูลอ้างอิง</h2><div class="cols"><div><div class="lab">หมวดตาม requirements → กลุ่มบนแผนที่</div><table>' + ref.taxonomies.categories.map(c => '<tr><td>' + esc(c.name) + '</td><td><code>' + esc(c.mapGroup) + '</code></td></tr>').join('') + '</table></div>'
  + '<div><div class="lab">แหล่งข้อมูล</div><table>' + ref.sources.map(s => '<tr><td>' + esc(s.name) + '</td><td>' + esc(s.kind) + '</td></tr>').join('') + '</table><div class="lab">กฎสัญญาณหลอกลวง</div><table>' + ref.scamRules.map(s => '<tr><td><code>' + esc(s.id) + '</code></td><td>' + esc(s.reason) + '</td></tr>').join('') + '</table></div></div></section>');

// Rules
T.push(`<section id="rules"><h2>กติกาที่บังคับฝั่ง server</h2><p class="mut">อยู่ที่ server ย้ายหน้าจอแล้วกติกาไม่หาย ทุกข้อมีการทดสอบใน <code>test-contract.js</code></p><ol class="rules">
<li><b>ตัวเงินมาจากต้นทางเท่านั้น</b> <code>Money.basis</code> = official / listing / none, AI ไม่เติมตัวเงิน</li>
<li><b>AI จัดอันดับเฉพาะรายการที่ server ส่งให้</b> id ที่ไม่อยู่ในรายการและประกาศน่าสงสัยถูกตัดทิ้ง ถ้า AI ล้มใช้กฎแทน (<code>aiStatus: fallback_rules</code>)</li>
<li><b>บันทึกการเรียก AI</b> ทุกครั้งมี <code>aiInvocationId</code> เป็นหลักฐาน AC-02</li>
<li><b>ทุกรายการมีลิงก์ต้นทาง</b> และป้าย <code>dataStatus</code> (live, curated, open_data, mock, blocked)</li>
<li><b>ปักหมุดเฉพาะตำแหน่ง exact</b> ระดับเมืองหรือไม่มีที่ตั้งอยู่ในรายการเท่านั้น</li>
<li><b>ซ่อนประกาศน่าสงสัยเป็นค่าเริ่มต้น</b> และบอกจำนวนที่ซ่อนใน <code>hiddenSuspicious</code></li>
<li><b>ความคืบหน้าเป็นข้อมูลที่ผู้ใช้แจ้ง</b> <code>reportedBy: user</code></li>
<li><b>รายได้สุทธิคำนวณตรง</b> net = gross - cost ไม่ใช้ AI</li></ol></section>`);

const nav = [['overview', 'ภาพรวม'], ['front', 'แยกตามหน้า'], ...groups.map(g => ['tab-' + g.id, '— ' + g.label]), ['api', 'API ตามบริการ'], ...api.tags.map(t => ['svc-' + slug(t.name), '— ' + t.name]), ['actions', 'Action catalog'], ['filters', 'ตัวกรอง'], ['schemas', 'รูปแบบข้อมูล'], ['reference', 'ข้อมูลอ้างอิง'], ['rules', 'กติกาฝั่ง server']];

const html = `<!DOCTYPE html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Money Anywhere - หลังบ้านและ API</title>
<!-- GENERATED by contracts/build-docs.js. Do not edit by hand: edit the contracts and run npm run docs. -->
<style>
:root{--p:#0e9f6e;--pd:#047857;--ink:#0f1f1a;--mut:#6b7c75;--bg:#f3f7f5;--line:#e3ebe7}
*{box-sizing:border-box;font-family:"Segoe UI","Noto Sans Thai",system-ui,sans-serif}
body{margin:0;background:var(--bg);color:var(--ink);font-size:14px;line-height:1.55}
aside{position:fixed;top:0;left:0;bottom:0;width:240px;background:#fff;border-right:1px solid var(--line);padding:18px 14px;overflow-y:auto}
aside h1{font-size:17px;margin:0 0 2px}aside .ver{font-size:11.5px;color:var(--mut);margin-bottom:12px}
aside input{width:100%;padding:9px 11px;border:1.5px solid var(--line);border-radius:10px;font-size:13px;margin-bottom:12px}
aside a{display:block;color:var(--ink);text-decoration:none;padding:5px 8px;border-radius:8px;font-size:13px}aside a:hover{background:#ecfdf5;color:var(--pd)}
main{margin-left:240px;padding:24px 32px 60px;max-width:1200px}
h2{font-size:22px;margin:34px 0 10px;padding-top:8px;border-top:2px solid var(--line)}section:first-child h2{border:0;margin-top:0}
h3{font-size:16px;margin:22px 0 10px}
a{color:var(--pd)}code{background:#eef4f1;padding:1px 6px;border-radius:6px;font-size:12.5px;font-family:Consolas,monospace}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:12px;overflow:hidden;margin:8px 0 14px;box-shadow:0 1px 3px rgba(0,0,0,.05)}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top;font-size:13px}th{background:#f8fbf9;color:var(--mut);font-weight:600}
.mut{color:var(--mut);font-size:12.5px}.req{color:#b42318;font-size:11px;font-weight:700}
.m{display:inline-block;min-width:54px;text-align:center;font-size:11px;font-weight:800;padding:2px 6px;border-radius:6px;color:#fff}
.m-get{background:#2563eb}.m-post{background:#0e9f6e}.m-put{background:#d97706}.m-patch{background:#7c3aed}.m-delete{background:#b42318}
.code{font-size:11.5px;font-weight:800;padding:1px 6px;border-radius:6px}.c2{background:#dcfce7;color:#166534}.c3{background:#e0e7ff;color:#3730a3}.c4{background:#fef3c7;color:#92400e}.c5{background:#fee2e2;color:#991b1b}
.flow{display:flex;align-items:stretch;gap:6px;flex-wrap:wrap;margin:14px 0 18px}
.box{flex:1;min-width:150px;background:#fff;border-radius:14px;padding:12px;box-shadow:0 2px 8px rgba(0,0,0,.06);border-top:4px solid}.box b{display:block}.box span{font-size:12.5px;color:var(--mut)}.box small{display:inline-block;margin-top:6px;font-size:11px;font-weight:700;background:#f3f7f5;padding:1px 7px;border-radius:8px}
.b1{border-color:#2563eb}.b2{border-color:#0e9f6e}.b3{border-color:#d97706}.b4{border-color:#7c3aed}.b5{border-color:#64748b}.arr{display:flex;align-items:center;font-size:20px;color:var(--mut)}
.cmd{background:#0f1f1a;color:#e2f5ec;border-radius:14px;padding:12px 16px}.cmd code{background:#1f3a30;color:#e2f5ec}.cmd pre{margin:8px 0 0;font-family:Consolas,monospace;font-size:12.5px;white-space:pre-wrap}
.tabsum{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}.tabchip{background:#fff;border-radius:20px;padding:7px 14px;text-decoration:none;color:var(--ink);font-weight:600;box-shadow:0 1px 4px rgba(0,0,0,.08)}.tabchip span{color:var(--mut);font-weight:400;font-size:12px}
.tabgrp{margin-bottom:10px}
.card{background:#fff;border-radius:14px;padding:14px 16px;margin-bottom:12px;box-shadow:0 1px 4px rgba(0,0,0,.06)}.ch{margin-bottom:8px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:18px}.lab{font-size:11.5px;font-weight:800;color:var(--mut);text-transform:uppercase;letter-spacing:.04em;margin:8px 0 4px}
.wl{margin:0;padding-left:18px}.wl li{margin-bottom:6px}.bd{font-size:12.5px;color:var(--mut);margin-top:2px}
.apirow{padding:6px 0;border-bottom:1px dashed var(--line)}.apirow:last-child{border:0}
.pill{font-size:11px;background:#f3e8ff;color:#6b21a8;padding:1px 8px;border-radius:8px}
.svc{margin-bottom:8px}.op{background:#fff;border-radius:12px;margin-bottom:8px;box-shadow:0 1px 3px rgba(0,0,0,.05)}.op summary{cursor:pointer;padding:10px 14px;list-style:none}.op summary::-webkit-details-marker{display:none}.op[open] summary{border-bottom:1px solid var(--line)}
.sum{color:var(--mut);margin-left:6px}.opb{padding:10px 14px}.kv{display:flex;gap:10px;font-size:13px;margin-bottom:4px}.kv>span:first-child{width:96px;color:var(--mut);flex:none}
.rules li{margin-bottom:8px;background:#fff;padding:9px 12px;border-radius:10px;list-style-position:inside}
.hide{display:none!important}
@media(max-width:900px){aside{position:static;width:auto;height:auto}main{margin:0;padding:16px}.cols{grid-template-columns:1fr}}
</style></head><body>
<aside><h1>Money Anywhere</h1><div class="ver">หลังบ้านและ API · config ${esc(cfg.configVersion)} · API ${esc(api.info.version)}<br>สร้างเมื่อ ${new Date().toLocaleString('th-TH')}</div>
<input id="q" placeholder="🔍 ค้นหา เช่น tasks, แผนที่, POST" oninput="filt(this.value)">
${nav.map(([id, l]) => '<a href="#' + id + '">' + esc(l) + '</a>').join('')}</aside>
<main>${T.join('\n')}</main>
<script>
function filt(v){v=v.trim().toLowerCase();document.querySelectorAll('.card,.op,table tr[id]').forEach(e=>{const hit=!v||e.textContent.toLowerCase().includes(v);e.classList.toggle('hide',!hit);if(hit&&v&&e.tagName==='DETAILS')e.open=true;});}
document.querySelectorAll('a[href^="#op-"],a[href^="#schema-"]').forEach(a=>a.addEventListener('click',()=>{const t=document.querySelector(a.getAttribute('href'));if(t&&t.tagName==='DETAILS')t.open=true;}));
if(location.hash){const t=document.querySelector(location.hash);if(t&&t.tagName==='DETAILS')t.open=true;}
</script></body></html>`;

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, html);
const unplaced = Object.keys(cfg.actions).filter(a => !usedAt[a]);
console.log('wrote ' + path.relative(path.join(D, '..'), OUT) + ': ' + groups.length + ' front groups, ' + Object.keys(cfg.routes).length + ' routes, ' + ops.length + ' operations, ' + Object.keys(api.components.schemas).length + ' schemas');
if (unplaced.length) console.log('note: actions not placed on any screen: ' + unplaced.join(', '));
