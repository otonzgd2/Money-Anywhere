# Work Breakdown (ตัวติดตามความคืบหน้าหลัก)

## วิธีเก็บแผน (แหล่งความจริงแหล่งเดียวต่อเรื่อง)

| เรื่อง | เก็บที่ | ใครแก้ |
|---|---|---|
| ข้อกำหนดธุรกิจ | `docs/product/requirements.md` | Owner เท่านั้น |
| แผนเฟสและ checklist ภาพรวม | `docs/plan/delivery-plan.md` | ทีม |
| งานย่อยและสถานะ | ไฟล์นี้ (`docs/plan/work-breakdown.md`) | ทีม อัปเดตเมื่อมีหลักฐาน |
| กฎที่ agent ต้องทำตาม | `aidlc/spaces/default/memory/project.md` | ทีม ผ่านกระบวนการของ AI-DLC |
| ผลของแต่ละ stage (intent, state, stories, design, Bolt) | `aidlc/spaces/default/intents/...` | AI-DLC สร้างเอง ห้ามแก้มือ |
| ประวัติและหลักฐาน | git commit และ hash | อัตโนมัติ |

กติกา:
- สถานะมี 4 ค่า: `TODO`, `DOING`, `DONE`, `BLOCKED`
- `DONE` ต้องมีหลักฐาน (ไฟล์, ผลรัน, commit hash) ในคอลัมน์ Evidence
- เมื่อ AI-DLC สร้างแผน Bolt จริง (stage delivery-planning) ให้แทนงานเฟส 4 ในไฟล์นี้ด้วย Bolt นั้น ห้ามให้ 2 แผนขัดกัน
- เจ้าของงาน: `P1`, `P2`, `P3` = สมาชิกทีม 3 คน (กำหนดชื่อจริงเมื่อ Units Generation เสร็จ), `AI` = Kiro, `OWNER` = ผู้อนุมัติ
- Commit และ push ทุกครั้งที่เปลี่ยนสถานะงานสำคัญ

## เฟส 0: วางเครื่องมือ

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T0.1 | Git repo และ push ขึ้น GitHub | AI | - | commit `2d171a8` | DONE |
| T0.2 | กฎโปรเจกต์ Demo ใน `project.md` | AI | - | `project.md` | DONE |
| T0.3 | เพิ่ม `requirements.md` และ `README.md` | AI | - | ไฟล์ใน repo | DONE |
| T0.4 | `.gitignore` กัน secret/build และ `.env.example` | AI | - | ไฟล์ใน repo | DONE |
| T0.5 | ติดตั้ง Android Studio (JDK + SDK Manager) | P1 | - | `java -version` ผ่าน | TODO |
| T0.6 | ติดตั้ง Android SDK และ platform-tools | P1 | T0.5 | `adb version` ผ่าน | TODO |
| T0.7 | เตรียมอุปกรณ์ทดสอบ (emulator หรือมือถือ USB debugging) | P1 | T0.6 | `adb devices` เห็นเครื่อง | TODO |
| T0.8 | ตั้ง AI provider และ API key ใน `.env` (ไม่ commit) | OWNER | - | เรียก API ทดสอบได้ | TODO |
| T0.9 | ตรวจ Kiro: agent `aidlc` และ `/aidlc --doctor` | AI | - | ผล doctor ไม่มี error | TODO |
| T0.10 | commit และ push เฟส 0 | AI | T0.1-T0.4 | commit hash | TODO |
| T0.11 | บันทึกการตัดสินใจใช้ Flutter ใน `project.md` | AI | - | `project.md` (Tech Stack, Decided) | DONE |
| T0.12 | ติดตั้ง Flutter SDK ที่ `C:\src\flutter` และเพิ่มใน PATH | AI | - | `flutter --version` ผ่าน | DOING |
| T0.13 | `flutter doctor` ไม่มีข้อผิดพลาดเรื่อง Android toolchain | P1 | T0.5, T0.6, T0.12 | ผล doctor | TODO |

ผ่านเฟส 0 เมื่อ: T0.5-T0.9 DONE (hello-world APK ติดตั้งได้ทำใน T4.1 หลังเลือก framework)

## เฟส 1: Ideation + Mock คร่าวๆ

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T1.1 | `/aidlc compose` เสนอแผน ตรวจว่ามี rough/refined mockups | AI | T0.9 | แผน EXECUTE/SKIP | TODO |
| T1.2 | Approve แผน (Plan Approval) | OWNER | T1.1 | บันทึกอนุมัติ | TODO |
| T1.3 | Intent Capture, Scope Definition | AI | T1.2 | artifact ใน `aidlc/` | TODO |
| T1.4 | Rough Mockups ครบ 8 หน้าตามรายการใน delivery-plan | AI | T1.3 | artifact ใน `aidlc/` | TODO |
| T1.5 | Owner ตรวจภาพร่าง (แก้ได้ 1 รอบ) | OWNER | T1.4 | บันทึกอนุมัติ | TODO |

## เฟส 1M: Money Map และ UX (ข้อเสนอ รอ Owner ตัดสินว่าอยู่ใน MVP หรือไม่)

อ้างอิง: handoff Money Map (2026-11-25) และ mock `docs/mockups/index.html` ห้ามแก้ requirements.md เองโดยไม่ผ่าน Owner

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| TM.1 | Owner ตัดสิน: Money Map เป็นส่วนของ MVP หรือ vertical slice แยก และยอมใช้ข้อมูลคัดมือแทนข้อมูลสดหรือไม่ | OWNER | - | บันทึกการตัดสินใจ | TODO |
| TM.2 | Mock หน้าแผนที่: หมุด, รัศมี, ลากเลื่อน, ค้นหาในพื้นที่นี้, ซูม, กลับตำแหน่งฉัน | AI | - | `docs/mockups/index.html` | DONE |
| TM.3 | Mock การแสดงเงิน 3 ระดับ (ทางการ / ช่วงตามประกาศ / ไม่ระบุ + AI ประมาณแยกกล่อง) | AI | - | `docs/mockups/index.html` | DONE |
| TM.4 | Mock หน้าแรกผู้ใช้เดิม, pop up อัปเดตสถานะ, เลิกทำ, ถามตอนกลับจากเว็บต้นทาง, ตัวอักษรใหญ่ | AI | - | `docs/mockups/index.html` | DONE |
| TM.5 | Mock ผู้ใช้ตัวอย่าง 3 คน (A/B/C) สำหรับ AC-01 | AI | - | `docs/mockups/index.html` | DONE |
| TM.6 | Mock ขอตำแหน่ง, ปฏิเสธ/GPS ล้ม (เลือกจุดเอง), หน้ายินยอมข้อมูล | AI | - | `docs/mockups/index.html` | DONE |
| TM.7 | Mock สถานะแผนที่: ไม่พบผล, ออฟไลน์, ข้อมูลเก่า, โหลดล้มเหลว | AI | - | `docs/mockups/index.html` | DONE |
| TM.8 | Mock ความสดใหม่ของข้อมูลบนการ์ดและหมุด, หมุดน่าสงสัย (FR-07) | AI | - | `docs/mockups/index.html` | DONE |
| TM.9 | Owner ตรวจ mock และสั่งแก้ได้ 1 รอบ | OWNER | TM.2-TM.8 | บันทึกอนุมัติ | TODO |
| TM.10 | หน้าโปรไฟล์/ตั้งค่า (แก้ ลบข้อมูล), เรียงลำดับ/ค้นหาด้วยคำ, รายการโปรด, ปุ่ม "ผลนี้ไม่ตรง" | AI | TM.9 | mock | TODO |
| TM.11 | สำรวจแหล่งข้อมูลทีละแหล่ง (Greenhouse, Lever, ที่ตั้งโรงเรียนฝึกอาชีพ กทม., OSM) พร้อมตัวอย่าง response และสิทธิ์ใช้ | AI | - | ตารางหลักฐาน | DOING |
| TM.12 | ชุดข้อมูลคัดมืออย่างน้อย 30 รายการ มี URL, วันที่ตรวจ, พิกัดจากที่อยู่จริง | P1-P3 | TM.1, TM.11 | ไฟล์ข้อมูล | TODO |
| TM.13 | ตัดสินวิธีเก็บ AI key (ในแอป vs พร็อกซีบางๆ) | OWNER+AI | T0.8 | ADR | TODO |
| TM.14 | Mock ทักษะเป็น dropdown ค้นหาได้ มีหัวข้อหมวด และเพิ่มทักษะเองได้ | AI | - | `docs/mockups/index.html` | DONE |
| TM.15 | Mock แผนรายได้แสดงทุกทางเลือก เรียงได้ 3 แบบ เทียบได้สูงสุด 3 และแยกกลุ่มที่ไม่ทราบเงิน | AI | - | `docs/mockups/index.html` | DONE |
| TM.16 | ร่างฟิลด์กลางและการแมปของแต่ละเจ้า | AI | TM.11 | `docs/design/opportunity-sources.md` | DONE |
| TM.18 | ลดเมนูหลัก: 4 แท็บ, หน้าแรกเหลือการกระทำหลักเดียว, หน้าโอกาสรวมรายการ/แผนที่ พร้อมตัวกรองชุดเดียว, แท็บ ฉัน (ตั้งค่า/ข้อมูล/ช่วยเหลือ) | AI | TM.9 | `docs/design/navigation.md`, smoke test 23/23 PASS (`docs/mockups/smoke-test.js`) | DONE |
| TM.17 | Mock ดึงสดจาก Greenhouse และ Lever ผ่านฟิลด์กลาง พร้อมหน้าแหล่งข้อมูลและลิงก์ต้นทาง | AI | TM.16 | `docs/mockups/index.html` (ยังไม่ยืนยันว่าเบราว์เซอร์ยอม CORS) | DOING |

หลักฐานจาก TM.11 ที่ได้แล้ว (เรียกจริง): Greenhouse (Agoda) ตอบ JSON 335 ตำแหน่ง ที่ตั้งเป็นข้อความ ไม่มีพิกัดและเงินเดือน; Lever (Coda) ตอบ JSON ที่ตั้งเป็นข้อความเช่นกัน; ชุดข้อมูลโรงเรียนฝึกอาชีพมีไฟล์ JSON แต่ยังไม่ได้ตรวจเนื้อหา; Overpass ตอบ 502 หนึ่งครั้ง ยังไม่ยืนยัน

## เฟส 1B: หลังบ้านแบบ dynamic (ข้อเสนอ R&D)

อ้างอิง: `docs/design/backend.md`, สัญญาใน `contracts/`

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| TB.1 | วิเคราะห์และออกแบบหลังบ้านแยก resource / action catalog / layout config | AI | TM.18 | `docs/design/backend.md` | DONE |
| TB.2 | OpenAPI ร่าง 25 operations ตาม resource | AI | TB.1 | `contracts/openapi.yaml` | DONE |
| TB.3 | JSON Schema ของ app-config + ตัวอย่างที่ตรงกับ mock (4 แท็บ, 16 routes, 25 actions, 5 filters) | AI | TB.1 | `contracts/app-config.*.json` | DONE |
| TB.4 | Validator ตรวจการอ้างอิงของ config กับ OpenAPI | AI | TB.2, TB.3 | `node contracts/validate-config.js` PASS, config ที่ย้ายปุ่ม PASS, config ที่ผิดจับได้ 2 จุด | DONE |
| TB.5 | ตรวจ OpenAPI และ schema ด้วยเครื่องมือมาตรฐาน | AI | TB.2, TB.3 | `npm run validate`: OpenAPI 3.0.3 valid, config ตรง schema | DONE |
| TB.8 | เอกสาร HTML หลังบ้าน/API แยกตามหน้า สร้างจากสัญญา | AI | TB.2, TB.3 | `docs/backend/index.html` (`npm run docs`) | DONE |
| TB.9 | Contract test เรียกทุก API ตรวจ schema และกติกา | AI | TB.7 | `npm test`: 100/100 PASS, 25/25 operations | DONE |
| TB.6 | ตัดสิน stack หลังบ้าน, AI provider, ที่เก็บข้อมูล | OWNER+AI | TB.1 | ADR (รวมกับ T2.7, TM.13) | TODO |
| TB.7 | Mock server ครบทุก operation ให้ U1/U2/U3 ทำงานขนานได้ | AI | TB.2 | `npm run mock`; LIVE=1 ดึง Greenhouse 220 และ Lever 6 ตำแหน่งในกรุงเทพฯ (ทดสอบจริงแล้ว) | DONE |

## เฟส 2: Inception

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T2.1 | Practices Discovery | AI | T1.5 | artifact | TODO |
| T2.2 | Requirements Analysis (FR-01..08) | AI | T2.1 | artifact | TODO |
| T2.3 | User Stories 3 track + AC | AI | T2.2 | artifact | TODO |
| T2.4 | Domain Design | AI | T2.3 | artifact | TODO |
| T2.5 | Units Generation (แบ่ง 3 คน) | AI | T2.4 | artifact | TODO |
| T2.6 | Contract Design | AI | T2.5 | artifact | TODO |
| T2.7 | เลือก AI provider, backend, persistence (framework เลือก Flutter แล้ว) | AI+OWNER | T2.4 | ADR | TODO |
| T2.8 | Delivery Planning (Bolt) | AI | T2.5-T2.7 | แผน Bolt | TODO |
| T2.9 | Review แบบ advisory 1 รอบ และตรวจ FR/AC ครบทุกข้อ | AI | T2.8 | ตาราง traceability | TODO |

## เฟส 3: Mock ละเอียด

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T3.1 | Refined Mockups ทุกหน้า + loading/empty/error | AI | T2.8 | artifact | TODO |
| T3.2 | Owner อนุมัติ UI | OWNER | T3.1 | บันทึกอนุมัติ | TODO |

## เฟส 4: Construction (แทนด้วย Bolt จริงเมื่อ T2.8 เสร็จ)

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T4.1 | Bolt 1 Walking skeleton: ติดตั้ง APK, กรอกโปรไฟล์, เรียก AI จริง, แสดงผล | P1-P3 | T0.7, T0.8, T3.2 | APK + commit hash | TODO |
| T4.2 | Bolt 2 Track A เงินที่ควรตรวจ/รับคืน + กฎคำนวณ deterministic | TBD | T4.1 | build+test + hash | TODO |
| T4.3 | Bolt 3 Track B งาน | TBD | T4.1 | build+test + hash | TODO |
| T4.4 | Bolt 4 Track C รายได้จากทักษะ | TBD | T4.1 | build+test + hash | TODO |
| T4.5 | Bolt 5 Action plan + Money Tracker | TBD | T4.2-T4.4 | build+test + hash | TODO |
| T4.6 | Bolt 6 Scam signals + failure handling | TBD | T4.5 | build+test + hash | TODO |

## เฟส 5: Package และตรวจรับ

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T5.1 | AC-01 3 สถานการณ์ synthetic บนอุปกรณ์จริง | P1-P3 | T4.6 | วิดีโอ/บันทึก + hash | TODO |
| T5.2 | AC-02 ยืนยันเรียก AI จริงและติดป้าย DEMO/MOCK | P1-P3 | T4.6 | log + ภาพหน้าจอ | TODO |
| T5.3 | AC-03 ไม่มีผลลัพธ์รับประกันหรือยืนยันสิทธิ์เท็จ | P1-P3 | T4.6 | เช็คลิสต์ตรวจ | TODO |
| T5.4 | AC-04 กรณีลบ 5 แบบ | P1-P3 | T4.6 | ผลเทสต์ | TODO |
| T5.5 | AC-05 หลักฐาน build/test/install ผูก commit เดียว | P1-P3 | T5.1-T5.4 | รายงาน + hash | TODO |
| T5.6 | AC-06 รวมงาน 3 คนผ่าน contract | P1-P3 | T4.6 | แอปเดียวที่ทดสอบแล้ว | TODO |

## เฟส 6: ส่งมอบ

| ID | งาน | เจ้าของ | ขึ้นกับ | Evidence | สถานะ |
|---|---|---|---|---|---|
| T6.1 | Deck น้อยกว่า 8 สไลด์ | P1-P3 | T5.5 | ไฟล์ | TODO |
| T6.2 | วิดีโอสำรองไม่เกิน 3 นาที | P1-P3 | T5.5 | ไฟล์ | TODO |
| T6.3 | ซ้อม Demo สดอย่างน้อย 1 รอบ | P1-P3 | T6.1, T6.2 | บันทึก | TODO |
| T6.4 | `/aidlc-outcomes-pack` สร้าง `OUTCOMES.md` | AI | T5.5 | ไฟล์ | TODO |
| T6.5 | บันทึก AC-07 เป็นสมมติฐานที่ยังไม่ทดสอบ | AI | - | หมายเหตุใน OUTCOMES | TODO |

## เส้นทางวิกฤต
T0.5 → T0.6 → T0.7 → (T1.x → T2.x → T3.x) → T4.1 → T4.2/T4.3/T4.4 (ขนานได้ 3 คน) → T4.5 → T4.6 → T5.x → T6.x

งานที่ทำขนานได้ตอนนี้: T0.5-T0.8 (ผู้ใช้ทำ) กับ T0.9, T1.1 (AI ทำ)
