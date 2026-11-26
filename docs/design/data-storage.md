# ที่เก็บข้อมูล: เก็บรวมตอนนี้ พร้อมแยก server และ archive ทีหลัง

สถานะ: ทำแล้วใน API 0.11.0 (26 พ.ย. 2569) · ที่ย้ายไปหลัง Demo: ยังไม่ตัดสิน (Owner บอกหลัง Demo)
โค้ด: `contracts/adapters/store.js` · config: `.env` (`DATA_FILE`, `RETENTION_DAYS`, `RETENTION_MODE`, `ARCHIVE_FILE`)

## 1. ตอนนี้
- ข้อมูลทุกเครื่องอยู่ในไฟล์ JSON ไฟล์เดียว (`DATA_FILE`) เขียนแบบ atomic หลังทุกการเปลี่ยน
- แต่ข้อมูลของแต่ละเครื่องถูกแบ่งเป็น 4 collection แล้ว (layout 2) ย้ายแต่ละส่วนไปคนละที่ได้โดยไม่แก้ API และแอป

| Collection | ข้อมูล | ความอ่อนไหว | ย้ายไปได้ที่ | Archive |
|---|---|---|---|---|
| `identity` | ข้อมูลจาก ThaID (`gov`: สถานะ, claims, pidMasked, pidHash, ช่องที่เติมให้) | สูงสุด | server แยกที่คุมเข้มกว่า (ต้อง DPIA) | **ไม่ archive** ลบเมื่อยกเลิกเชื่อมหรือหมดอายุ |
| `profile` | profile, facts, settings, docsReady | กลาง | DB หลัก | ✓ |
| `activity` | consents (ประวัติ), tasks, events, memory | กลาง (consent ต้องเก็บเป็นหลักฐาน) | DB หลัก / audit store | ✓ |
| `runtime` | sessions, conversations, idempotency cache, ตัวนับ, lastSeenAt | ต่ำ อายุสั้น | cache (เช่น Redis) | ไม่ |

ฟิลด์ใหม่ที่ไม่อยู่ในรายการไปอยู่ `runtime` อัตโนมัติ (ไม่หาย) ถ้าจะให้อยู่ collection อื่น แก้ `COLLECTIONS` ใน `store.js`
ไฟล์ layout 1 (API 0.10 และเก่ากว่า) ยังอ่านได้ server เขียนกลับเป็น layout 2 เอง

## 2. ระยะเวลาเก็บ (config แก้ทีหลัง)
| Env | ค่าเริ่ม | ความหมาย |
|---|---|---|
| `RETENTION_DAYS` | `0` (ปิด) | เครื่องที่ไม่ได้ใช้เกิน N วัน ถูกจัดการตาม mode |
| `RETENTION_MODE` | `archive` | `archive` = ย้าย profile + activity ไป `ARCHIVE_FILE` แล้วลบออกจากที่เก็บหลัก · `delete` = ลบเลย |
| `ARCHIVE_FILE` | `DATA_FILE` + `.archive.jsonl` | 1 บรรทัดต่อ 1 เครื่อง: `archivedAt, reason, layout, id, profile, activity` |

- job `retention` รันวันละครั้ง `/v1/health` บอก `retention: {days, mode}` และ `storeLayout`
- identity (ThaID) ไม่ถูก archive ทุกกรณี
- ระยะเวลาจริงต้องให้ Owner และผู้รู้กฎหมายกำหนด (open-items O1) แล้วแก้ใน `.env` ได้เลย

## 3. แผนแยก server (หลัง Demo)
1. เขียน adapter ใหม่ที่ implement `load / save / archive` เดิม แต่เขียนแต่ละ collection ไปที่ของมัน (เช่น Postgres ตาราง `profile`, `activity` แบบ JSONB ต่อ device; `identity` ไป server แยก; `runtime` ไป cache)
2. ย้ายข้อมูล: อ่านไฟล์ layout 2 → เขียนทีละ collection (key = device id)
3. Archive ย้ายไป object storage (ไฟล์ JSONL เดิมใช้ได้เลย)
4. API และแอปไม่ต้องแก้ เทสต์ `npm.cmd test` ชุดเดิมต้องผ่าน

## 4. ข้อควรรู้
- `pidHash` เป็น hash ทางเดียว ใช้จับคู่คนเดียวกันข้ามระบบได้ภายหลัง แต่ยังถือเป็นข้อมูลส่วนบุคคล
- Demo ไม่มีการเข้ารหัสไฟล์ (กฎ Demo) ก่อนใช้จริงต้องเพิ่ม
