# Backend Design: Money Anywhere (ร่างสำหรับ R&D)

สถานะ: ข้อเสนอ ยังไม่ผ่าน AI-DLC design และยังไม่ได้ Owner อนุมัติ ไม่ได้เลือก stack แทนทีม
สัญญากลาง (ใช้ร่วมกัน 3 คน): `contracts/openapi.yaml`, `contracts/app-config.schema.json`, `contracts/app-config.sample.json`
ตรวจความถูกต้องของ config: `node contracts/validate-config.js [config.json]`

## 1. โจทย์
ย้ายเมนู ปุ่ม หรือ action ไปหน้าไหนก็ได้ โดยไม่ต้องแก้ backend และไม่ทำให้ส่วนอื่นพัง

### สาเหตุที่ระบบทั่วไปย้ายแล้วพัง
1. API ออกแบบตามหน้าจอ เช่น `/home-data` พอย้ายปุ่มออกจากหน้าแรก endpoint ก็ไม่ตรง
2. แอปฝังที่อยู่ endpoint ไว้ในปุ่ม ย้ายปุ่มต้องแก้โค้ดและออกเวอร์ชันใหม่
3. หลังทำ action แล้ว หน้าอื่นที่แสดงข้อมูลเดียวกันไม่อัปเดต เพราะรีเฟรชเฉพาะหน้าที่กด
4. รายการตัวเลือก (หมวด ทักษะ ตัวกรอง) ฝังในแอป เพิ่มหรือย้ายต้องออกเวอร์ชันใหม่

## 2. หลักออกแบบ: แยก "อะไร" ออกจาก "อยู่ที่ไหน"

| ชั้น | ตอบคำถาม | เปลี่ยนบ่อยแค่ไหน | อยู่ที่ |
|---|---|---|---|
| Resource API | ข้อมูลและการกระทำมีอะไรบ้าง | น้อย | `openapi.yaml` (ตาม resource ไม่ตามหน้าจอ) |
| Action catalog | action id นี้เรียก endpoint ไหน | น้อย | `actions` ใน app-config |
| Layout config | อะไรอยู่หน้าไหน ปุ่มไหนเรียก action ไหน | บ่อย | `tabs`, `routes`, `filters` ใน app-config |
| Widget catalog | ชิ้นส่วน UI ที่แอปวาดได้ | ปานกลาง | โค้ด Flutter (ชุดตายตัว) |

ผลคือ:
- **ย้ายปุ่ม:** แก้แค่ `routes` ใน config ไม่ต้องแตะ API หรือ action catalog
- **ย้าย endpoint:** แก้แค่ `actions.<id>.path` หน้าจอไม่รู้ตัว
- **เพิ่มหมวด ทักษะ หรือตัวกรอง:** แก้ taxonomy หรือ `filters` ไม่ต้องออกแอปใหม่

## 3. กลไกที่ทำให้ย้ายได้จริง

### 3.1 Action อ้างด้วย id เท่านั้น
ทุกปุ่มเป็น binding รูปแบบเดียว:
```json
{ "action": "task.step.complete", "params": { "id": "$ctx.task.id" }, "then": { "toast": "บันทึกแล้ว" } }
```
- `$ctx.<path>` อ่านค่าจากข้อมูลที่ widget นั้นแสดงอยู่ ปุ่มเดียวกันจึงวางในการ์ดหน้าแรก ในแผนของฉัน หรือในรายละเอียดก็ได้
- action ไม่รู้ว่าถูกเรียกจากหน้าไหน backend ก็ไม่ต้องรู้

### 3.2 อัปเดตทุกหน้าด้วย data tag
- action ที่อ่านข้อมูลประกาศ `provides` เช่น `task.list` ให้ `tasks`
- action ที่แก้ข้อมูลประกาศ `invalidates` เช่น `task.step.complete` ล้าง `tasks`
- แอปเก็บ cache ตาม tag เมื่อ tag ถูกล้าง ทุก widget ที่ใช้ tag นั้นโหลดใหม่ ไม่ว่าอยู่หน้าไหน ทำให้การ์ดหน้าแรก แท็บแผนของฉัน และหน้าขั้นตอนตรงกันเสมอ

### 3.3 Route ใช้ id และประกาศ params
- ปุ่มนำทางอ้าง route id เช่น `opp.detail` ซึ่งประกาศว่าต้องใช้ `id`
- validator จับได้ถ้าปุ่มที่ย้ายไปลืมส่ง param ที่ต้องใช้

### 3.4 Validator กันพังก่อนปล่อย config
`contracts/validate-config.js` ตรวจว่า:
- tab และปุ่มทุกปุ่มอ้าง route และ action ที่มีจริง
- action ทุกตัวมี method และ path ตรงกับ `openapi.yaml`
- route ที่ต้องใช้ param ได้รับ param ครบ
- widget type อยู่ใน catalog
- ตัวกรองทุกตัวเป็น query parameter ที่ `GET /v1/opportunities` รับจริง
- feature flag ที่ใช้ถูกประกาศไว้

ผลที่รันแล้ว:
| config | ผล |
|---|---|
| ตัวอย่าง (4 แท็บ, 16 routes, 25 actions) | PASS |
| ย้ายปุ่ม "ทำเสร็จแล้ว" ไปการ์ดหน้าแรก, ย้าย "แหล่งข้อมูล" ไปหน้าโอกาส, ตัดเหลือ 3 แท็บ | PASS โดยไม่แก้ API |
| ใส่ action ที่ไม่มีจริง + ลิงก์ไปรายละเอียดโดยไม่ส่ง id | FAIL พร้อมบอกจุดที่ผิด 2 จุด |

### 3.5 รุ่นของ config และการ fallback
- `schemaVersion` คือรูปแบบไฟล์ แอปไม่รู้จัก schema ใหม่ให้ใช้ config เดิม
- `configVersion` + ETag ใช้ cache และตอบ 304
- `minAppVersion` เมื่อ config ต้องใช้ widget ใหม่ แอปที่เก่ากว่าใช้ config ที่ฝังมากับแอป
- widget type ที่แอปไม่รู้จัก: ข้ามไป ไม่ล้ม
- แอปฝัง `app-config.sample.json` ไว้เป็นค่าเริ่มต้น ออฟไลน์หรือเซิร์ฟเวอร์ล่มก็ยังเปิดได้
- `featureFlags` ซ่อนหรือแสดงฟีเจอร์ เช่น `moneyMap`, `aiChat`

## 4. บริการหลังบ้าน (แยกตาม domain ไม่ตามหน้าจอ)

| บริการ | หน้าที่ | Endpoint | FR/AC |
|---|---|---|---|
| Config | ส่ง app-config, taxonomy, feature flags | `/v1/app-config`, `/v1/taxonomies` | - |
| Profile | โปรไฟล์ขั้นต่ำ, ความยินยอม, ตั้งค่า, ดูและลบข้อมูล | `/v1/me/*` | FR-01 |
| Intake (AI) | คุยถามทีละข้อ คืนคำถามถัดไปและโปรไฟล์ร่าง | `/v1/intake/chat` | FR-01 |
| Opportunity | รวมข้อมูลจากทุกแหล่งเป็นฟิลด์กลาง, ค้นหาตามระยะ หมวด คำค้น และเรียงลำดับ | `/v1/opportunities*` | FR-02, FR-03 |
| Source adapters | Greenhouse, Lever, data.go.th, OSM, Curated, Mock แปลงเป็นฟิลด์กลาง | `/v1/sources*` | FR-03 |
| Matching (AI) | จัดอันดับและให้เหตุผลจากรายการที่ server ส่งให้เท่านั้น | `/v1/matches` | FR-02, AC-02 |
| Planner | คำนวณรายได้สุทธิแบบ deterministic | `/v1/plans/options` | FR-04 |
| Tasks | บันทึก, ทำขั้นเสร็จ, เลิกทำ, ติดปัญหา, เลื่อน, AI อธิบาย | `/v1/tasks*` | FR-05, FR-06 |
| Scam rules | กฎตรวจสัญญาณหลอกลวงแบบมีเวอร์ชัน + รายงานจากผู้ใช้ | ฝังใน Opportunity, `/reports` | FR-07 |

ฟิลด์กลางของโอกาสอ้างตาม `docs/design/opportunity-sources.md` และถูกกำหนดใน `Opportunity` ของ OpenAPI

## 5. กติกาความถูกต้องที่บังคับฝั่ง server
ทำที่ server ไม่ใช่ที่หน้าจอ เพื่อให้ย้ายหน้าจอแล้วกติกายังอยู่

1. **ตัวเงินต้องมาจากต้นทาง:** `Money.basis` เป็น `official`, `listing` หรือ `none` เท่านั้น AI ไม่มีสิทธิ์เติมตัวเงิน (FR-04, AC-03)
2. **AI ใช้เฉพาะรายการที่ส่งให้:** AI ได้รับรายการ id ของผู้สมัครที่ server กรองแล้ว และต้องคืน JSON ที่มีแค่ id, ระดับความตรง และเหตุผล
   - server ทิ้ง id ที่ไม่อยู่ในรายการ และทิ้งตัวเลขเงินในข้อความ
   - ถ้า AI ล้มหรือคืนรูปแบบผิด ให้ใช้การจัดอันดับตามกฎ แล้วตั้ง `aiStatus: fallback_rules` (FR-08)
3. **หลักฐานว่าเรียก AI จริง:** ทุกครั้งที่เรียก AI บันทึก `aiInvocationId` (AC-02)
4. **ป้ายสถานะข้อมูล:** ทุกโอกาสมี `provenance.dataStatus` และ `sourceUrl` ไม่มี URL ไม่แสดง
5. **ความแม่นยำตำแหน่ง:** ปักหมุดได้เฉพาะ `location.precision = exact`
6. **ประกาศน่าสงสัย:** ซ่อนเป็นค่าเริ่มต้น และนับจำนวนที่ซ่อนส่งกลับใน `hiddenSuspicious`
7. **สถานะความคืบหน้า:** `Task.reportedBy` เป็น `user` เสมอใน Demo (FR-06)
8. **ข้อผิดพลาด:** ใช้รูปแบบเดียว `{code, message, retryable, missingFields}` code ตรงกับกรณีใน FR-08

## 6. ข้อมูลที่เก็บ
| ตาราง/คอลเลกชัน | เก็บอะไร |
|---|---|
| devices | id อุปกรณ์แบบไม่ระบุตัวตน (Demo ไม่มีระบบล็อกอิน) |
| profiles, consents, settings | ข้อมูลขั้นต่ำตาม `Profile` |
| opportunities | ฟิลด์กลาง + พิกัด (ต้องค้นตามระยะได้) |
| sources, fetch_runs | สถานะการดึงของแต่ละเจ้า เวลา จำนวน ข้อผิดพลาด |
| taxonomies | หมวด 10 หมวด, 4 กลุ่มแผนที่, กลุ่มทักษะ |
| tasks, task_events | งานและประวัติทุกการกด ใช้ทำ undo และเป็นหลักฐาน |
| checklist_templates | ขั้นตอนตามประเภทโอกาส |
| scam_rules | กฎและเวอร์ชัน |
| app_configs | config แต่ละเวอร์ชัน ใช้ย้อนกลับได้ |
| ai_invocations | id, เวลา, สถานะ (ไม่เก็บข้อมูลส่วนตัวเกินจำเป็น) |

ข้อมูล Curated ให้เก็บเป็นไฟล์ JSON ใน repo ตามฟิลด์กลาง แล้วโหลดเข้าเมื่อ deploy ไม่ต้องสร้างหน้า admin สำหรับ Demo

## 7. การดึงข้อมูลจากแหล่ง
- adapter ของแต่ละเจ้ามีหน้าที่เดียวคือ ดึง แล้วแปลงเป็นฟิลด์กลาง แล้วตรวจ (ต้องมี URL, กรองที่ตั้ง, คำนวณ precision)
- ดึงตามรอบ (เช่น ทุก 6 ชั่วโมงสำหรับ API) และเมื่อกด refresh บันทึกลง `fetch_runs`
- แหล่งที่ล้ม: ยังแสดงข้อมูลเดิมพร้อม `ageDays` และสถานะ `failed` ในหน้าแหล่งข้อมูล ไม่สร้างข้อมูลแทน
- เพิ่มเจ้าใหม่: เพิ่ม adapter กับแถวใน `sources` เท่านั้น

## 8. ตัวเลือก stack (ยังไม่ตัดสิน ให้ตัดสินใน T2.7)
| ทางเลือก | ข้อดี | ข้อเสีย/ต้องตรวจ |
|---|---|---|
| Node.js/TypeScript service เล็กๆ + SQLite หรือ Postgres | ทีมมี Node อยู่แล้ว, ทำ validator/adapter ภาษาเดียวกัน, ย้าย host ได้ง่าย | ต้องหาที่ host ฟรี |
| Supabase (Postgres + PostGIS + Edge Functions) | ค้นตามรัศมีด้วย PostGIS, มี free tier | ผูกกับผู้ให้บริการ, ต้องตรวจเงื่อนไข free tier ล่าสุด |
| AWS (Lambda + API Gateway + DynamoDB) | ตรงกับ AI-DLC/AWS, มี free tier | ตั้งค่ามากกว่า, ค้นตามระยะต้องทำเอง |
| ไม่มี backend (แอปเรียกทุกอย่างเอง) | เร็วสุด | AI key อยู่ในแอป, กติกาข้อ 5 ไปอยู่ฝั่งแอปทำให้ย้ายหน้าจอแล้วเสี่ยง, ไม่แนะนำ |

ผมแนะนำให้มี backend บางๆ เพราะต้องเก็บ AI key ไว้ฝั่ง server (ตอบ TM.13) และให้กติกาข้อ 5 อยู่ที่เดียว ส่วนเลือกเจ้าไหนให้ตัดสินตอน design ผมยังไม่ได้ตรวจราคาหรือ free tier ล่าสุดของแต่ละเจ้า

## 9. แบ่งงาน 3 คนตามสัญญา
| Unit | งาน | ใช้สัญญา |
|---|---|---|
| U1 App shell | ตัวอ่าน config, ตัวเรียก action, cache ตาม tag, widget catalog, Android build | app-config schema + action catalog |
| U2 Opportunity | adapters, ฟิลด์กลาง, ค้นหา, แผนที่และรายการ, หน้าแหล่งข้อมูล | `Opportunity`, `/v1/opportunities`, `/v1/sources` |
| U3 Profile, AI, Plan | intake chat, matching, planner, tasks, AI guardrails | `/v1/me`, `/v1/intake`, `/v1/matches`, `/v1/plans`, `/v1/tasks` |

แต่ละ unit ทำงานกับ mock server ที่สร้างจาก `openapi.yaml` ได้ก่อนที่อีก unit จะเสร็จ

## 10. สิ่งที่ยังไม่ได้ทำ
- ยังไม่มีโค้ด backend หรือแอป Flutter ที่รันได้
- ยังไม่ได้ตรวจ `openapi.yaml` ด้วยเครื่องมือ OpenAPI โดยตรง validator อ่านแค่ส่วน `paths`
- ยังไม่ได้ตรวจ sample config กับ JSON Schema ด้วยตัวตรวจมาตรฐาน
- ยังไม่ได้ตัดสิน stack, AI provider และที่เก็บข้อมูล
