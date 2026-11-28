# พจนานุกรมข้อมูลและ API ของทางรอด

ใช้ `contracts/openapi.yaml` เป็นสัญญา wire format สำหรับ 50 operations และ `contracts/app-config.schema.json` สำหรับ config ตัวอย่าง [API ที่รันจริง](api-examples.json) เลือกเฉพาะ fields ที่ใช้อธิบาย เปลี่ยน origin เป็น `demo.invalid` และใช้ device สำหรับ QA เท่านั้น

## สถานะที่มีความหมายต่างกัน

| มิติ | ค่า | แสดงและใช้ข้อมูลอย่างไร |
| --- | --- | --- |
| ที่มาประกาศ `provenance.dataStatus` | `live`, `curated`, `open_data`, `mock` | `dataMode=real` รวมสามค่าแรก การอนุญาตใช้และวันตรวจเป็นอีกเงื่อนไขหนึ่ง ป้าย `DEMO / MOCK` ต้องติดกับทุกรายการสมมติหรือผลที่ใช้ facts จำลอง |
| จำนวนเงินตามประกาศ `money.basis` | `official`, `listing`, `none` | `official` อัตราจากแหล่งทางการ, `listing` ตามประกาศ, `none` ไม่มีตัวเลข ค่าเงินบาทมีหน่วย เช่น ต่อเดือน ต่อวัน หรือต่องาน |
| จำนวนเงินสิทธิ `amount.basis` | `verified`, `rate`, `calc`, `none` | `rate` อัตราประกาศ, `calc` คำนวณจากคำตอบ, `verified` ต้องมีข้อมูลจาก adapter ที่ยืนยันได้ ส่วนแผนรายได้ใช้ `numberSource` เป็น `official/listing/estimate/none` |
| ผลประเมินสิทธิ `status` | `verified`, `likely`, `unlikely`, `need`, `check` | `need` ขาดคำตอบ, `check` รอตรวจ และ `alreadyReceiving: true` แสดงว่าได้อยู่แล้ว แยกจากยอดเงินใหม่ |
| วิธีที่แชตตอบ `aiStatus` | `ok`, `guarded`, `fallback_rules`, `skipped_no_consent`, `unavailable` ตาม operation | หลักฐาน AI ต้องมี `ok` พร้อม tool call ที่เหมาะสมและ output อ้างกับผล tool ได้ `guarded` บางกรณีมี tool call แต่ใช้กฎ |
| สถานะประกาศกับ task | SQLite `active/needs_review/closed/expired` แยกจาก task `active/blocked/snoozed/finished` | ปิดประกาศแล้วเก็บ progress ตามเดิม การรายงานผลจากผู้ใช้ใช้ป้ายแจ้งเอง |
| คุณภาพข้อมูลที่ใช้ประเมิน | known, unknown, stale, conflict | false และ 0 มีความหมาย ข้อมูลขาด หมดอายุ คนละปี คนละเหตุการณ์ หรือขัดกันให้แยกและถามเพิ่ม |

## Entities ที่ต้องสร้างและรักษาความหมาย

| Entity | ฟิลด์หลัก | กฎความสอดคล้อง |
| --- | --- | --- |
| Device / consent | `X-Device-Id`, `noticeVersion`, `ageConfirmed`, `purposes.core/ai/gov/reminders` | Device ID สุ่มต่อ install ความยาวอย่างน้อย 8 ตัว เป็นการแยก Demo scopes ถือเป็นข้อมูลการทดสอบในระบบปิด |
| Profile / facts | `displayName`, `district`, `skills[]`, `hoursPerWeek`, `constraints`, `ageBand`, `work`, `wage`, `ss33`, `hasUnpaid`, `unpaidDays`, `dailyWage`, `taxWithheld` | `Profile.hoursPerWeek` เป็น string ตามตัวเลือก เช่น `ไม่เกิน 10` ส่วนแผนคำนวณเป็นชั่วโมงตัวเลข Facts มี provenance ตามที่หาได้ ช่วงอายุ, วันเกิด, เขตงาน, เขตทะเบียนบ้าน และข้อมูลทางภาษีเป็นคนละฟิลด์ |
| Fact provenance | source, value, `checkedAt`, `dataStatus`, ช่วงมีผล, ปีภาษี และสถานะ | วันที่จุดตัดใช้ Asia/Bangkok เอกสารเก่าใช้แสดงประวัติได้และไม่แทนคำตอบปัจจุบัน |
| Synthetic source | `thaid`, `tangRat`, `socialSecurity`, `dMyTax` | ThaID ผูก age band. ทางรัฐจำลองสถานะบัตรคนพิการ. SSO จำลอง 8 เดือนจาก 15 เดือน. D-MyTax จำลองภาษีหักไว้ 1,250 บาทในปีตัวอย่าง ให้ถือเป็นภาษีหักและรอตรวจยอดคืน |
| MoneyItem / MoneyRoute | `id`, title, status, amount, `nextQuestion`, documents, sources, channels | รหัสหลัก `old_age`, `disability`, `unemployment`, `unpaid_wages`, `child_support`, `tax_refund` ใช้ค่าตาม `GET /v1/taxonomies` และ fixture อ้างอิง |
| Opportunity | `id`, title, organization, category, mapGroup, location, money, provenance, skills, suspicious, checklistTemplateId | ID คงที่รูป `provider_externalId` เมื่อมาจาก SQLite. Source URL, วันที่ และสถานะอยู่ใน provenance. แยก `location.precision` กับ `coordinateSource` หมุดเขตเป็นจุดรวม |
| Opportunity categories | `welfare`, `refund`, `owed`, `job_full`, `job_part`, `freelance`, `sell`, `assets`, `grant`, `skill` | UI จัดห้าแถบตาม category ใช้ `mapGroup` ต่อกับตัวกรอง API |
| Task / TaskEvent | `id`, `moneyId` หรือ `opportunityId`, `districtCode`, `steps`, `doneCount`, `status`, reason, outcome, event `type` | ข้อมูล source กับความคืบหน้าแยกกัน `complete_step`, `undo`, `block`, `snooze`, `resume`, `report_outcome` เปลี่ยนผ่าน service และป้องกันการทำซ้ำด้วย Idempotency-Key |
| Conversation / action | `conversationId`, `reply`, `step.id`, `step.fact`, `quickReplies`, `toolCalls`, `guard.kind`, `aiStatus`, action ID, `maskedText` | เครื่องมืออ่านได้ตาม consent. เขียนผ่าน confirm, reject หรือ API ของผู้ใช้ที่ได้รับอนุญาตแล้ว `guard.kind` คือผลตรวจข้อความ ส่วน `aiStatus` บอกว่าใครตอบ ใน soft guard ข้อความที่ถูกจับยังตอบได้ด้วย `ok` `maskedText` มีเมื่อ server แทนข้อมูลอ่อนไหวด้วย `[ซ่อน]` |
| Opportunity link | `opportunityId`, `title`, `dataStatus`, `district`, `workMode`, `money`, `sourceUrl`, `sourceStatus` (`ok/unknown/unavailable`), `checkedAt`, `actionId` หรือ `savedTaskId` | field เสริมของผลค้นงานในแชต สร้างจาก record ใน catalogue ไม่เกิน 3 แถว `sourceUrl` เป็น http/https เท่านั้น `actionId` ชี้ `pendingActions[].id` ของรายการเดียวกัน ส่วน `savedTaskId` แทนเมื่อบันทึกไว้แล้ว |
| Job search context | `district`, `districtSource` (`text/profile`), `skill`, `shift`, `workMode`, `excluded`, `resultCount` | ตัวกรองที่ backend ใช้จริงในเทิร์นนั้น ผ่านการตรวจกับรายชื่อเขตและทักษะใน catalogue แล้ว ไม่ส่ง ID ที่ผู้ใช้เห็นแล้วออกนอก server |
| Job store | SQLite `job_source`, `job_posting`, `job_report` | migration 001/002. Source เก็บสิทธิในการจัดเก็บและแสดง, posting มี unique provider/external_id และ state, report เก็บ device hash และเหตุผล |
| User store | JSON layout 2 `identity`, `profile`, `activity`, `runtime` | File mode เก็บ conversation ขณะรันเป็นข้อมูลภายใน และแยกจาก catalogue. Smoke test ใช้ state สังเคราะห์ หลังใช้งานจริงต้องตรวจการคุ้มครองข้อมูลใหม่ |

## ชุดข้อมูลและวิธีนำไปใช้

| แหล่งใน repo อ้างอิง | เนื้อหา | การใช้ |
| --- | --- | --- |
| `contracts/fixtures/gov-prefill-demo.json` | synthetic input shape ของสี่บริการ | ใช้ทดสอบการถามซ้ำและ provenance แสดง DEMO / MOCK และแจ้งตามกติกา |
| `contracts/fixtures/reference.json`, `bangkok-district-map.json` | taxonomy, กฎ, district reference และ fixture ใน reference.json | ติดป้ายแยก static reference กับค่าจำลอง ตรวจที่มาและวันที่ก่อนใช้ |
| `contracts/fixtures/opportunities*.json`, `job-feed.demo.*` | mock input และ reference บางรายการรวมกัน | ตรวจ provenance ทีละรายการก่อนเลือก แยกงานที่มีวันหมดอายุหรือเป็นข้อมูลสมมติ |
| `docs/entities/database-script/demo/catalogue.db` | 5,100 แถว mock, 10 หมวด × 510, 50 เขต, บางนา 200 | ใช้ยืนยัน parity และทดสอบตัวกรอง งานกลุ่ม job ในบางนา 60 แถว แผนที่และลิงก์ประกาศในชุดนี้เป็น Demo |
| `docs/product/sources/bangkok-benefits-2026-11-27.*`, `thai-senior-benefits-2026-11-27.*` | สรุปและลิงก์อ้างอิงสาธารณะ | เปิด source ตามรายการ เก็บวันที่ตรวจและข้อจำกัด |
| [qa-scenarios.json](qa-scenarios.json) | อินพุตสมมติพร้อม assertion | จัดเก็บในส่วน tests/evidence |
| [api-examples.json](api-examples.json) | response ที่ดึงจาก API จริงใน rules-only ด้วย `capture-api-examples.cjs` | ใช้เป็น schema/QA evidence. ระบบเวทีต้องเรียก API และคำนวณผลใหม่ |

เก็บ `.env`, provider keys, runtime state, raw responses ที่มี PII และ AI call logs ของการซ้อมในพื้นที่เครื่องเท่านั้น ไฟล์ Kiro Activity Log วันงานเป็นหลักฐานคนละชนิด ส่งตามช่องทางและรูปแบบของผู้จัด ตรวจ secrets ในข้อมูลที่เปิดเผยก่อนส่ง
