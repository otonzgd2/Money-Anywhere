# Money Anywhere — เงินฉันอยู่ไหน?

แอปมือถือที่ช่วยผู้ใช้ค้นหา **เงินตามสิทธิ/เงินค้างรับ** และ **โอกาสหารายได้** พร้อมใช้ AI วิเคราะห์ทางเลือกที่เหมาะกับชีวิต วางแผนการลงมือทำ และติดตามความคืบหน้า

**สถานะ** มี Flutter Demo และ mock API สำหรับซ้อม การประเมินและหลักฐานที่ยังต้องเก็บในวันแข่งอยู่ในชุดเตรียม AI Skill Wars

## เอกสารหลัก

| เอกสาร | หน้าที่ |
|---|---|
| [ชุดเตรียม AI Skill Wars](docs/competition/skillwar/README.md) | ประเมินคะแนน สเปกสร้าง Demo และวิธีเตรียมไฟล์สำหรับ repo วันแข่ง |
| [docs/product/requirements.md](docs/product/requirements.md) | ข้อกำหนดธุรกิจที่ Owner อนุมัติ (input ของ AI-DLC) |
| [docs/plan/delivery-plan.md](docs/plan/delivery-plan.md) | แผนส่งมอบเป็นเฟสพร้อม checklist |
| [docs/plan/work-breakdown.md](docs/plan/work-breakdown.md) | รายการงานย่อย (ID, ผู้ทำ, ขึ้นกับ, หลักฐาน, สถานะ) ตัวติดตามความคืบหน้าหลัก |
| [docs/mockups/index.html](docs/mockups/index.html) | Mock หน้าจอคลิกได้ |
| [docs/backend/index.html](docs/backend/index.html) | หลังบ้านและ API แยกตามหน้า (สร้างจาก `contracts/`) |
| [contracts/](contracts/README.md) | สัญญากลาง API + config + mock server |
| [docs/guide/aidlc-commands.md](docs/guide/aidlc-commands.md) | คู่มือคำสั่ง AI-DLC ตามลำดับขั้น |
| [aidlc/spaces/default/memory/project.md](aidlc/spaces/default/memory/project.md) | กฎของโปรเจกต์ที่ agent อ่าน |
| `aidlc/` | บันทึกที่ AI-DLC สร้างเอง (ห้ามแก้มือ) |

## เริ่มงานใน Kiro

เลือก agent `aidlc` แล้วเริ่มด้วยคำขอภาษาอังกฤษที่อ้าง `docs/product/requirements.md` รายละเอียดอยู่ในคู่มือคำสั่ง

> ข้อมูลสวัสดิการ งาน และจำนวนเงินที่ยังไม่ได้ยืนยันต้องแสดงว่าเป็นข้อมูลจำลองหรือข้อมูลที่ยังไม่ยืนยัน ห้ามอ้างว่าได้รับเงินจริงหรือได้งานแน่นอน
