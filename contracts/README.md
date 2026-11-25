# contracts/ : สัญญากลางของทีม

ที่เดียวที่ทั้ง 3 คนใช้ร่วมกัน แก้ไฟล์ที่นี่แล้วรัน `npm run check` ทุกครั้ง

| ไฟล์ | หน้าที่ | แก้เมื่อ |
|---|---|---|
| `openapi.yaml` | API ทุกตัว (v0.3: 47 operations, 14 บริการ) | เพิ่ม/แก้ API หรือฟิลด์ |
| `integrations.json` | ช่องทางเชื่อมต่อภายนอก (port) และ adapter ของแต่ละตัว | เพิ่ม/เปลี่ยนผู้ให้บริการ |
| `adapters/` | AI, ผู้ช่วย AI (agent), กฎเงิน (money), เชื่อมรัฐ (gov จำลอง), แหล่งโอกาส, หาพิกัด, แจ้งเตือน | เขียน adapter ใหม่ตาม interface เดิม |
| `app-config.sample.json` | แท็บ หน้า ปุ่ม ตัวกรอง และ action catalog | ย้ายเมนู ย้ายปุ่ม เพิ่มหน้า |
| `app-config.schema.json` | รูปแบบของ config และรายชื่อ widget | เพิ่มชนิด widget |
| `fixtures/reference.json` | หมวด ทักษะ ขั้นตอน กฎหลอกลวง แหล่งข้อมูล แผนรายได้ตัวอย่าง | เพิ่มตัวเลือก |
| `fixtures/opportunities.json` | ข้อมูลตัวอย่าง DEMO / MOCK | เพิ่มข้อมูลทดสอบ |
| `mock-server.js` | API จำลองครบทุก operation (ดึง Greenhouse/Lever จริงได้) | เปลี่ยนพฤติกรรม mock |
| `validate-config.js` | ตรวจว่าปุ่มและเมนูอ้างของที่มีจริง | - |
| `validate-contracts.js` | ตรวจ OpenAPI และ schema ด้วยเครื่องมือมาตรฐาน | - |
| `test-contract.js` | เรียกทุก API แล้วตรวจกับ schema, มาตรฐานกลาง และกติกา รวมทดสอบ AI กับ LLM จำลอง | เพิ่มกติกา |
| `build-docs.js` | สร้าง `docs/backend/index.html` | - |

## คำสั่ง (รันในโฟลเดอร์นี้)
```
npm install       # ครั้งแรก
npm run check     # ตรวจทั้งหมดแล้วสร้างเอกสาร HTML ใหม่
npm run mock      # API จำลองที่ http://localhost:8080 เอกสารที่ /docs
```
PowerShell ที่ปิดการรันสคริปต์ ให้ใช้ `npm.cmd` แทน `npm`
ตัวแปรของ mock (ตั้งก่อนรัน เช่น `$env:LIVE=1` ใน PowerShell):
- `LIVE=1` ดึง Greenhouse/Lever จริงตอนเปิด
- `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL` ใช้ผู้ให้บริการ AI แบบ OpenAI-compatible (ไม่ตั้งใช้กฎ)
- `GOV_CONNECTED=1` เปิดโหมดเชื่อมรัฐ (adapter จำลอง)
- `DEMO_MODE=0` ปิด `/v1/demo`
- `INTEGRATION_KEY` คีย์ของ `/v1/integrations`
- `GIT_COMMIT` commit ที่ `/v1/health` รายงาน

`docs/backend/index.html` สร้างอัตโนมัติ ห้ามแก้ตรง
