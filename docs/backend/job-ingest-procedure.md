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

## เปิดใช้การอัปเดต DEMO / MOCK

เมื่อกำหนด `JOB_DB_FILE` เซิร์ฟเวอร์พร้อมรับคำสั่งอัปเดตแหล่ง `mock_doe` จากฟีดจำลองใน `contracts/fixtures/opportunities-mock.json` ค่าเริ่มต้นเป็นแบบสั่งเอง ใช้ `JOB_AUTO_SYNC=0` เพื่อกำหนดโหมดนี้ชัดเจน และ `JOB_AUTO_SYNC=1` เพื่อเปิดการดึงตอนเริ่มรับคำขอและทุก 1 ชั่วโมง

รันคำสั่งนี้จากโฟลเดอร์รากของ repo บน PowerShell

```powershell
$env:JOB_DB_FILE = (Resolve-Path 'docs/entities/database-script/catalogue.db').Path
$env:LIVE = '0'
$env:JOB_AUTO_SYNC = '0'
npm.cmd --prefix .\contracts run mock
```

สำหรับการทดสอบฟีดอื่น ให้กำหนด `MOCK_JOB_FEED_FILE` เป็นพาธของไฟล์ JSON ที่คัดลอกมาจากฟีดตัวอย่าง เซิร์ฟเวอร์อ่านไฟล์ใหม่ทุกรอบ ใช้ `POST /v1/sources/mock_doe/refresh` เพื่อรันทันที และ `GET /v1/sources` เพื่อตรวจสถานะกับเวลาที่ดึงสำเร็จล่าสุด

ฟิลด์ `job_source.last_run_stat` บันทึกจำนวน `new`, `changed`, `unchanged` และ `missing` ของรอบที่สำเร็จ หากรายการที่ยังเปิดรับหายตั้งแต่ 50% รอบนั้นจะล้มเหลวและคงข้อมูลเดิม ประกาศที่ต้นทางส่งสถานะ `closed` หรือถึงวันหมดอายุใช้สถานะ `closed` หรือ `expired` ตามลำดับ

## เปิดอัปเดต Jobicy เข้าฐาน SQLite

กำหนด `JOB_DB_FILE` ตามตัวอย่างด้านบน แล้วกำหนด `$env:JOBICY_SYNC = '1'` ก่อนรัน Backend ใช้ `JOB_AUTO_SYNC=0` เพื่อสั่งเอง หรือ `JOB_AUTO_SYNC=1` เพื่อตรวจตอนเปิด Backend และทุก 1 ชั่วโมง ระบบอ่านเวลาเริ่มรอบล่าสุดจาก SQLite เพื่อเว้นอย่างน้อย 1 ชั่วโมงระหว่างรอบทั้งสองโหมด

- `GET /v1/health` แสดงงาน `jobicy_refresh` พร้อมผลรอบล่าสุด และ `GET /v1/sources` แสดงเวลาที่ดึงสำเร็จ
- `POST /v1/sources/jobicy/refresh` สั่งตรวจว่าครบรอบแล้วหรือยังเมื่อเปิด `JOBICY_SYNC`
- ฟีด Jobicy ครอบคลุมประกาศที่เผยแพร่ในช่วง 7 วัน และอาจมีหลายหน้า ตัวดึงคัดประกาศที่ระบุ Thailand หรือ Anywhere ชัดเจน หากประกาศเดิมหลุดจากฟีด ระบบตรวจสถานะกับ Jobicy ก่อนเปลี่ยนสถานะใน SQLite
- เก็บชื่อประกาศ นายจ้าง พื้นที่ ลิงก์ Jobicy วันประกาศ และค่าจ้างที่ระบุเป็นบาท ข้อมูลค่าจ้างสกุลอื่นอ้างกลับไปยังประกาศต้นทาง

[เอกสาร Public API ของ Jobicy](https://jobicy.com/jobs-rss-feed)

## ดึงฟีด CSV/JSON

กำหนด `JOB_FEEDS_FILE` เป็นพาธของไฟล์ตั้งค่าฟีด JSON แล้วรัน Backend ด้วย `JOB_DB_FILE` ที่ชี้ฐาน SQLite ตัวอย่างนี้เตรียมฟีด DEMO / MOCK สองแหล่งสำหรับสั่งนำเข้าจากไฟล์ในโครงการ

```powershell
$env:JOB_FEEDS_FILE = (Resolve-Path 'contracts/fixtures/job-file-feeds.demo.json').Path
$env:JOB_AUTO_SYNC = '0'
npm.cmd --prefix .\contracts run mock
```

- แต่ละรายการกำหนด `provider` และ `format` เป็น `csv` หรือ `json` ค่าเริ่มต้น `everyMinutes` คือ 60 และกำหนดค่าเป็นรายแหล่งได้
- ถ้าต้นทางวางไฟล์ในเครื่อง Backend ให้ระบุ `file` พาธสัมพัทธ์นับจากโฟลเดอร์ไฟล์ตั้งค่า สำหรับฟีดจำลองให้ระบุ `mock: true` และใช้รหัสที่ขึ้นต้นด้วย `mock_` ฟีดจำลองที่ผ่านเงื่อนไขนี้จะขึ้นทะเบียนให้อัตโนมัติ
- สำหรับแหล่งจริง ก่อนตั้งเวลาต้องลงทะเบียนเป็น `direction='pull'` และอนุมัติสิทธิ์เก็บและแสดงข้อมูลตามนโยบายโครงการ หากใช้ไฟล์ออนไลน์ให้เว้น `file` และกำหนดปลายทาง HTTPS ใน `job_source.fetch_url` รูปแบบข้อมูลใช้ฟิลด์เดียวกับการนำเข้าไฟล์จากพาร์ทเนอร์ด้านล่าง
- Backend ตรวจ ETag หรือ Last-Modified ตามที่ต้นทางรองรับ และเปรียบเทียบเนื้อหาไฟล์กับรอบก่อน ถ้าไฟล์เสียหรือดึงล้มเหลว ข้อมูลและตัวชี้รอบสำเร็จล่าสุดจะยังอยู่ ถ้าประกาศหายจากไฟล์ที่ส่งมาเพียงบางส่วน ระบบคงสถานะเดิมไว้
- เรียก `POST /v1/sources/<provider>/refresh` เพื่อสั่งนำเข้าด้วยมือ แล้วตรวจผลของ `job_file_refresh_<provider>` ที่ `GET /v1/health` ค่า `enabled` บอกสถานะการตั้งเวลา

### เปิดฟีดเว็บงานไทย

ใช้ [ตัวอย่างการตั้งค่าฟีดห้าเว็บ](../../contracts/fixtures/thailand-partner-job-feeds.example.json) สำหรับ `jobthai`, `jobsdb`, `jobbkk`, `jobtopgun` และ `fastwork` ตัวอย่างตั้ง `enabled: false` ไว้ในแต่ละแหล่ง ให้เปิดเฉพาะแหล่งที่ได้รับฟีดแล้ว

1. ลงทะเบียนฟีดใน `job_source` ด้วยรหัสแหล่งที่ตรงกับไฟล์ตั้งค่า กำหนด `direction='pull'` และเก็บ URL ของฟีดใน `fetch_url` พร้อมผลตรวจสิทธิ์ตาม [นโยบายแหล่งข้อมูล](job-source-policy.md)
2. ตั้ง `format` ให้ตรงกับ CSV หรือ JSON ในรูปแบบกลางของ Backend แล้วเปลี่ยนแหล่งนั้นเป็น `enabled: true` ถ้าฟีดใช้คีย์ ให้เพิ่ม `auth` เช่น `{ "type": "api-key", "env": "PARTNER_JOB_FEED_KEY" }` โดยตั้งค่าคีย์ใน environment ของ Backend ใช้ `type: "bearer"` สำหรับฟีดที่รับ Bearer token
3. เริ่มด้วย `JOB_AUTO_SYNC=0` แล้วสั่ง `POST /v1/sources/<provider>/refresh` ตรวจจำนวนแถว ลิงก์ต้นทาง และสถานะใน SQLite เมื่อตรวจผลแล้วจึงเริ่ม Backend ด้วย `JOB_AUTO_SYNC=1`

ห้าแหล่งนี้ใช้รอบเริ่มต้น **5 นาที** และตั้ง `everyMinutes` ให้มากขึ้นได้ตามเงื่อนไขของเจ้าของฟีด ฟีดออนไลน์เก็บเวลาเริ่มดึงไว้ใน SQLite การสั่งซ้ำหรือรีสตาร์ตก่อนครบช่วงเวลาจึงข้ามการเรียกรอบนั้น

### รับข้อมูลจาก Apify

[ตัวอย่างการตั้งค่า Apify](../../contracts/fixtures/apify-job-feeds.example.json) เตรียมรอบ 5 นาทีสำหรับ `jobthai`, `jobbkk` และ `fastwork` โดยปิดแต่ละแหล่งไว้จนกว่าจะมีสิทธิ์ใช้ข้อมูลและ Actor Task ที่พร้อม ฟีดของ Fastwork สำหรับตารางงานใช้ประกาศจากฝั่งผู้จ้างใน Jobboard

1. หลังยืนยันเงื่อนไขการดึง เก็บ และแสดงข้อมูลกับต้นทางแล้ว ให้ทดสอบ Actor Task ทีละแหล่งและตรวจว่า Dataset มีฟิลด์ `OpportunityInput` ตาม [API contract](../../contracts/openapi.yaml) รวมถึงรหัสประกาศที่คงเดิมและ URL สมัคร
2. กำหนด `job_source.fetch_url` ของแหล่งนั้นเป็น `https://api.apify.com/v2/actor-tasks/<task-id>/runs/last/dataset/items?status=SUCCEEDED&format=json` และตั้ง `APIFY_JOB_FEEDS_TOKEN` ใน environment ของ Backend ระบบส่งคีย์ผ่าน Authorization header และอ่านผลจากรอบที่สำเร็จล่าสุด [เอกสาร Dataset API ของ Apify](https://docs.apify.com/api/v2/actor-task-runs-last-dataset-items-get)
3. เปิด `enabled` เฉพาะแหล่งที่ผ่านการตรวจ แล้วทดสอบสั่งนำเข้าด้วยมือหนึ่งรอบ หากผลถูกต้อง ให้ตั้งเวลา Actor Task ใน Apify และเปิด `JOB_AUTO_SYNC=1` สำหรับ Backend การตั้งเวลาใน Apify ใช้สร้างผลลัพธ์ใหม่ ส่วน Backend ตรวจผลและนำเข้า SQLite ทุก 5 นาที หรือตามรอบที่เจ้าของแหล่งอนุญาต [เอกสารตั้งเวลา Apify](https://docs.apify.com/actors/running/schedules)

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

## นำเข้าไฟล์จากพาร์ทเนอร์

เปิด Backend ด้วย `JOB_DB_FILE` และใช้รหัสแหล่งที่ลงทะเบียนใน `job_source` เป็น `direction='push'` แล้ว สำหรับแหล่งจริงให้บันทึกผลตรวจสิทธิ์เก็บและแสดงข้อมูลตาม [นโยบายแหล่งข้อมูล](job-source-policy.md) ก่อนเปิดใช้ Backend ใช้สถานะและเครดิตจากทะเบียน รายการ `curated` ใหม่หรือที่เปลี่ยนเนื้อหาจะเข้าคิวตรวจ

ตั้ง `INTEGRATION_KEY` ใน environment ของเครื่องที่ส่งข้อมูล แล้วรันจากโฟลเดอร์โครงการด้วย PowerShell 7

```powershell
.\contracts\import-job-batch.ps1 -Provider partner_code -InputFile .\jobs.csv -BaseUrl http://127.0.0.1:8080
```

- ไฟล์ CSV เป็น UTF-8 ใช้คอลัมน์ `externalId,title,category,sourceUrl` และเพิ่ม `organization,province,district,workMode,locationText,precision,lat,lng,moneyBasis,moneyMin,moneyMax,moneyUnit,skills,conditions,postedAt,updatedAt,expiresAt,status` ตามข้อมูลต้นทาง ใช้ `|` คั่นสมาชิกใน `skills` และ `conditions`
- ไฟล์ JSON เป็นอาร์เรย์รายการ หรือมี `items` เป็นอาร์เรย์ รูปร่างแต่ละรายการใช้ `OpportunityInput` ใน [OpenAPI](../../contracts/openapi.yaml)
- สคริปต์แบ่งส่งครั้งละไม่เกิน 500 รายการและรายงาน `accepted`, `rejected` และ `merged` พร้อมตำแหน่งในไฟล์เดิม ใช้รหัสประกาศเดิมเมื่อส่งซ้ำเพื่ออัปเดตแถวเดิม ใช้ `status=closed` หรือ webhook เมื่อต้นทางยืนยันว่าปิดรับ
- `GET /v1/opportunities` รองรับ `province`, `district`, `workMode` และ `skill` จากข้อมูลที่แหล่งส่งมา ถ้า URL ประกาศเดียวกันมาจากมากกว่าหนึ่งแหล่ง API เก็บแยกทุกแถวและรวมผลค้นหาพร้อม `provenance.sourceLinks`
- Backend เพิ่มคอลัมน์สถานที่และรูปแบบงานจาก [สคริปต์ 002](../entities/database-script/002_job_location_filters.sql) เมื่อเปิดฐานเดิมครั้งแรก ค่าว่างหมายถึงแหล่งยังไม่ระบุ

## ดูเพิ่มเติม

- [job-data-scope-lock](job-data-scope-lock.md)
- [job-source-policy](job-source-policy.md)
- [job-data-quality-rules](job-data-quality-rules.md)
- [job-acceptance-tests](job-acceptance-tests.md)
- [job_posting](../entities/database-spec/job_posting.md)
- [job_source](../entities/database-spec/job_source.md)
