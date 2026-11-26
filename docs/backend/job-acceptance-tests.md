---
title: "Job Data: Acceptance Tests"
type: ai-lock-spec
created: 2026-11-26
updated: 2026-11-26
version: "0.1.0"
status: draft-spec
tags: [money-anywhere, ai-lock, job, test, acceptance, definition-of-done]
sources:
  - "[[contracts/test-contract.js]]"
  - "[[.kiro/hooks/money-contracts-test.json]]"
related:
  - "[[job-data-scope-lock]]"
  - "[[job-ingest-procedure]]"
  - "[[job-data-quality-rules]]"
---

# Job Data: Acceptance Tests

> รุ่นเอกสาร: 0.1.0 · สร้างเมื่อ: 2026-11-26 · สถานะ: draft-spec

## วัตถุประสงค์

กำหนดเกณฑ์ว่า "เสร็จ" หมายถึงอะไรสำหรับงานข้อมูลงาน AI ต้องรันการทดสอบและรายงานผลจริง ห้ามสรุปว่าผ่านโดยไม่ได้รัน

## วิธีรัน

รันในโฟลเดอร์ `contracts/` (PowerShell ที่ปิดการรันสคริปต์ให้ใช้ `npm.cmd`):

```
cmd /c "npm.cmd run check > .data\check.txt 2>&1"
```

แล้วอ่าน `.data/check.txt` และรายงานจำนวนที่ผ่าน/ล้ม ตามที่ hook `money-contracts-test.json` กำหนด ถ้ามีข้อใดล้ม ต้องแก้ก่อนรายงาน

## กติกาของการทดสอบ

1. ใช้ฐานข้อมูลแบบ memory หรือไฟล์ชั่วคราวที่สร้างใหม่ทุกครั้ง **ห้ามชี้ `DATA_FILE`, `AI_LOG_FILE` หรือฐานงานไปที่ข้อมูลจริง**
2. ห้ามเรียกเครือข่ายภายนอกจริงใน test ให้ใช้ `fetch` จำลองที่ `createServer({ fetch })` รองรับ
3. ข้อมูลทดสอบสร้างจาก fixture หรือสร้างในเทสต์ ห้ามใช้ข้อมูลที่ดึงจากแหล่งจริงเป็น expected value
4. `test-contract.js` ตรวจทุก response กับ schema และล้มถ้ามี operation ที่ไม่ถูกเรียก endpoint ใหม่ต้องมี test เรียก
5. `MOCK_CATALOGUE` ปิดไว้ใน test อื่นเพื่อให้ตัวเลขคงที่ เปิดเฉพาะเซิร์ฟเวอร์ที่ทดสอบ catalogue

## ชุดทดสอบที่ต้องมี

รหัส `JT-` ต่อไปนี้ต้องมี test ที่ตรวจค่าที่คาดหวังเป็นรายข้อ test ที่ไม่ตรวจค่าไม่นับ

### Incremental ingest

| รหัส | เงื่อนไข | ผลที่ต้องเป็น |
|---|---|---|
| JT-01 | รายการใหม่จากแหล่ง live/mock | insert `status='active'`, `version=1`, `seen_run_id` = รอบนั้น, นับ `new` |
| JT-02 | รายการใหม่จากแหล่ง curated/official | insert `status='needs_review'`, `review_reason='new'`, ไม่ปรากฏในผลค้นหา |
| JT-03 | รอบที่ 2 ข้อมูลเหมือนเดิม | ไม่มีฟิลด์ธุรกิจเปลี่ยน `version` เท่าเดิม `seen_run_id` ใหม่ นับ `unchanged` |
| JT-04 | เปลี่ยนค่าจ้างของรายการเดิม (แหล่ง live) | `version=2`, `prev_snapshot` เก็บค่าเดิม, `content_hash` เปลี่ยน, `status='active'`, นับ `changed` |
| JT-05 | เปลี่ยนเงื่อนไขของรายการ curated | `status='needs_review'`, `review_reason='changed'`, ค่าที่แสดงให้ผู้ใช้ยังเป็นค่าเดิมจนกว่าคนยืนยัน (ตามที่ตัดสินใน scope-lock) |
| JT-06 | รายการหายจากต้นทางในรอบที่สำเร็จ | `status='needs_review'`, `review_reason='missing'`, ไม่ลบแถว, นับ `missing` |
| JT-07 | รอบที่ล้มเหลว (fetch error/timeout) | `state='failed'`, มี `error`, rollback, ไม่มีรายการถูกตั้ง `missing`, `last_run_id` ไม่เปลี่ยน, `sourceWarnings` มี provider นี้ |
| JT-08 | ต้นทางตอบสำเร็จแต่ว่างเปล่า (เมื่อกำหนดค่ากันผิดพลาดแล้ว) | ไม่ตั้ง `missing` ทั้งหมด, `state='failed'` พร้อมข้อความ |
| JT-09 | รันรอบเดียวกันซ้ำ 2 ครั้ง | ผลเหมือนรันครั้งเดียว (idempotent) |
| JT-10 | webhook `opportunity.closed` | `status='closed'` ไม่ลบแถว ไม่ปรากฏในผลค้นหา |
| JT-11 | คนยืนยันรายการ `needs_review` | `status='active'`, มี `verified_at`, `verified_by`, ไม่มี `review_reason` |
| JT-12 | รายการที่ `expires_at` เลยกำหนด | ไม่ปรากฏในผลค้นหา และ job ตั้งเป็น `expired` |

### ความถูกต้องและแหล่งข้อมูล

| รหัส | เงื่อนไข | ผลที่ต้องเป็น |
|---|---|---|
| JT-20 | รายการซ้ำข้าม provider (ชื่อ+องค์กรเดียวกัน) | provider แรกชนะ ตอบ `merged` ไม่ insert แถวซ้ำ |
| JT-21 | ชื่อเดียวกันใน provider เดียวกัน | ไม่ถือว่าซ้ำ |
| JT-22 | รายการขาดฟิลด์บังคับ, `sourceUrl` ไม่ใช่ http(s), `exact` ไม่มีพิกัด, `basis` นอก allow-list | ถูกปฏิเสธ ตอบ `rejected` พร้อม `index` และเหตุผล ไม่ insert |
| JT-23 | ประกาศตรงกฎ scam | `suspicious=1` มีเหตุผล ไม่แสดงในผลค้นหาปกติ นับใน `hiddenSuspicious` |
| JT-24 | provider ที่ `approved=0` และไม่ใช่ mock (เมื่อ Owner ยืนยันกฎนี้) | ไม่ ingest |
| JT-25 | provider mock | ทุกรายการมีป้าย DEMO / MOCK ใน `provenance` |
| JT-26 | `money_basis='none'` | ไม่มี `money_min`/`money_max` และ AI ไม่เติมค่า |
| JT-27 | ข้อความในประกาศมีเบอร์โทรหรืออีเมลบุคคล | ไม่ถูกเก็บ (ตัดออกหรือปฏิเสธตามกฎที่ตกลง) |
| JT-28 | `link_check` ได้ 404/410 | `link_status='broken'` และไม่ปรากฏในผลค้นหา |
| JT-29 | `link_check` ได้ 403/405 หรือ timeout | `link_status='unknown'` ยังแสดงอยู่ |

### รายงานผู้ใช้

| รหัส | เงื่อนไข | ผลที่ต้องเป็น |
|---|---|---|
| JT-30 | 3 เครื่องแจ้ง `suspicious` | `hidden_by_reports=1`, `suspicious=1`, เหตุผลถูกเพิ่ม |
| JT-31 | เครื่องเดียวแจ้ง 3 ครั้ง | ไม่ถึงเกณฑ์ ไม่ซ่อน |
| JT-32 | รายการที่ถูกซ่อนเพราะรายงาน ถูก upsert ซ้ำ | ยังซ่อนอยู่ (`hidden_by_reports` คงเดิม) |
| JT-33 | `reason` นอก allow-list | 400 `VALIDATION` |
| JT-34 | รายงานประกาศที่ไม่มี | 404 `NOT_FOUND` |
| JT-35 | `device_hash` | ยาว 12 ตัวอักษร hex และไม่เท่ากับ `X-Device-Id` |

### การค้นหาและ API

| รหัส | เงื่อนไข | ผลที่ต้องเป็น |
|---|---|---|
| JT-40 | ค้นด้วย fixture ชุดเดียวกับ `mock-server.js` เดิม | ผลลัพธ์ (รายการ ลำดับ `near`/`money`/`fresh` และ cursor) เท่ากับของเดิม |
| JT-41 | รายการ `loc_precision<>'exact'` | ไม่ถูกกรองด้วยรัศมี (เหมือนโค้ดเดิม) |
| JT-42 | ค้นแล้วไม่พบ | ตอบ `suggestions` ตามเงื่อนไข ไม่เติมรายการอื่นแทน |
| JT-43 | `/v1/sources` | `itemCount` นับจาก `job_posting` ตรงกับจำนวนจริงต่อ provider |
| JT-44 | schema ของ response | ผ่านการตรวจกับ `openapi.yaml` ไม่มี breaking change |
| JT-45 | เวลาตอบของ `GET /v1/opportunities` กับข้อมูลชุด Demo (ประมาณ 100 รายการ) | บันทึกค่าที่วัดได้ในรายงาน (ยังไม่กำหนดเกณฑ์ ต้องตกลงกับเจ้าของโครงการ) |

### การตั้งค่าและความปลอดภัย

| รหัส | เงื่อนไข | ผลที่ต้องเป็น |
|---|---|---|
| JT-50 | seed จาก fixture รันซ้ำ | จำนวนแถวไม่เพิ่ม ไม่เกิดรายการซ้ำ |
| JT-51 | restart แล้วเปิดฐานเดิม (ไฟล์ชั่วคราว) | ข้อมูลและ `hidden_by_reports` ยังอยู่ |
| JT-52 | ค้นด้วยข้อความที่มีอักขระพิเศษของ SQL | ไม่เกิด error และไม่เปลี่ยนข้อมูล (parameterized query) |
| JT-53 | `/v1/integrations/*` ไม่มี `X-Api-Key` | ถูกปฏิเสธ |
| JT-54 | ค้นใน repo หา key/token ที่เพิ่มเข้ามา | ไม่พบ ความลับไม่ถูกเขียนลงไฟล์ที่ commit |

## เกณฑ์ว่าเสร็จ (Definition of Done)

- [ ] `npm.cmd run check` ผ่านทั้งหมด และรายงานจำนวนที่ผ่าน
- [ ] ทุกรหัส JT ที่เกี่ยวกับงานนี้มี test ที่ตรวจค่าที่คาดหวัง
- [ ] ไม่มีการแก้ไฟล์นอกขอบเขตใน `job-data-scope-lock.md`
- [ ] ไม่มีหัวข้อที่ยังไม่ตัดสินถูกเลือกโดยไม่ถาม
- [ ] สเป็คตารางและเอกสารในชุดนี้ตรงกับโค้ด (ถ้าโค้ดเปลี่ยนสเป็ค ต้องแก้เอกสารและบอกเจ้าของโครงการ)
- [ ] ถ้าเปลี่ยน API: ขยับ `info.version` ใน `openapi.yaml` กับ `package.json` ให้ตรงกัน และเพิ่มรายการใน `CHANGELOG.md`
- [ ] รายงานสิ่งที่ยังไม่ได้ทดสอบ (เช่น การเรียกแหล่งจริง, ทดสอบบนมือถือ)

## รูปแบบรายงานผล

```
ผลทดสอบ: ผ่าน X / ทั้งหมด Y (คำสั่ง: ...)
รหัส JT ที่ครอบคลุม: ...
รหัส JT ที่ยังไม่ได้ทำ: ... (เหตุผล)
สิ่งที่ไม่ได้ทดสอบ: ...
หัวข้อที่ยังไม่ตัดสินที่เจอ: ...
ไฟล์ที่เปลี่ยน: ...
```

## ดูเพิ่มเติม

- [job-data-scope-lock](job-data-scope-lock.md)
- [job-ingest-procedure](job-ingest-procedure.md)
- [job-data-quality-rules](job-data-quality-rules.md)
