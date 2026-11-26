---
inclusion: fileMatch
fileMatchPattern: ["contracts/adapters/**", "contracts/mock-server.js", "contracts/fixtures/opportunities*.json", "docs/entities/database-spec/job_*.md", "docs/backend/job-*.md"]
---
# ข้อมูลงาน (Job data): กฎที่ AI ต้องทำตามเมื่อพัฒนาส่วนดึงและเก็บข้อมูลงาน
สเป็คนี้ล็อกการทำงานของ AI ในงานดึง เก็บ และอัปเดตข้อมูลงานในประเทศไทย อ่านไฟล์ด้านล่างก่อนแก้โค้ดหรือข้อมูลที่เกี่ยวข้อง ถ้ากฎขัดกันให้ยึดไฟล์ที่เข้มกว่าและถามเจ้าของโครงการ

## ไฟล์สเป็ค (อ่านตามงานที่ทำ)
- ขอบเขตและสิ่งที่ห้าม: `docs/backend/job-data-scope-lock.md` (อ่านก่อนเสมอ)
- แหล่งข้อมูลที่ใช้ได้และห้ามใช้: `docs/backend/job-source-policy.md`
- ขั้นตอน ingest แบบ incremental: `docs/backend/job-ingest-procedure.md`
- กฎความถูกต้องของข้อมูล: `docs/backend/job-data-quality-rules.md`
- เกณฑ์ผ่านและคำสั่งทดสอบ: `docs/backend/job-acceptance-tests.md`
- สเป็คตาราง: `docs/entities/database-spec/job_source.md`, `job_posting.md`, `job_report.md`

## กฎที่ไม่ยืดหยุ่น
- แก้ได้เฉพาะ 3 ตารางงาน (`job_source`, `job_posting`, `job_report`) ห้ามแตะข้อมูลผู้ใช้
- สเป็คตารางยังเป็น `draft-spec` และ `write_allowed: false` ห้ามสร้างหรือเปลี่ยน schema ของฐานข้อมูลจริงจนกว่าเจ้าของโครงการอนุมัติ
- ห้ามดึงข้อมูลจากแหล่งที่ไม่ได้ระบุว่าใช้ได้ใน `job-source-policy.md` (ห้าม scraper ของบุคคลที่สามและ API ภายในของเว็บงาน)
- ห้ามแต่งข้อมูลงานหรือตัวเลขค่าจ้าง ข้อมูลจำลองต้องติดป้าย DEMO / MOCK เสมอ
- ห้ามอ่านหรือพิมพ์ค่าใน `.env`
- หัวข้อที่ระบุว่ายังไม่ตัดสินในสเป็ค (เช่น ฟิลด์ใน `content_hash`) ให้ถามเจ้าของโครงการ ห้ามเลือกเอง
- ก่อนรายงานว่าเสร็จ ต้องรันการทดสอบตาม `job-acceptance-tests.md` และรายงานผลจริง
- ตอบเจ้าของโครงการเป็นภาษาไทย โค้ดและชื่อฟิลด์เป็นภาษาอังกฤษ
