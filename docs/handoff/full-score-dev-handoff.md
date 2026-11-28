# Handoff ให้ dev ทำชุดแก้เต็ม 100 คะแนน

ทำชุด S0–S4 ตาม [สเปกปิดช่องว่าง 100 คะแนน](../competition/skillwar/full-score-spec.md) ใน `otonzgd2/Money-Anywhere` เริ่มจาก `main` ที่ `7e56bc5` สเปกเป็นตัวกำหนดว่าต้องเกิดอะไรและตรวจรับอย่างไร ไฟล์นี้บอกว่าตอนนี้ทำถึงไหน จุดแก้อยู่ตรงไหนในโค้ด และกับดักที่เจอระหว่างสำรวจ

## สถานะตอนส่งต่อ (28 พ.ย. 2569)

| ส่วน | สถานะ |
| --- | --- |
| D3 แชตค้นงานตามเขต (ส่วนหนึ่งของ S1) | **เสร็จแล้ว** ใน `7e56bc5` มีเทสต์ D3-01..03 |
| S0 ข้อ 1–2 (path DB, ลงทะเบียน `bkk_curated`) | ยังไม่ทำ ทำได้เลย |
| S0 ข้อ 3–4 (CSV ประกาศจริง, ทะเบียนแหล่ง) | **ทีมข้อมูลรับไป** ไม่ต้องรอ ทำ S1–S4 ด้วยข้อมูล mock ไปก่อน |
| S1 ส่วนที่เหลือ รวม soft guard | ยังไม่ทำ |
| S2, S3, S4 | ยังไม่ทำ |

Baseline ที่ `7e56bc5`: `npm --prefix contracts test` ผ่าน 248/248, `node --test contracts/test-thang-rot-guard.js` ผ่าน 135/135, `node contracts/test-thang-rot-manual.js` ผ่าน 33/33 ส่วน `flutter test` กับ `flutter analyze` ยังไม่ได้รันตั้งแต่ commit อ้างอิง `8efb63b` ให้รันก่อนแก้และจดผลไว้

## ผลตัดสินที่ต้องยึด

- **D2 guard เป็น soft** เจ้าของงานแจ้งว่า guard มีไว้เพื่อลดค่า LLM เท่านั้น Demo ต้องไหลลื่น กฎไหนกั้นผู้ใช้จนสะดุดให้เอาออก ข้อเดียวที่คงไว้คือปิดบัง OTP, เลขบัญชี และเลขบัตรเป็น `[ซ่อน]` ก่อนส่งให้โมเดล โดยไม่หยุดบทสนทนา ถ้าข้อนี้ทำให้ flow สะดุดให้แจ้งเจ้าของงาน รายละเอียดอยู่ในสเปกหัวข้อ D2 และ "Soft guard" ใน S1
- **D3 แก้แล้ว** อย่าย้อนกลับไปใช้รัศมีอย่างเดียวในแชต
- **D1 ไม่ใช่งาน dev** เตรียมโค้ดให้รับแหล่ง `curated` ได้ แล้วรอไฟล์จากทีมข้อมูล

## ลำดับทำงาน

ทำทีละชุด ชุดละหนึ่ง commit (หรือ commit เทสต์ที่ตกก่อน แล้วตามด้วย fix) รันเทสต์ทั้งสามชุดก่อนขึ้นชุดถัดไป

1. **S1 ส่วนที่เหลือ** ทำ soft guard ก่อน เพราะเปลี่ยนว่าข้อความไหนถึงโมเดล แล้วตามด้วยบังคับ `group=job`, ทักษะ, ช่วงเวลา และผลว่าง
2. **S0 ข้อ 1–2** งานเล็ก ทำแทรกตอนไหนก็ได้
3. **S2** สัญญา API และ logic ฝั่ง backend
4. **S3** Flutter ต้องได้ S2 ก่อน
5. **S4** ทางกู้ ทำต่อจาก S3 ในไฟล์เดียวกัน

## จุดเริ่มแก้ในโค้ด

ตำแหน่งบรรทัดอ้างอิง `7e56bc5` ให้ค้นด้วยชื่อฟังก์ชันหรือข้อความ เพราะบรรทัดจะเลื่อนเมื่อแก้

### S1 soft guard และตัวกรอง

| จุด | สิ่งที่พบและวิธีต่อ |
| --- | --- |
| `contracts/adapters/guard.js` `check()` | คืน kind `injection`, `sensitive`, `guarantee`, `scam`, `off_topic`, `safe_advice`, `answer`, `explain`, `skip`, `in_scope`, `unclear` เพิ่ม `mask(text)` ที่นี่ ใช้ `credentialName`/`credentialValue` ที่มีอยู่เป็นจุดตั้งต้น |
| `contracts/mock-server.js` route `POST /v1/ai/conversations/{id}/messages` ส่วน `const hardRefusal = [...]` | จุดที่ปฏิเสธทันทีสำหรับ `sensitive`, `injection`, `guarantee` และ `off_topic`/`scam` แบบมีเงื่อนไข โหมด soft ให้ส่งเข้า `runAssistant` แทน |
| route เดียวกัน บรรทัดท้ายสุด `return turn(c.expect.question, 'unclear')` | ข้อความที่จับเจตนาไม่ได้ตกมาที่นี่และไม่ถึงโมเดล โหมด soft ให้ส่งเข้า `runAssistant` |
| `runAssistant` ตัวแปร `narrowed` | แทนข้อความผู้ใช้ด้วยข้อความคงที่ในเส้นค้นงาน โหมด soft ให้ส่งข้อความที่ปิดบังแล้วพร้อมบรรทัดตัวกรอง ระวังเงื่อนไขท้ายฟังก์ชัน `narrowed !== 'หางานใกล้บ้าน'` ที่ตัดสินว่าจะกลับไป `incomeIdeas()` เมื่อ fallback ต้องเปลี่ยนให้ไม่อิงข้อความคงที่ |
| `agentTools().search_opportunities.run` | เพิ่ม `jobArea` แล้วใน D3 ส่วน `group` ยังอ่านจาก `a.group` ตรงๆ ถ้าโมเดลส่ง `งาน` ผลจะว่าง ในเส้น `income` ให้บังคับ `job` ส่วนนอกเส้นนี้ให้ normalize ค่าไทย |
| `districtsIn()`, `homeDistrict()`, `askJobDistrict()` | มาจาก D3 ใช้ต่อได้เลย การจับทักษะและช่วงเวลาให้เขียนแบบเดียวกัน และเก็บค่าไว้ข้าง `c.topic.jobArea` |
| เทสต์ guard/manual เดิม | ทุกชุดเดิมสมมติพฤติกรรม strict ให้ส่ง `guardMode: 'strict'` ที่ `createServer` ของสองไฟล์นี้ (`openServer` ใน guard และ server ตั้งต้นใน manual) แล้วเขียน SOFT-01..06 แยก |

### S0

| จุด | สิ่งที่พบและวิธีต่อ |
| --- | --- |
| `contracts/run-bangkok-demo.js` | ชี้ `docs/entities/database-script/catalogue.db` ซึ่งไม่มีอยู่จริง ไฟล์จริงอยู่ที่ `.../database-script/demo/catalogue.db` (5,100 แถว เป็น mock ทั้งหมด) |
| `contracts/mock-server.js` ลูป `for (const feed of fileFeeds)` | file feed ที่ `mock: false` ต้องมี provider ลงทะเบียนใน `job_source` ไว้ก่อน ไม่งั้น server จะ throw ให้ลงทะเบียน `bkk_curated` ด้วย `data_status = 'curated'` ผ่าน seed หรือ migration |
| `contracts/fixtures/job-file-feeds.demo.json` และ `job-feed.demo.csv` | ใช้เป็นแบบของ config และคอลัมน์ CSV |

### S2

| จุด | สิ่งที่พบและวิธีต่อ |
| --- | --- |
| `runAssistant` ตัวแปร `returnedJobs` | ตั้งต้นด้วย `excludedJobs` จึงรวม IDs ของเทิร์นก่อน ให้แยก `turnIds` ที่นับเฉพาะเทิร์นนี้ |
| `details()` | ตอนนี้รับ `create_task` ที่มี `opportunityId` อะไรก็ได้ที่โมเดลเสนอ ไม่ตรวจว่าอยู่ในผลค้น ให้กรองที่นี่และสร้าง `opportunityLinks` ที่นี่ |
| `contracts/adapters/agent.js` `rulesAgent` สาขา `/งาน/` | เสนอบันทึกรายการแรกเอง และเขียนรายการในข้อความโดยไม่มีป้าย mock ต้องผ่านกติกาเดียวกับ provider |
| `agent.js` ต่อจาก `guardMoney`/`guardReferences` | วาง `guardPromises` |
| route `POST /v1/ai/conversations/{id}/actions/{actionId}` | confirm ซ้ำคืนผลเดิมจาก `c.decisions` อยู่แล้ว แต่ไม่ตรวจว่าประกาศปิดหรือหมดอายุ ส่วน `svc.createTask` ก็ไม่ตรวจ ให้ตรวจใน route นี้ เพื่อไม่เปลี่ยน `POST /v1/tasks` |
| `contracts/openapi.yaml` `AgentTurn` | เพิ่ม `opportunityLinks` และ `jobSearch` แบบ optional ใช้ `Money` component ที่มีอยู่ อัปเดต `api-examples.json` ด้วย `capture-api-examples.cjs` |

### S3 และ S4

| จุด | สิ่งที่พบและวิธีต่อ |
| --- | --- |
| `app/lib/chat.dart` `_send` | อ่าน `planLinks` และ `pendingActions` จาก response ให้อ่าน `opportunityLinks` ตรงนี้แบบ optional |
| `_bubble` | วาด `planLinks` และ action ทีละรายการ ให้วางแถวผลค้นงานที่นี่ และซ่อน action ที่ผูกกับแถวแล้วจากรายการ action ทั่วไป |
| `_decide` | เมื่อเกิด error แสดงแค่ toast และไม่จำว่ากำลังรอผล ต้องปรับตาม S4 ข้อ 1–2 |
| `app/lib/common.dart` `openExternal` | มี `askAfterReturn` ให้ส่ง `false` สำหรับลิงก์ต้นทางจากแชต |
| `_who()` | แยกป้าย `ok`, `fallback_rules` และ `guarded` อยู่แล้ว |
| Demo chat | `home_tab.dart` เปิด `ChatScreen(app: demoApp, ...)` จึงเปิด `TaskScreen` ด้วย `demoApp` และใช้ device scope ของ demo ถูกต้องอยู่แล้ว ให้ตรวจซ้ำหลังเพิ่มปุ่มในแถว |

## ตัวช่วยที่มีอยู่แล้ว

- `openCatalogueChat()` ท้าย `contracts/test-thang-rot-guard.js` เปิด server กับสำเนา `demo/catalogue.db` และ stub agent ที่เรียก `search_opportunities` ใช้ต่อได้กับเคส JOB, LINK และ SOFT ที่ต้องการข้อมูลมีเขต
- ใน `test-thang-rot-guard.js` server `observed` นับ payload ที่ส่งโมเดลไว้ใน `agentCalls` ใช้ตรวจว่าข้อความดิบหรือค่าอ่อนไหวไม่หลุดไปถึงโมเดล
- ฟิกซ์เจอร์ใน memory (`opportunities.json`) ไม่มีชื่อเขตเลยและเป็นพิกัดจริงรอบจุดกลาง เคสที่ต้องการเขตให้ใช้ catalogue

## นอกขอบเขต

- `jobOptions` ซึ่งแผนรายได้ตามเป้าใช้เลือกงาน ไม่ดูพื้นที่เลย เป็นปัญหาแบบเดียวกับ D3 แต่ไม่ได้อ้างว่า "ใกล้บ้าน" และถ้าแก้จะกระทบตัวเลขในเทสต์แผนรายได้ ให้เปิดเป็นงานแยกถ้าจะทำ
- ไม่เปลี่ยน API paths, store layout v2, enum ของ `aiStatus` และหน้าจอหลัก

## ตรวจก่อนส่งแต่ละชุด

```powershell
npm.cmd --prefix contracts test
node --test contracts/test-thang-rot-guard.js
node contracts/test-thang-rot-manual.js
```

```powershell
cd app; flutter analyze; flutter test
```

- เคสเดิมต้องผ่านทั้งหมด จำนวนเคสเพิ่มตามเคสใหม่ในสเปก (JOB, SOFT, LINK, SCHEMA, UI)
- ทวนเส้นเดิมด้วยมือ: ค้นโอกาสจากแท็บ, เช็กสิทธิ, วางแผนรายได้, เปิดแผนเก่า, ยกเลิก action, โหมดไม่มี AI consent และ Demo persona chat
- ตรวจความเข้ากันได้สองทาง: client ใหม่กับ server เก่า และ client เก่ากับ server ใหม่
- S3 และ S4 ต้องตรวจบน Android จริงตามคู่มือ [event-runbook](../competition/skillwar/event-runbook.md) (`adb reverse tcp:8080 tcp:8080`) ถ้ายังไม่มีอุปกรณ์ให้ระบุในรายงานว่าตรวจเฉพาะ widget test

## รายงานกลับ

ต่อชุดให้ส่ง SHA, ผลเทสต์ทั้งสามชุดพร้อมจำนวนเคส, ผล `flutter analyze`/`flutter test` (ถ้าแตะ Flutter), รหัสเคสในสเปกที่ผ่าน, เคสที่ตรวจไม่ได้พร้อมเหตุผล และจุดที่ต้องเบี่ยงจากสเปก เมื่อทีมข้อมูลส่ง CSV แล้ว ให้รันเกณฑ์ผ่านของ S0 กับข้อมูลจริงและติ๊กเช็คลิสต์ D1 ในสเปก
