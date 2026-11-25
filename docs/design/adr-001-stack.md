# ADR-001: Stack หลังบ้าน ที่เก็บข้อมูล และ AI provider (TB.6)

- สถานะ: เสนอโดย AI ตามที่ Owner ขอให้ "แนะนำเลย ขอแก้ทีหลังได้ไม่กระทบ" (26 พ.ย. 2569)
- ใช้กับ: Demo เท่านั้น ตามกฎใน `project.md` (ไม่ทำ security, ข้อมูลสังเคราะห์เท่านั้น)

## หลักที่ทำให้เปลี่ยนทีหลังได้

แอป Flutter รู้จักแค่ `contracts/openapi.yaml` กับ `app-config` ไม่รู้ว่าหลังบ้านเขียนด้วยอะไร เก็บข้อมูลที่ไหน หรือใช้ AI เจ้าไหน
ทุกอย่างหลังสัญญานี้เป็น adapter ที่สลับได้ด้วย env หรือไฟล์เดียว และ `npm.cmd test` (89 checks) เป็นตัวยืนยันว่าสลับแล้วสัญญาไม่เปลี่ยน

## การตัดสินใจ

| เรื่อง | เลือกสำหรับ Demo | เปลี่ยนทีหลังเป็น | ต้องแก้อะไรถ้าเปลี่ยน |
|---|---|---|---|
| หลังบ้าน | Node.js ต่อยอดจาก `contracts/mock-server.js` ที่ผ่าน contract test ครบ 47 operations แล้ว | ภาษาอื่นได้ (Go, Python, Dart) | เขียนใหม่ให้ผ่าน `test-contract.js` ชุดเดิม แอปไม่ต้องแก้ |
| ที่เก็บข้อมูล | port `store` (อ่าน/เขียนเอกสารต่ออุปกรณ์) + adapter ไฟล์ JSON หรือ SQLite บนเครื่องที่รัน server | Postgres (Supabase หรือ Neon) เก็บเป็น JSONB ต่ออุปกรณ์ | adapter ไฟล์เดียว ตอนนี้ข้อมูลอยู่ใน `Map` ในหน่วยความจำ (`mock-server.js`) ดับแล้วหาย |
| AI | adapter แบบ OpenAI-compatible ที่มีอยู่แล้ว (`adapters/ai.js`, `adapters/agent.js`) ตั้งค่าด้วย `AI_BASE_URL`, `AI_API_KEY`, `AI_MODEL` เริ่มที่ Gemini API free tier | Typhoon, OpenAI หรือเจ้าอื่นที่มี endpoint `/chat/completions` | แก้ 3 ค่าใน `.env` ไม่แก้โค้ด ถ้าไม่มี key หรือ provider ล่ม ระบบใช้กฎแทน (มี test แล้ว) |
| ที่รัน server | โน้ตบุ๊กที่ใช้ demo รัน `npm.cmd run mock` แล้วเปิด tunnel ให้มือถือเรียกได้ | Render หรือ host อื่น | เปลี่ยน `API_BASE_URL` ใน build ของแอป |

## เหตุผลและข้อจำกัดที่ตรวจแล้ว

- **ไม่เขียนหลังบ้านใหม่**: mock server ทำครบทุก endpoint และมี test แล้ว การเปลี่ยนเป็น TypeScript หรือ framework อื่นตอนนี้ไม่เพิ่ม output ให้ Demo
- **Gemini free tier**: ไม่ต้องผูกบัตร มี endpoint แบบ OpenAI-compatible แต่โควตาต่อวันต่ำและเปลี่ยนบ่อย ดูตัวเลขจริงได้ใน Google AI Studio ของโปรเจกต์เท่านั้น ([Google AI rate limits](https://ai.google.dev/gemini-api/docs/rate-limits), [บทสรุป free tier ต.ค. 2569](https://dev.to/hassann/gemini-api-free-tier-in-2026-limits-models-and-when-you-get-billed-4081)) นอก EEA/UK ข้อมูลที่ส่งใน free tier อาจถูกใช้ปรับปรุงผลิตภัณฑ์ ([freeapihub](https://freeapihub.com/blog/gemini-api-free-tier-python)) จึงส่งได้เฉพาะ persona สังเคราะห์ ซึ่งตรงกับกฎเดิมอยู่แล้ว
- **Typhoon (ทางเลือกภาษาไทย)**: มี free tier แบบจำกัดอัตรา เป็น research showcase ไม่มี SLA และจำกัด 8,192 token ต่อคำขอ ([Typhoon docs](https://docs.opentyphoon.ai/en/), [API reference](https://docs.opentyphoon.ai/en/api-reference/)) ยังไม่ได้ตรวจว่ารองรับ tool calling ที่ assistant ใช้หรือไม่ ต้องลองใน TB.13 ก่อนสลับ
- **Supabase free**: DB 500 MB, 2 โปรเจกต์, หยุดอัตโนมัติถ้าไม่มีการใช้งาน 1 สัปดาห์ ([Supabase pricing](https://supabase.com/pricing)) ใช้ได้ถ้าเปิดใช้ก่อนวัน demo
- **Render free**: หลับหลังไม่มีคนเรียก 15 นาที ปลุกใช้ราว 1 นาที, Postgres ฟรีหมดอายุใน 30 วัน, ไม่มี disk ถาวร ([Render Node.js hosting](https://render.com/hosting/nodejs)) ไฟล์ SQLite บน Render จะหายเมื่อ restart จึงเป็นแผนสำรอง ไม่ใช่แผนหลัก
- **Tunnel จากโน้ตบุ๊ก**: ข้อมูลอยู่บนเครื่องเดียวกับ server ไม่หลับ ไม่หมดอายุ ยังไม่ได้ทดลองในโปรเจกต์นี้ ทดลองใน TB.16

## ทางเลือกที่ไม่เลือก

- Firebase/Firestore เป็นหลังบ้านตรงจากแอป: แอปต้องรู้โครงข้อมูลและกฎเงินเอง ขัดกับหลัก "หลังบ้านกำหนดเมนูและ action" และย้ายออกยาก
- Supabase เป็นหลังบ้านตรงจากแอป: เหตุผลเดียวกัน และหยุดเมื่อไม่มีการใช้งาน
- ผูกกับ SDK ของ AI เจ้าเดียว: เปลี่ยนเจ้าแล้วต้องแก้โค้ด ต่างจาก OpenAI-compatible ที่แก้แค่ env

## งานต่อจากนี้

- TB.16: เพิ่ม port `store` + adapter ไฟล์/SQLite, ทดลอง tunnel กับมือถือจริง
- TB.13: ใส่ key Gemini ใน `.env` (ไม่ commit) แล้วรัน `LIVE=1` ทดสอบ assistant กับ provider จริง
