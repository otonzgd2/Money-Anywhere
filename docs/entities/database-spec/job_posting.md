---
title: "job_posting"
type: entity
created: 2026-11-26
updated: 2026-11-26
version: "0.1.0"
status: draft-spec
tags: [money-anywhere, database, database-spec, job, opportunity, incremental, search]
sources:
  - "[[contracts/mock-server.js]] (opps, upsert, search, refresh, checkLinks, webhooks)"
  - "[[contracts/openapi.yaml]] (Opportunity, Location, Money, Provenance, OpportunityInput)"
  - "[[contracts/fixtures/opportunities.json]]"
  - "[[contracts/fixtures/opportunities-mock.json]]"
  - "[[docs/product/knowledge-database-approach]] (ส่วน 5.3, 5.5)"
related:
  - "[[database-spec/job_source]]"
  - "[[database-spec/job_report]]"
  - "[[docs/entities/database-selection]]"
proposed_table: job_posting
target_database: "SQLite (catalogue.db) -> PostgreSQL ภายหลัง"
write_allowed: false
---

# job_posting

> รุ่นเอกสาร: 0.1.0<br>
> สร้างเมื่อ: 2026-11-26 · อัปเดตล่าสุด: 2026-11-26 · สถานะ: draft-spec

## สรุป

`job_posting` เก็บประกาศงานและโอกาสรายได้ในประเทศไทย (1 แถวต่อ 1 รายการ) เป็นตารางหลักที่ `GET /v1/opportunities` ใช้ค้นหา ออกแบบให้ **flat และ denormalize** เพื่อให้ค้นหาจากตารางเดียวโดยไม่ต้อง join และรองรับ **incremental update** ด้วย `content_hash`, `seen_run_id`, `status`, `version` และ `prev_snapshot`

ปัจจุบันข้อมูลอยู่ใน `Map` ชื่อ `opps` ใน `mock-server.js` ประมาณ 95 รายการ (base mock 15, mock catalogue 77, official 3) บวก Greenhouse/Lever เมื่อ `LIVE=1` รายการ mock/live ถูกสร้างใหม่จาก fixture ทุกครั้งที่เปิด server เอกสารนี้เป็น spec ยังไม่ได้สร้างตารางหรือเขียนโค้ด

## กฎธุรกิจ

1. `id` = `<provider>_<externalId>` คง format เดิมของ API (`/v1/opportunities/{id}`) และ `UNIQUE (provider, external_id)`
2. ตัดรายการซ้ำข้าม provider ด้วย `dedup_key = norm(title) | norm(organization)` provider แรกที่เข้าระบบชนะ ถ้าเป็น provider เดียวกันไม่ถือว่าซ้ำ (ตรงกับ `upsert()` เดิม) `norm` = ตัวพิมพ์เล็ก ตัดข้อความในวงเล็บ และตัดทุกอย่างที่ไม่ใช่ตัวอักษร/ตัวเลข
3. ตัวเลขเงิน (`money_*`) มาจากประกาศหรือแหล่งทางการเท่านั้น AI ไม่เติม (`money_basis`: `official` / `listing` / `none`)
4. ทุกรายการต้องมี `source_url` เป็น `https://` หรือ `http://`
5. `loc_precision='exact'` ต้องมี `lat`, `lng` (ตรงกับ `validInput`)
6. รายการ `suspicious` ถูกซ่อนจากผลค้นหาเป็นค่าเริ่มต้น แต่ยังนับเป็น `hiddenSuspicious` `suspicious` มาจากกฎ `scamRules` ตอน ingest หรือจากรายงานผู้ใช้ 3 เครื่อง (`hidden_by_reports=1` ต้องคงอยู่แม้ upsert ซ้ำ)
7. `link_status='broken'` (ตอบ 404/410 จาก job `link_check`) ต้องไม่ปรากฏในผลค้นหา ส่วน 403/405 ให้เป็น `unknown` ไม่ซ่อน
8. ค้นหาแสดงเฉพาะ `status='active'` และ `expires_at` ว่างหรือยังไม่เลยกำหนด
9. `ageDays` และ `distanceKm` คำนวณตอนอ่าน ไม่เก็บ

## กฎ incremental update

ตัวแปร: `run_id` ของรอบดึง (เก็บใน `job_source.last_run_id` เมื่อจบรอบ) และ `content_hash` ของรายการจากต้นทาง

| เหตุการณ์ | การเขียนข้อมูล |
|---|---|
| ไม่พบ `(provider, external_id)` | insert, `version=1`, `seen_run_id=run_id` ถ้าแหล่งเป็น curated/official: `status='needs_review'`, `review_reason='new'` ถ้าเป็น live/mock: `status='active'` |
| พบ และ `content_hash` เท่าเดิม | อัปเดตเฉพาะ `seen_run_id`, `fetched_at` |
| พบ และ `content_hash` ต่าง | เก็บค่าเดิมลง `prev_snapshot`, `version = version + 1`, อัปเดตฟิลด์ แหล่ง curated/official: `needs_review` + `review_reason='changed'` แหล่ง live/mock: `active` |
| จบรอบสำเร็จ และไม่พบรายการของ provider ที่ `status='active'` ในรอบนี้ | `status='needs_review'`, `review_reason='missing'` ไม่ลบ |
| รอบล้มเหลว | ไม่ทำขั้นตอน `missing` |
| webhook `opportunity.closed` | `status='closed'` |
| เลย `expires_at` | `status='expired'` (job ประจำวัน) หรือถูกกรองตอนค้นหา |
| คนยืนยันรายการที่ `needs_review` | `status='active'`, ตั้ง `verified_at`, `verified_by`, ล้าง `review_reason` |

`content_hash` คำนวณจาก: `title`, `organization`, `category`, `map_group`, `loc_*`, `lat`, `lng`, `money_*`, `conditions`, `skills`, `for_older`, `expires_at` **ไม่รวม** `fetched_at`, `updated_at`, `link_*` และฟิลด์ที่ server คำนวณ (ต้องยืนยัน ดู "คำถามที่ยังต้องหาคำตอบ")

ทั้งรอบอยู่ใน transaction เดียว ตาม `job_source` (ดู [job_source](job_source.md))

## ตารางที่เสนอ

```sql
CREATE TABLE job_posting (
  id                  TEXT PRIMARY KEY,
  provider            TEXT NOT NULL REFERENCES job_source(provider),
  external_id         TEXT NOT NULL,
  title               TEXT NOT NULL,
  organization        TEXT,
  category            TEXT NOT NULL,
  map_group           TEXT NOT NULL,
  search_text         TEXT NOT NULL,
  dedup_key           TEXT NOT NULL,

  loc_precision       TEXT NOT NULL DEFAULT 'none' CHECK (loc_precision IN ('exact','city','none')),
  loc_text            TEXT,
  lat                 REAL,
  lng                 REAL,

  money_basis         TEXT NOT NULL CHECK (money_basis IN ('official','listing','none')),
  money_min           REAL,
  money_max           REAL,
  money_unit          TEXT,
  money_known_text    TEXT,

  conditions          TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(conditions)),
  skills              TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(skills)),
  for_older           INTEGER NOT NULL DEFAULT 0 CHECK (for_older IN (0,1)),

  source_url          TEXT NOT NULL,
  posted_at           TEXT,
  updated_at          TEXT,
  expires_at          TEXT,
  fetched_at          TEXT NOT NULL,
  link_status         TEXT NOT NULL DEFAULT 'unknown' CHECK (link_status IN ('ok','broken','unknown')),
  link_checked_at     TEXT,

  suspicious          INTEGER NOT NULL DEFAULT 0 CHECK (suspicious IN (0,1)),
  suspicious_reasons  TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(suspicious_reasons)),
  hidden_by_reports   INTEGER NOT NULL DEFAULT 0 CHECK (hidden_by_reports IN (0,1)),

  status              TEXT NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','needs_review','closed','expired')),
  content_hash        TEXT NOT NULL,
  seen_run_id         TEXT,
  version             INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  prev_snapshot       TEXT CHECK (prev_snapshot IS NULL OR json_valid(prev_snapshot)),
  review_reason       TEXT CHECK (review_reason IS NULL OR review_reason IN ('new','changed','missing')),
  verified_at         TEXT,
  verified_by         TEXT,

  UNIQUE (provider, external_id),
  CHECK (loc_precision <> 'exact' OR (lat IS NOT NULL AND lng IS NOT NULL)),
  CHECK (status <> 'needs_review' OR review_reason IS NOT NULL)
);

CREATE INDEX idx_job_filter ON job_posting (status, suspicious, map_group, category);
CREATE INDEX idx_job_geo    ON job_posting (lat, lng) WHERE loc_precision = 'exact';
CREATE INDEX idx_job_dedup  ON job_posting (dedup_key);
CREATE INDEX idx_job_prov   ON job_posting (provider, seen_run_id);
CREATE INDEX idx_job_review ON job_posting (status, provider) WHERE status = 'needs_review';
```

## พจนานุกรมคอลัมน์

| คอลัมน์ | SQLite type | Nullable/default | ความหมาย / แหล่งที่มา | กฎทดสอบ |
|---|---|---|---|---|
| `id` | `TEXT` PK | NOT NULL | `provider_externalId` (`Opportunity.id`) | ไม่ว่าง, ขึ้นต้นด้วย `provider_` |
| `provider` | `TEXT` FK | NOT NULL | แหล่งข้อมูล (`Provenance.provider`) | มีใน `job_source` |
| `external_id` | `TEXT` | NOT NULL | id จากต้นทาง (`OpportunityInput.externalId`) | ไม่ว่าง |
| `title` | `TEXT` | NOT NULL | ชื่อประกาศ | ไม่ว่าง |
| `organization` | `TEXT` | NULL | ชื่อองค์กร/ผู้ประกาศ | - |
| `category` | `TEXT` | NOT NULL | หมวด 1 ใน 10 หมวด (`taxonomies.categories`) เช่น `job_full`, `job_part`, `freelance` | มีใน taxonomy |
| `map_group` | `TEXT` | NOT NULL | `job`, `skill`, `sell`, `money` | มีใน taxonomy |
| `search_text` | `TEXT` | NOT NULL | `lower(title || ' ' || organization)` ใช้ค้นด้วย `LIKE` | สร้างจาก title/organization เสมอ |
| `dedup_key` | `TEXT` | NOT NULL | `norm(title) \| norm(organization)` | ตรงกับ `dupKey()` |
| `loc_precision` | `TEXT` | NOT NULL `none` | ความแม่นของตำแหน่ง (`Location.precision`) | allow-list |
| `loc_text` | `TEXT` | NULL | ข้อความที่อยู่ (`Location.text`) | - |
| `lat`, `lng` | `REAL` | NULL | พิกัด (บังคับเมื่อ `exact`) | ช่วงพิกัดที่ถูกต้อง |
| `money_basis` | `TEXT` | NOT NULL | ที่มาของตัวเลข (`Money.basis`) | allow-list |
| `money_min`, `money_max` | `REAL` | NULL | ช่วงเงิน บาท | `min <= max` เมื่อมีทั้งคู่ |
| `money_unit` | `TEXT` | NULL | หน่วย เช่น `บาท/วัน`, `บาท/เดือน` | - |
| `money_known_text` | `TEXT` | NULL | สิ่งที่รู้เมื่อ `basis='none'` | - |
| `conditions` | `TEXT` JSON | NOT NULL `[]` | เงื่อนไขของประกาศ (array ของข้อความ) | JSON array |
| `skills` | `TEXT` JSON | NOT NULL `[]` | ทักษะที่ประกาศต้องการ | JSON array |
| `for_older` | `INTEGER` | NOT NULL `0` | รับผู้สูงอายุ | 0/1 |
| `source_url` | `TEXT` | NOT NULL | ลิงก์กลับต้นทาง | ขึ้นต้น `http(s)://` |
| `posted_at` | `TEXT` | NULL | เวลาประกาศ | ISO-8601 UTC |
| `updated_at` | `TEXT` | NULL | เวลาที่ต้นทางแก้ล่าสุด (ใช้คำนวณ `ageDays`) | ISO-8601 UTC |
| `expires_at` | `TEXT` | NULL | เวลาหมดอายุ/ปิดรับ | ISO-8601 UTC |
| `fetched_at` | `TEXT` | NOT NULL | เวลาที่ server ดึง/รับล่าสุด | ISO-8601 UTC |
| `link_status` | `TEXT` | NOT NULL `unknown` | ผลตรวจลิงก์ (`ok`/`broken`/`unknown`) | allow-list |
| `link_checked_at` | `TEXT` | NULL | เวลาตรวจลิงก์ล่าสุด | ISO-8601 UTC |
| `suspicious` | `INTEGER` | NOT NULL `0` | ถูกกฎ scam หรือรายงานผู้ใช้ | 0/1 |
| `suspicious_reasons` | `TEXT` JSON | NOT NULL `[]` | เหตุผล (array ของข้อความไทย) | JSON array; ไม่ว่างเมื่อ `suspicious=1` |
| `hidden_by_reports` | `INTEGER` | NOT NULL `0` | ถูกซ่อนเพราะรายงานครบเกณฑ์ ต้องคงอยู่แม้ upsert ซ้ำ | 0/1 |
| `status` | `TEXT` | NOT NULL `active` | `active` / `needs_review` / `closed` / `expired` | allow-list |
| `content_hash` | `TEXT` | NOT NULL | hash ของฟิลด์ที่ใช้เทียบ (ดูกฎ incremental) | คำนวณซ้ำแล้วต้องตรงกับค่าที่เก็บ |
| `seen_run_id` | `TEXT` | NULL | รอบล่าสุดที่เห็นรายการที่ต้นทาง | ใช้หา `missing` |
| `version` | `INTEGER` | NOT NULL `1` | เลขเวอร์ชัน เพิ่มเมื่อ hash เปลี่ยน | ≥ 1 |
| `prev_snapshot` | `TEXT` JSON | NULL | ค่าก่อนเปลี่ยนล่าสุด (รอบเดียว) | JSON ที่ valid |
| `review_reason` | `TEXT` | NULL | `new` / `changed` / `missing` | ต้องมีเมื่อ `needs_review` |
| `verified_at` | `TEXT` | NULL | เวลาที่คนยืนยัน | ISO-8601 UTC |
| `verified_by` | `TEXT` | NULL | ผู้ยืนยัน | ห้ามมี secret |

## การจับคู่กับ API (`Opportunity`)

| ฟิลด์ API | คอลัมน์ |
|---|---|
| `id`, `title`, `organization`, `category`, `mapGroup` | `id`, `title`, `organization`, `category`, `map_group` |
| `location` | `loc_precision`, `loc_text`, `lat`, `lng` (`distanceKm` คำนวณตอนค้นหา) |
| `money` | `money_basis`, `money_min`, `money_max`, `money_unit`, `money_known_text` |
| `conditions`, `skills`, `forOlder` | `conditions`, `skills`, `for_older` |
| `provenance` | `provider`, `source_url`, `posted_at`, `updated_at`, `expires_at`, `fetched_at`, `link_status`, `link_checked_at`, ส่วน `dataStatus` และ `attribution` มาจาก `job_source` (`ageDays` คำนวณ) |
| `suspicious`, `suspiciousReasons` | `suspicious`, `suspicious_reasons` |
| `checklistTemplateId` | ไม่เก็บ เท่ากับ `category` เสมอ |

## ข้อจำกัดและดัชนี

| Kind | ชื่อ / รูปแบบ | เหตุผล |
|---|---|---|
| PK | `id` | |
| FK | `provider` → `job_source(provider)` | |
| Unique | `(provider, external_id)` | รองรับ upsert |
| Index | `idx_job_filter (status, suspicious, map_group, category)` | เงื่อนไขหลักของ `search()` |
| Index | `idx_job_geo (lat, lng) WHERE loc_precision='exact'` | bounding box ก่อนคำนวณ Haversine |
| Index | `idx_job_dedup (dedup_key)` | หาซ้ำข้าม provider ตอน ingest |
| Index | `idx_job_prov (provider, seen_run_id)` | หา `missing` ท้ายรอบ |
| Index | `idx_job_review (status, provider)` บางส่วน | แสดงคิวตรวจ |
| Check | `exact` ต้องมีพิกัด; `needs_review` ต้องมี `review_reason`; JSON ต้อง valid | |

## แนวทางค้นหาให้เร็ว

1. ช่วง Demo ใช้ `Map` เดิมเป็น read cache และให้ SQLite เป็น write-through (โหลดเข้า `Map` ตอนเปิด server) `search()` และ contract tests เดิมไม่ต้องแก้
2. เมื่อข้อมูลโตเกินหลักหมื่น ย้าย search เป็น SQL: กรองด้วย `idx_job_filter` และ bounding box แล้วคำนวณ Haversine และเรียงใน JS รายการที่ `loc_precision<>'exact'` ต้องรวมเข้ามาเสมอ เพราะโค้ดเดิมไม่กรองรัศมีรายการเหล่านั้น
3. เปิด `PRAGMA journal_mode=WAL`, `synchronous=NORMAL`, ใช้ prepared statement และ transaction เดียวต่อ batch (สูงสุด 500 รายการตาม API)
4. ค้นข้อความด้วย `LIKE '%q%'` บน `search_text` ไม่ใช้ FTS เพราะไม่ตัดคำไทย
5. การเรียง: `near` ใช้ระยะที่คำนวณ, `money` ใช้ `money_max` (NULL เป็น -1), `fresh` ใช้ `updated_at`

## ข้อตกลงคำอธิบาย

SQLite ไม่มี `MS_Description` ให้ใส่คำอธิบายตารางและทุกคอลัมน์เป็นคอมเมนต์ใน migration `.sql` ตามตาราง "พจนานุกรมคอลัมน์" ถ้าย้ายไป PostgreSQL ใช้ `COMMENT ON`

## กฎตรวจสอบข้อมูล

| สิ่งที่ตรวจ | ผลที่คาดหวัง |
|---|---|
| ไม่ซ้ำ | ไม่มี `(provider, external_id)` ซ้ำ |
| ซ้ำข้าม provider | ไม่มี `dedup_key` เดียวกันข้าม provider ที่ `status='active'` |
| พิกัด | ทุกแถว `exact` มี `lat`, `lng` |
| เงิน | `money_basis='none'` ต้องไม่มี `money_min/max` |
| คิวตรวจ | ทุกแถว `needs_review` มี `review_reason` |
| ความถูกต้องของ hash | คำนวณ `content_hash` ใหม่จากแถวแล้วต้องเท่ากับค่าที่เก็บ |
| ซ่อนถาวร | แถวที่ `hidden_by_reports=1` ต้องมี `suspicious=1` เสมอ หลัง upsert ซ้ำ |
| mock | แถวที่ `job_source.data_status='mock'` ต้องแสดงป้าย DEMO / MOCK ใน API |

## จุดที่โค้ดได้รับผลกระทบ

- `mock-server.js`: `opps`, `upsert()`, `refresh()`, `search()`, `/v1/opportunities*`, `/v1/integrations/*`, `checkLinks()`, `snapshot()`/`persist()`, การอ่านจาก `plans/goal` และเครื่องมือ AI (`search_opportunities`)
- `adapters/store.js` (ต้องเพิ่ม adapter SQLite และ repository ฝั่งงาน)
- `snapshot()` เดิมเก็บเฉพาะรายการที่ส่งผ่าน Integrations หลังย้ายตารางนี้ต้องครอบคลุมทุกรายการ และ seed ข้อมูล mock/official จาก fixture ด้วยการ upsert ที่รันซ้ำได้

## คำถามที่ยังต้องหาคำตอบ

1. ฟิลด์ใดบ้างอยู่ใน `content_hash` (ข้อเสนอข้างต้น ยังไม่ได้ตกลง)
2. แหล่ง live/mock ข้ามคิวตรวจได้ใช่หรือไม่ และ curated/official ต้องผ่านคิวทุกครั้งที่เปลี่ยน
3. รายการ `needs_review` (new/changed) ควรแสดงให้ผู้ใช้เห็นระหว่างรอตรวจหรือไม่ ข้อเสนอคือไม่แสดง
4. ทุนและบริการรัฐที่เปลี่ยนช้า (`official`, `mock_fund`, `mock_dsd`) จะอยู่ในตารางนี้ต่อไป หรือย้ายไปฐานความรู้แยกตาม `knowledge_item`
5. ระยะเวลาเก็บรายการ `closed`/`expired` ก่อนลบ
6. Task ของผู้ใช้ที่อ้าง `opportunity_id` ของรายการที่ปิดแล้ว ต้องแสดงอย่างไร (task เก็บ `title` ซ้ำไว้แล้ว)

## รายการตรวจสอบก่อนอนุมัติ

- [ ] ยืนยันฟิลด์ใน `content_hash`
- [ ] ยืนยันกฎคิวตรวจแยกตามชนิดแหล่ง
- [ ] ยืนยันการแยกไฟล์ฐานข้อมูลจากฐานผู้ใช้
- [ ] ทดสอบ search เทียบผลกับ `mock-server.js` เดิมด้วย fixture ชุดเดียวกัน
- [ ] ตรวจคำอธิบายตารางและทุกคอลัมน์
- [ ] `write_allowed` เปลี่ยนเมื่ออนุมัติเท่านั้น

## ดูเพิ่มเติม

- [job_source](job_source.md)
- [job_report](job_report.md)
- [database-selection](../database-selection.md)
- [knowledge-database-approach](../../product/knowledge-database-approach.md)
- [thailand-job-data-sources](../../product/thailand-job-data-sources.md)
