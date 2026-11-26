---
title: "Job Data: Ingest Procedure"
type: ai-lock-spec
created: 2026-11-26
updated: 2026-11-26
version: "0.1.0"
status: draft-spec
tags: [money-anywhere, ai-lock, job, ingest, incremental, content-hash]
sources:
  - "[[contracts/mock-server.js]] (upsert, refresh, integrations, checkLinks)"
  - "[[docs/product/knowledge-database-approach]] (ส่วน 5.5)"
related:
  - "[[job-data-scope-lock]]"
  - "[[job-source-policy]]"
  - "[[job-data-quality-rules]]"
  - "[[job-acceptance-tests]]"
  - "[[database-spec/job_posting]]"
  - "[[database-spec/job_source]]"
---

# Job Data: Ingest Procedure

> รุ่นเอกสาร: 0.1.0 · สร้างเมื่อ: 2026-11-26 · สถานะ: draft-spec

## วัตถุประสงค์

ขั้นตอนที่ AI ต้องทำตามเมื่อเขียนหรือแก้ส่วนที่นำข้อมูลงานเข้าตาราง `job_posting` แบบ incremental คือเขียนเฉพาะรายการที่เปลี่ยน ไม่ลบรายการที่หายไปทันที และไม่เขียนทับข้อมูลที่ต้องให้คนตรวจ ขั้นตอนนี้ต่อยอดจาก `upsert()` และ `refresh()` ใน `mock-server.js` ซึ่งปัจจุบัน `refresh` ลบรายการของ provider ทั้งหมดแล้วใส่ใหม่

## คำศัพท์

| คำ | ความหมาย |
|---|---|
| รอบ (run) | การดึงหรือรับข้อมูลหนึ่งครั้งจาก provider หนึ่งราย มี `run_id` เฉพาะ |
| `content_hash` | แฮชของฟิลด์ที่ใช้เทียบว่ารายการเปลี่ยนหรือไม่ |
| `seen_run_id` | `run_id` ล่าสุดที่เห็นรายการนี้ที่ต้นทาง |
| รายการที่ต้องตรวจ | `status='needs_review'` พร้อม `review_reason` ใน `new`, `changed`, `missing` |
| แหล่งที่ต้องผ่านคิว | `data_status` เป็น `curated` หรือ `open_data` (และ `official`) |
| แหล่งที่เขียนทับได้ | `data_status` เป็น `live` หรือ `mock` (**ข้อเสนอ ยังไม่ตัดสิน** ดู `job-data-scope-lock.md` หัวข้อ 2) |

## การคำนวณ `content_hash`

1. สร้างวัตถุที่มีเฉพาะฟิลด์ที่ใช้เทียบ (**รายการข้างล่างเป็นข้อเสนอ ยังไม่ตกลง ให้ถามก่อนใช้จริง**): `title`, `organization`, `category`, `map_group`, `loc_precision`, `loc_text`, `lat`, `lng`, `money_basis`, `money_min`, `money_max`, `money_unit`, `money_known_text`, `conditions`, `skills`, `for_older`, `expires_at`
2. **ไม่รวม:** `fetched_at`, `updated_at`, `link_status`, `link_checked_at`, `seen_run_id`, `version` และฟิลด์ที่ server คำนวณ (`suspicious`, `suspicious_reasons`, `distanceKm`, `ageDays`)
3. ทำให้เป็นรูปแบบมาตรฐาน: ตัดช่องว่างหัวท้าย ยุบช่องว่างซ้ำ ใช้ `null` สำหรับค่าว่าง เรียงทักษะ (`skills`) ตามตัวอักษร คงลำดับ `conditions` ตามต้นทาง จัดเรียง key ของวัตถุตามตัวอักษร
4. แปลงเป็น JSON แล้วคำนวณ SHA-256 เก็บเป็น hex
5. ฟังก์ชันนี้ต้องเป็นฟังก์ชันเดียวที่ทุกที่เรียกใช้ และมีการทดสอบว่าข้อมูลเหมือนเดิมให้ผลเท่าเดิม

## ลำดับขั้นตอนต่อรอบ

ทุกขั้นตอนใน 3 ถึง 8 ต้องอยู่ใน transaction เดียวต่อ provider (ถ้า batch เกิน 500 รายการ ให้แบ่ง transaction แต่ต้องกำกับด้วย `run_id` เดียวกัน และตั้ง `missing` เมื่อจบทุก batch เท่านั้น)

1. **ตรวจสิทธิ์:** อ่านแถว `job_source` ตาม `job-source-policy.md` ถ้าไม่ผ่านให้หยุด ไม่ดึง
2. **เริ่มรอบ:** สร้าง `run_id` (เช่น timestamp UTC + ตัวสุ่มสั้น) ตั้ง `state='loading'` อ่าน `sync_cursor`
3. **ดึงข้อมูล:** เรียกต้นทางด้วย timeout และมารยาทตามนโยบายแหล่ง ถ้าล้มเหลวให้ไปขั้น "รอบล้มเหลว"
4. **ตรวจแต่ละรายการ** ตาม `job-data-quality-rules.md` รายการที่ไม่ผ่านให้เก็บเหตุผลลงสรุปรอบ (`rejected`) ไม่ insert
5. **หารายการซ้ำข้าม provider:** `SELECT id FROM job_posting WHERE dedup_key=? AND provider<>? LIMIT 1` ถ้าพบ ให้ข้ามรายการนี้และนับเป็น `merged` (provider แรกชนะ) provider เดียวกันที่ key ซ้ำไม่นับว่าซ้ำ
6. **เทียบกับของเดิม** โดยค้นด้วย `(provider, external_id)` แล้วเขียนตามตาราง:

| กรณี | การเขียน | นับใน `last_run_stat` |
|---|---|---|
| ไม่พบ | insert, `version=1`, `seen_run_id=run_id` แหล่งที่ต้องผ่านคิว: `status='needs_review'`, `review_reason='new'` แหล่งที่เขียนทับได้: `status='active'` | `new` |
| พบ และ hash เท่าเดิม | อัปเดตเฉพาะ `seen_run_id`, `fetched_at` และถ้าเดิม `needs_review`/`active` ให้คงสถานะ | `unchanged` |
| พบ และ hash ต่าง | `prev_snapshot` = ค่าก่อนเปลี่ยน, `version = version + 1`, อัปเดตฟิลด์และ `content_hash`, `seen_run_id` แหล่งที่ต้องผ่านคิว: `needs_review` + `review_reason='changed'` แหล่งที่เขียนทับได้: `active` | `changed` |
| พบ แต่ `status` เป็น `closed`/`expired` และต้นทางส่งกลับมา | ถือเป็นรายการเปลี่ยน ใช้กฎ "hash ต่าง" และเปิดกลับตามกฎแหล่ง | `changed` |

7. **หารายการที่หายไป (เฉพาะรอบที่ดึงสำเร็จครบ):** รายการของ provider นี้ที่ `status='active'` และ `seen_run_id <> run_id` ให้ตั้ง `status='needs_review'`, `review_reason='missing'` ห้ามลบ นับเป็น `missing`
8. **จบรอบ:** อัปเดต `job_source`: `last_run_id`, `last_run_at`, `last_run_stat` (JSON), `last_fetched_at`, `sync_cursor`, `state='ok'`, `error=NULL` แล้ว commit

## รอบล้มเหลว

- ตั้ง `state='failed'`, เก็บ `error` (ไม่มี key หรือข้อมูลลับ), **rollback** การเขียนของรอบนั้น
- **ห้าม** ตั้งรายการเป็น `missing` และห้ามแตะ `last_run_id`
- ข้อมูลเดิมยังแสดงต่อได้ และ `/v1/opportunities` ต้องแจ้งใน `sourceWarnings` ว่ามี provider ที่ดึงล้มเหลว
- ห้ามแต่งข้อมูลทดแทน (FR-08)

## กันผิดพลาดเรื่องรายการหายพร้อมกันจำนวนมาก (ข้อเสนอ ต้องยืนยันค่า)

ถ้าต้นทางตอบสำเร็จแต่ว่างเปล่าผิดปกติ รายการทั้งหมดจะถูกตั้ง `missing` ให้ตั้งเกณฑ์ เช่น ถ้ารายการที่จะถูกตั้ง `missing` เกินสัดส่วนที่ตกลงของรายการ `active` ของ provider นั้น ให้ยกเลิกขั้น 7 ตั้ง `state='failed'` พร้อมข้อความ และแจ้งเจ้าของโครงการ ค่าสัดส่วนต้องตัดสินกับเจ้าของโครงการ ห้ามเดา

## เส้นทางอื่นที่เขียนตาราง `job_posting`

| เส้นทาง | การเขียน |
|---|---|
| `POST /v1/integrations/opportunities/batch` | ใช้ขั้น 4 ถึง 6 ต่อรายการ ไม่เกิน 500 รายการต่อครั้ง ตอบ `accepted`, `rejected` (มี `index` และเหตุผล), `merged` ตามสัญญาเดิม และไม่ทำขั้น 7 เพราะผู้ส่งอาจส่งเป็นบางส่วน เว้นแต่ผู้ส่งระบุว่าเป็นชุดเต็ม (ต้องตัดสินเมื่อเพิ่มความสามารถนี้) |
| webhook `opportunity.closed` | `status='closed'` ไม่ลบ |
| webhook `opportunity.updated` | ใช้ขั้น 4 ถึง 6 กับรายการเดียว |
| job `link_check` (วันละครั้ง) | อัปเดต `link_status`, `link_checked_at` ตามผล HEAD: 404/410 → `broken`, ต่ำกว่า 400 → `ok`, อื่นๆ รวมทั้ง 403/405 และ timeout → `unknown` ไม่ซ่อน ไม่ตรวจรายการ `mock` |
| job หมดอายุ | รายการ `active` ที่ `expires_at` เลยกำหนด → `expired` |
| รายงานผู้ใช้ | ดู `job_report.md` ตั้ง `hidden_by_reports=1` และ `suspicious=1` เมื่อครบเกณฑ์ ต้องคงค่านี้เมื่อ upsert ซ้ำ |
| คนยืนยันรายการที่ `needs_review` | `status='active'`, ตั้ง `verified_at`, `verified_by`, ล้าง `review_reason` |

## ข้อบังคับของโค้ด

- ใช้ prepared statement และ transaction ห้ามประกอบ SQL จากข้อความภายนอกด้วยการต่อสตริง
- ฟังก์ชัน ingest ต้องรันซ้ำด้วยข้อมูลเดิมแล้วไม่เปลี่ยนอะไร (idempotent) นอกจาก `seen_run_id`, `fetched_at`
- Seed จาก fixture ใช้ขั้นตอนเดียวกัน (ไม่เขียนทางลัด)
- เปิด `PRAGMA journal_mode=WAL`, `synchronous=NORMAL` เฉพาะฐาน SQLite
- Log จำนวนและเหตุผลสรุปรอบ ไม่ log เนื้อหาประกาศทั้งก้อนหรือข้อมูลลับ
- ห้ามให้ AI/LLM เขียนหรือแก้ค่าฟิลด์ใน `money_*` (ดู `job-data-quality-rules.md`)

## ดูเพิ่มเติม

- [job-data-scope-lock](job-data-scope-lock.md)
- [job-source-policy](job-source-policy.md)
- [job-data-quality-rules](job-data-quality-rules.md)
- [job-acceptance-tests](job-acceptance-tests.md)
- [job_posting](../entities/database-spec/job_posting.md)
- [job_source](../entities/database-spec/job_source.md)
