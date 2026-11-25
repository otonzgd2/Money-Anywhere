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
