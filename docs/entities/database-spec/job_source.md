---
title: "job_source"
type: entity
created: 2026-11-26
updated: 2026-11-26
version: "0.1.0"
status: draft-spec
tags: [money-anywhere, database, database-spec, job, source-register, incremental]
sources:
  - "[[contracts/mock-server.js]] (srcState, refresh, integrations)"
  - "[[contracts/openapi.yaml]] (Source, OpportunityBatch)"
  - "[[contracts/fixtures/reference.json]] (sources)"
  - "[[docs/product/knowledge-database-approach]] (ส่วน 5.4 ทะเบียนแหล่งข้อมูล, 5.5 incremental)"
  - "[[docs/product/thailand-job-data-sources]]"
related:
  - "[[database-spec/job_posting]]"
  - "[[database-spec/job_report]]"
  - "[[docs/entities/database-selection]]"
proposed_table: job_source
target_database: "SQLite (catalogue.db) -> PostgreSQL ภายหลัง"
write_allowed: false
---

# job_source

> รุ่นเอกสาร: 0.1.0<br>
> สร้างเมื่อ: 2026-11-26 · อัปเดตล่าสุด: 2026-11-26 · สถานะ: draft-spec

## สรุป

`job_source` เป็นทะเบียนแหล่งข้อมูลงานและโอกาส (1 แถวต่อ 1 provider) รวม 3 หน้าที่ไว้ในตารางเดียวเพื่อให้ Demo เร็ว:

1. **สถานะการดึงข้อมูล** ที่ `/v1/sources` ใช้ (`state`, `last_fetched_at`, `error`)
2. **ทะเบียนสิทธิ์การใช้ข้อมูล** ตามส่วน 5.4 ของ `knowledge-database-approach` (`can_store`, `can_redisplay`, `commercial_use`, `approved`)
3. **ตัวแทนความคืบหน้า incremental** (`sync_cursor`, `last_run_id`, `last_run_stat`) แทนตารางประวัติการดึงข้อมูลแยก

ปัจจุบันข้อมูลนี้อยู่ใน array `srcState` ใน memory ของ `mock-server.js` (สร้างจาก `reference.json` → `sources` และเพิ่มเมื่อมีผู้ส่งผ่าน Integrations) เอกสารนี้เป็น spec ยังไม่ได้สร้างตารางหรือเขียนโค้ด

## กฎธุรกิจ

1. `provider` เป็นคีย์ธรรมชาติ ตรงกับ prefix ของ `job_posting.id` (`<provider>_<externalId>`) และห้ามเปลี่ยนค่าหลังมีรายการอ้างอิง
2. `direction`: `pull` = server ดึงเอง, `push` = ผู้ให้ข้อมูลส่งผ่าน `/v1/integrations/*`, `static` = ไฟล์ข้อมูลใน repo
3. `data_status` เป็นค่าเริ่มต้นของรายการทั้งหมดจาก provider นี้ ถ้าเป็น `mock` แอปต้องแสดงป้าย DEMO / MOCK
4. `approved = 0` เป็นค่าเริ่มต้น แหล่งที่ยังไม่ตรวจข้อกำหนดการใช้งานห้ามถือว่าใช้เป็นสาธารณะได้ (ส่วน 8 ของ `thailand-job-data-sources`) ฟิลด์สิทธิ์ที่เป็น `NULL` หมายถึงยังไม่ตรวจ ไม่ใช่อนุญาต
5. จำนวนรายการ (`itemCount` ใน API) ไม่เก็บในตาราง คำนวณจาก `COUNT(*)` ของ `job_posting` ตาม `provider`
6. ถ้าการดึงข้อมูลล้มเหลวทั้งรอบ ให้ตั้ง `state='failed'` และห้ามให้ขั้นตอน incremental ตั้งรายการเป็น `needs_review` ด้วยเหตุผล `missing`

## แหล่งข้อมูลเดิม

| ส่วนใน `mock-server.js` | ใช้ทำอะไร | ย้ายมาที่ |
|---|---|---|
| `srcState` ที่สร้างจาก `ref.sources` | รายชื่อ provider, name, kind, attribution, direction, state | แถวตั้งต้นของ `job_source` (seed จาก `reference.json`) |
| `refresh(which)` | ตั้ง `state` เป็น `loading` → `ok` / `failed`, `lastFetchedAt`, `error` | อัปเดต `state`, `last_fetched_at`, `error`, `last_run_*` |
| `POST /v1/integrations/opportunities/batch` | สร้างแถว provider ใหม่ถ้ายังไม่มี (`kind` = "ส่งเข้าผ่าน Integrations") | insert แถว `direction='push'` |
| `fx.official`, ข้อมูล mock | provider `official`, `mock`, `mock_*` | seed ด้วย `data_status` ตามชนิด |

Provider ที่มีใน `reference.json` ตอนนี้: `greenhouse`, `lever` (pull), `bma_open`, `osm`, `curated`, `official`, `mock`, `mock_doe`, `mock_jobboard`, `mock_gig`, `mock_dsd`, `mock_market`, `mock_fund` และ `thaid_mock` (provider ของ ThaID ไม่เกี่ยวกับงาน ไม่ต้องนำเข้าตารางนี้)

## ตารางที่เสนอ

```sql
CREATE TABLE job_source (
  provider         TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  kind             TEXT NOT NULL,
  direction        TEXT NOT NULL CHECK (direction IN ('pull','push','static')),
  attribution      TEXT NOT NULL,
  data_status      TEXT NOT NULL CHECK (data_status IN ('live','curated','open_data','mock')),
  fetch_url        TEXT,
  state            TEXT NOT NULL DEFAULT 'idle' CHECK (state IN ('ok','failed','loading','static','idle')),
  last_fetched_at  TEXT,
  error            TEXT,
  terms_url        TEXT,
  can_store        INTEGER CHECK (can_store      IN (0,1)),
  can_redisplay    INTEGER CHECK (can_redisplay  IN (0,1)),
  commercial_use   INTEGER CHECK (commercial_use IN (0,1)),
  approved         INTEGER NOT NULL DEFAULT 0 CHECK (approved IN (0,1)),
  checked_by       TEXT,
  checked_on       TEXT,
  sync_cursor      TEXT,
  last_run_id      TEXT,
  last_run_at      TEXT,
  last_run_stat    TEXT CHECK (last_run_stat IS NULL OR json_valid(last_run_stat))
);
```

## พจนานุกรมคอลัมน์

| คอลัมน์ | SQLite type | Nullable/default | ความหมาย / แหล่งที่มา | กฎทดสอบ |
|---|---|---|---|---|
| `provider` | `TEXT` PK | NOT NULL | รหัสแหล่งข้อมูล ตรงกับ `Provenance.provider` | ไม่ว่าง, ไม่ซ้ำ, ตัวพิมพ์เล็ก/ตัวเลข/`_` |
| `name` | `TEXT` | NOT NULL | ชื่อที่แสดงใน `/v1/sources` (`Source.name`) | ไม่ว่าง |
| `kind` | `TEXT` | NOT NULL | ชนิดแหล่ง เช่น "API สาธารณะ ไม่ต้องใช้ key", "Mock adapter รอต่อ API จริง" (`Source.kind`) | ไม่ว่าง |
| `direction` | `TEXT` | NOT NULL | `pull` / `push` / `static` (`Source.direction`) | อยู่ใน allow-list |
| `attribution` | `TEXT` | NOT NULL | ข้อความอ้างอิงแหล่งที่มาที่ต้องแสดง (`Provenance.attribution`) | ไม่ว่าง |
| `data_status` | `TEXT` | NOT NULL | สถานะข้อมูลเริ่มต้นของรายการจาก provider นี้ (`DataStatus`) | อยู่ใน allow-list |
| `fetch_url` | `TEXT` | NULL | URL ที่ใช้ดึง (เฉพาะ `pull`) ตรงกับ `url` ใน `reference.json` | ต้องเป็น `https://` เมื่อ `direction='pull'` |
| `state` | `TEXT` | NOT NULL `idle` | สถานะล่าสุด (`Source.state`) | อยู่ใน allow-list |
| `last_fetched_at` | `TEXT` ISO-8601 UTC | NULL | เวลาดึงสำเร็จล่าสุด (`Source.lastFetchedAt`) | รูปแบบเวลา |
| `error` | `TEXT` | NULL | ข้อความผิดพลาดของรอบล่าสุด (`timeout` หรือข้อความ error) | ห้ามมี key หรือ secret |
| `terms_url` | `TEXT` | NULL | ลิงก์ข้อกำหนดการใช้งานของแหล่ง | ต้องเป็น `https://` ถ้ามีค่า |
| `can_store` | `INTEGER` | NULL | เก็บข้อมูลได้หรือไม่ (`NULL` = ยังไม่ตรวจ) | 0/1/NULL |
| `can_redisplay` | `INTEGER` | NULL | แสดงซ้ำต่อผู้ใช้ได้หรือไม่ | 0/1/NULL |
| `commercial_use` | `INTEGER` | NULL | ใช้เชิงพาณิชย์ได้หรือไม่ | 0/1/NULL |
| `approved` | `INTEGER` | NOT NULL `0` | ทีมอนุมัติให้ใช้แหล่งนี้แล้วหรือไม่ | 0/1 |
| `checked_by` | `TEXT` | NULL | ผู้ตรวจข้อกำหนด | ต้องมีเมื่อ `approved=1` |
| `checked_on` | `TEXT` วันที่ | NULL | วันที่ตรวจข้อกำหนด | ต้องมีเมื่อ `approved=1` |
| `sync_cursor` | `TEXT` | NULL | ตัวแทนความคืบหน้าจากต้นทาง (`etag`, `last_modified`, หรือ cursor) ใช้ขอเฉพาะข้อมูลที่เปลี่ยน | ไม่ใช้ในการตัดสินสิทธิ์ |
| `last_run_id` | `TEXT` | NULL | รหัสรอบการดึงล่าสุด เทียบกับ `job_posting.seen_run_id` เพื่อหารายการที่หายไป | ตรงกับ `seen_run_id` ของรายการที่เห็นในรอบนั้น |
| `last_run_at` | `TEXT` | NULL | เวลาเริ่มรอบล่าสุด | รูปแบบเวลา |
| `last_run_stat` | `TEXT` JSON | NULL | สรุปรอบล่าสุด `{"new":n,"changed":n,"unchanged":n,"missing":n}` | JSON ที่ valid |

## ข้อจำกัดและดัชนี

| Kind | ชื่อ / รูปแบบ |
|---|---|
| PK | `provider` |
| Check | `direction`, `data_status`, `state` ตาม allow-list ข้างต้น |
| Check | `can_store`, `can_redisplay`, `commercial_use`, `approved` เป็น 0/1 (สามฟิลด์แรกเป็น NULL ได้) |
| Check | `last_run_stat` เป็น JSON ที่ valid หรือ NULL |
| Index | ไม่ต้องมีเพิ่ม ตารางมีไม่กี่สิบแถว |

## ความสัมพันธ์

- `job_posting.provider` → `job_source.provider` (FK, `NO ACTION`) ห้ามลบ provider ที่ยังมีรายการ
- ไม่มี FK ไปยังฐานผู้ใช้

## กฎ incremental ที่ตารางนี้รองรับ

1. ก่อนดึง: สร้าง `run_id`, ตั้ง `state='loading'`, อ่าน `sync_cursor`
2. ระหว่างดึง: ทุกรายการที่เห็นถูกเขียน `job_posting.seen_run_id = run_id` (ดู [job_posting](job_posting.md))
3. จบรอบสำเร็จ: ตั้ง `last_run_id`, `last_run_at`, `last_run_stat`, `last_fetched_at`, `state='ok'`, อัปเดต `sync_cursor` แล้วจึงตั้งรายการที่ `seen_run_id` ไม่ตรงเป็น `needs_review` (`missing`)
4. ล้มเหลว: ตั้ง `state='failed'`, เก็บ `error`, ไม่แตะ `last_run_id` และไม่ทำขั้นตอนหารายการที่หายไป
5. ทุกขั้นตอนข้างต้นอยู่ใน transaction เดียวกับการ upsert ของรอบนั้น

## ข้อตกลงคำอธิบาย

SQLite ไม่มี `MS_Description` ให้ใส่คำอธิบายตารางและทุกคอลัมน์เป็นคอมเมนต์ใน migration `.sql` และคงตารางคำอธิบายเดียวกับ "พจนานุกรมคอลัมน์" ข้างต้น ถ้าย้ายไป PostgreSQL ให้ใช้ `COMMENT ON TABLE/COLUMN`

## กฎตรวจสอบข้อมูล

| สิ่งที่ตรวจ | ผลที่คาดหวัง |
|---|---|
| ความครบของ provider | ทุก `job_posting.provider` มีแถวใน `job_source` |
| แหล่งที่อนุมัติ | `approved=1` ต้องมี `checked_by`, `checked_on`, `terms_url` และ `can_store`/`can_redisplay` ไม่เป็น NULL |
| แหล่ง mock | provider ที่ `data_status='mock'` ต้องไม่ถูกตั้ง `approved=1` เพื่อใช้เป็นข้อมูลจริง |
| error | `error` ไม่ว่างเมื่อ `state='failed'` และว่างเมื่อ `state='ok'` |
| ตรงกับ `/v1/sources` | response ของ API เท่ากับแถวในตาราง บวก `itemCount` ที่นับจาก `job_posting` |

## จุดที่โค้ดได้รับผลกระทบ

- `mock-server.js`: `srcState`, `refresh()`, handler ของ `/v1/sources`, `/v1/sources/{provider}/refresh`, `/v1/integrations/*`
- `adapters/store.js` และ adapter ใหม่ที่ใช้ SQLite (ยังไม่มี)
- seed script จาก `fixtures/reference.json` → `job_source`

## คำถามที่ยังต้องหาคำตอบ

1. จะบังคับให้ ingest ปฏิเสธแหล่งที่ `approved=0` หรือไม่ ตอนนี้โค้ดไม่ตรวจเงื่อนไขนี้
2. ข้อกำหนดการใช้งานของ JobThai, JobsDB, JobBKK, JobTopGun, JSearch ว่าอย่างไร (ยังไม่ได้อ่าน)
3. กฎ "ข้ามคิวตรวจ" สำหรับ `live`/`mock` ผูกกับ `data_status` อย่างเดียวพอหรือไม่ หรือต้องมีคอลัมน์ `review_required`
4. ใครเป็นผู้ตรวจและอนุมัติแหล่งข้อมูลหลังจบการแข่งขัน

## รายการตรวจสอบก่อนอนุมัติ

- [ ] ทีมยืนยันรายชื่อ provider และ seed จาก `reference.json`
- [ ] ตัดสินกฎ `approved` ใน ingest
- [ ] ยืนยันว่า provider ThaID ไม่อยู่ในตารางนี้
- [ ] ตรวจคำอธิบายตารางและทุกคอลัมน์
- [ ] `write_allowed` เปลี่ยนเมื่ออนุมัติเท่านั้น

## ดูเพิ่มเติม

- [job_posting](job_posting.md)
- [job_report](job_report.md)
- [database-selection](../database-selection.md)
- [knowledge-database-approach](../../product/knowledge-database-approach.md)
- [thailand-job-data-sources](../../product/thailand-job-data-sources.md)
