---
title: "job_report"
type: entity
created: 2026-11-26
updated: 2026-11-26
version: "0.1.0"
status: draft-spec
tags: [money-anywhere, database, database-spec, job, report, suspicious, pdpa]
sources:
  - "[[contracts/mock-server.js]] (reports, hiddenByReports, POST /v1/opportunities/{id}/reports)"
  - "[[contracts/openapi.yaml]] (reportOpportunity)"
  - "[[docs/design/backend-gaps.md]] (A13)"
related:
  - "[[database-spec/job_posting]]"
  - "[[database-spec/job_source]]"
  - "[[docs/entities/database-selection]]"
proposed_table: job_report
target_database: "SQLite (catalogue.db) -> PostgreSQL ภายหลัง"
write_allowed: false
---

# job_report

> รุ่นเอกสาร: 0.1.0<br>
> สร้างเมื่อ: 2026-11-26 · อัปเดตล่าสุด: 2026-11-26 · สถานะ: draft-spec

## สรุป

`job_report` เก็บรายงานจากผู้ใช้ว่าประกาศงานน่าสงสัย ข้อมูลผิด หมดอายุ หรืออื่นๆ (1 แถวต่อ 1 รายงาน) ใช้ตัดสินใจซ่อนรายการอัตโนมัติเมื่อมีผู้แจ้ง `suspicious` ครบเกณฑ์ (A13) ปัจจุบันเก็บเป็น array `reports` ใน memory ของ `mock-server.js` และบันทึกใน snapshot พร้อม `hiddenByReports` เอกสารนี้เป็น spec ยังไม่ได้สร้างตารางหรือเขียนโค้ด

## กฎธุรกิจ

1. `POST /v1/opportunities/{id}/reports` รับ `reason` ได้ 4 ค่า: `suspicious`, `wrong_info`, `expired`, `other` ค่าอื่นตอบ 400 `VALIDATION`
2. เมื่อจำนวน **เครื่องที่ต่างกัน** (`device_hash`) ที่แจ้ง `suspicious` ต่อรายการเดียวกันถึงเกณฑ์ (ค่าเริ่มต้น 3 ตั้งได้ด้วย `reportHideThreshold`) ให้ตั้ง `job_posting.hidden_by_reports=1`, `suspicious=1` และเพิ่มเหตุผล "ผู้ใช้หลายคนแจ้งว่าน่าสงสัย ซ่อนไว้รอทีมตรวจ" ใน `suspicious_reasons`
3. เครื่องเดียวแจ้งซ้ำไม่นับเพิ่ม (นับ `DISTINCT device_hash`)
4. เก็บเฉพาะ `device_hash` (SHA-256 ตัดเหลือ 12 ตัวอักษร) ไม่เก็บ `X-Device-Id` ดิบ ตรงกับ `hashDevice()` ที่ใช้กับ log ของ AI
5. `note` เป็นข้อความอิสระจากผู้ใช้ ห้ามบังคับให้ใส่ข้อมูลส่วนบุคคล และแสดงต่อทีมตรวจเท่านั้น
6. ลบประกาศ (ถ้าลบจริง) ให้ลบรายงานตามด้วย `ON DELETE CASCADE` ปกติใช้ `status='closed'` จึงไม่ลบ
7. ปัจจุบันยังไม่มีหน้าให้ทีมตรวจรายงาน (backend-gaps A13 "ซ่อนอัตโนมัติ ยังไม่มีหน้าให้ทีมตรวจ") ตารางนี้เป็นฐานของหน้านั้น

## แหล่งข้อมูลเดิม

| ส่วนใน `mock-server.js` | ใช้ทำอะไร | ย้ายมาที่ |
|---|---|---|
| `reports.push({ device, id, reason, note, at })` | บันทึกรายงาน | แถวใน `job_report` |
| `new Set(reports.filter(...).map(r => r.device)).size` | นับเครื่องที่แจ้ง `suspicious` | `COUNT(DISTINCT device_hash)` |
| `hiddenByReports` (Set) | จำว่ารายการไหนถูกซ่อน | `job_posting.hidden_by_reports` |
| `snapshot()` → `reports`, `hiddenByReports` | บันทึกลงไฟล์ | ตารางนี้และคอลัมน์ในตารางงาน |

## ตารางที่เสนอ

```sql
CREATE TABLE job_report (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id       TEXT NOT NULL REFERENCES job_posting(id) ON DELETE CASCADE,
  device_hash  TEXT NOT NULL,
  reason       TEXT NOT NULL CHECK (reason IN ('suspicious','wrong_info','expired','other')),
  note         TEXT,
  at           TEXT NOT NULL
);

CREATE INDEX idx_report_job ON job_report (job_id, reason);
```

## พจนานุกรมคอลัมน์

| คอลัมน์ | SQLite type | Nullable/default | ความหมาย / แหล่งที่มา | กฎทดสอบ |
|---|---|---|---|---|
| `id` | `INTEGER` PK AUTOINCREMENT | NOT NULL | รหัสรายงาน | ไม่ซ้ำ |
| `job_id` | `TEXT` FK | NOT NULL | ประกาศที่ถูกรายงาน (`/v1/opportunities/{id}`) | มีใน `job_posting` |
| `device_hash` | `TEXT` | NOT NULL | SHA-256 ของ device id ตัด 12 ตัวอักษร | ยาว 12 ตัวอักษร hex; ห้ามเก็บ id ดิบ |
| `reason` | `TEXT` | NOT NULL | `suspicious` / `wrong_info` / `expired` / `other` | allow-list |
| `note` | `TEXT` | NULL | หมายเหตุจากผู้ใช้ | จำกัดความยาว (เสนอ ≤ 500 ตัวอักษร) |
| `at` | `TEXT` ISO-8601 UTC | NOT NULL | เวลาที่รับรายงาน | รูปแบบเวลา |

## ข้อจำกัดและดัชนี

| Kind | ชื่อ / รูปแบบ | เหตุผล |
|---|---|---|
| PK | `id` | |
| FK | `job_id` → `job_posting(id)` `ON DELETE CASCADE` | ไม่ให้รายงานค้างโดยไม่มีประกาศ |
| Check | `reason` ตาม allow-list | |
| Index | `idx_report_job (job_id, reason)` | นับ `DISTINCT device_hash` ต่อประกาศ |

ยังไม่มี unique บน `(job_id, device_hash, reason)` เพราะโค้ดเดิมเก็บทุกรายงานและนับแบบ distinct ตอนอ่าน ถ้าต้องการกันรายงานซ้ำจากเครื่องเดียวให้เพิ่ม unique นี้และใช้ `INSERT OR IGNORE` (ต้องยืนยัน)

## ขั้นตอนเมื่อรับรายงาน

1. ตรวจว่า `job_id` มีอยู่ ไม่พบ → 404 `NOT_FOUND`
2. ตรวจ `reason` ไม่ถูกต้อง → 400 `VALIDATION`
3. insert แถวใน `job_report` (ใช้ `device_hash`)
4. ถ้า `reason='suspicious'`: `SELECT COUNT(DISTINCT device_hash) FROM job_report WHERE job_id=? AND reason='suspicious'` แล้วถ้า ≥ เกณฑ์และ `hidden_by_reports=0` ให้ตั้ง `hidden_by_reports=1`, `suspicious=1` และเพิ่มเหตุผลใน `suspicious_reasons`
5. ตอบ 202 ทั้งหมดอยู่ใน transaction เดียว

## ข้อตกลงคำอธิบาย

SQLite ไม่มี `MS_Description` ให้ใส่คำอธิบายตารางและทุกคอลัมน์เป็นคอมเมนต์ใน migration `.sql` ตามตาราง "พจนานุกรมคอลัมน์" ถ้าย้ายไป PostgreSQL ใช้ `COMMENT ON`

## กฎตรวจสอบข้อมูล

| สิ่งที่ตรวจ | ผลที่คาดหวัง |
|---|---|
| ไม่มีรายงานกำพร้า | ทุก `job_id` มีใน `job_posting` |
| device id | ไม่มี `device_hash` ที่ยาวไม่เท่ากับ 12 หรือเหมือนค่า `X-Device-Id` ดิบ |
| เกณฑ์ซ่อน | ทุกประกาศที่ `COUNT(DISTINCT device_hash)` ของ `suspicious` ≥ เกณฑ์ ต้องมี `hidden_by_reports=1` |
| ความสอดคล้อง | ทุกประกาศที่ `hidden_by_reports=1` ต้องมี `suspicious=1` |
| เครื่องเดียวแจ้งซ้ำ | ไม่ทำให้นับเกินเกณฑ์ |

## จุดที่โค้ดได้รับผลกระทบ

- `mock-server.js`: handler ของ `/v1/opportunities/{id}/reports`, `reports`, `hiddenByReports`, `snapshot()`, `upsert()` (ต้องคง `hidden_by_reports` เมื่อ upsert ซ้ำ)
- test ใน `contracts/test-contract.js` ที่ตรวจกติกา A13
- PDPA: `note` และ `device_hash` ต้องรวมใน `GET /v1/me/export` และถูกลบเมื่อผู้ใช้ลบข้อมูล ซึ่งเป็นข้อกำหนดที่ต้องตัดสินใจ ดู "คำถามที่ยังต้องหาคำตอบ"

## คำถามที่ยังต้องหาคำตอบ

1. เมื่อผู้ใช้ลบข้อมูลตัวเอง (`DELETE /v1/me`) ต้องลบรายงานที่ผู้ใช้เคยส่งด้วยหรือไม่ การลบแถวอาจทำให้ประกาศที่ซ่อนอยู่กลับมาแสดง (ต้องคง `hidden_by_reports` แยก)
2. จะกันรายงานซ้ำจากเครื่องเดียวด้วย unique หรือไม่
3. ใครเป็นผู้ตรวจรายงาน และจะปลด `hidden_by_reports` อย่างไร (ยังไม่มีหน้าและ API)
4. ระยะเวลาเก็บรายงาน (เกี่ยวกับ `RETENTION_DAYS` และ open-items O1)
5. จะเปิดเผยจำนวนรายงานต่อประกาศใน API หรือไม่ (ตอนนี้ไม่เปิดเผย)

## รายการตรวจสอบก่อนอนุมัติ

- [ ] ยืนยันเกณฑ์ซ่อน (ค่าเริ่มต้น 3 เครื่อง)
- [ ] ตัดสินเรื่องลบรายงานเมื่อผู้ใช้ลบข้อมูล
- [ ] ตัดสินเรื่อง unique ของรายงานซ้ำ
- [ ] ตรวจคำอธิบายตารางและทุกคอลัมน์
- [ ] `write_allowed` เปลี่ยนเมื่ออนุมัติเท่านั้น

## ดูเพิ่มเติม

- [job_posting](job_posting.md)
- [job_source](job_source.md)
- [database-selection](../database-selection.md)
- [backend-gaps](../../design/backend-gaps.md)
