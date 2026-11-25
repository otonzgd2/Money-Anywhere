# แผนส่งมอบ Demo: Money Anywhere

เป้าหมาย: Demo แอป Android ที่รันได้จริง ตรงกับ `docs/product/requirements.md` (3 track: A เงินที่ควรตรวจ/รับคืน, B งาน, C รายได้จากทักษะ)
หลักการ: ปิดงานให้ได้ก่อน ตัดสิ่งที่ทำให้ติด ไม่ทำ security/hardening และไม่ให้งานวนไปมา (ดู `aidlc/spaces/default/memory/project.md`)

กฎใช้ checklist: ติ๊ก `[x]` เมื่อมีหลักฐานจริง (ไฟล์, ผลรัน, หน้าจอ) ก่อนไปเฟสถัดไป ไม่ผ่านให้แก้ในเฟสนั้น

## สถานะเครื่องที่ตรวจเมื่อ 2026-11 (ตรวจจริงในเครื่องนี้)
- มี: Node.js
- ไม่มี: Java/JDK, Android SDK (adb), Flutter/Dart, Gradle
- ใน repo ยังไม่มี `docs/product/requirements.md` และ `README.md`

## ภาพรวมเฟส

| เฟส | ชื่อ | ผลลัพธ์ | คำสั่ง/เครื่องมือ |
|---|---|---|---|
| 0 | วางเครื่องมือ | เครื่องและ repo พร้อมทำงาน | ติดตั้ง, `/aidlc --doctor` |
| 1 | Ideation + Mock หน้าจอ | scope, ภาพร่างหน้าจอ, แผน | `/aidlc ...`, rough-mockups |
| 2 | Inception | requirements, stories, design, contract, หน่วยงาน, แผน Bolt | AI-DLC stages |
| 3 | Mock หน้าจอละเอียด | หน้าจอที่ Owner อนุมัติ | refined-mockups |
| 4 | Construction | โค้ดและเทสต์ทีละ unit | code-generation, build-and-test |
| 5 | Package และ Demo | APK ที่ติดตั้งได้ + สคริปต์ Demo | build APK, ซ้อม |
| 6 | ส่งมอบ | deck (<8 สไลด์), วิดีโอ (<3 นาที), ผลทดสอบ | เอกสาร |

---

## เฟส 0: วางเครื่องมือ (ทำก่อนเสมอ)

คำตอบสั้น: ใช่ ต้องวางก่อน เพราะ Android build ต้องใช้ JDK และ SDK ซึ่งยังไม่มีในเครื่อง และ Android packaging ต้องได้ตั้งแต่ช่วงต้นตาม requirements

### 0.1 เครื่องมือกลาง (ใช้ได้ไม่ว่าจะเลือก framework ไหน)
- [ ] Git ใช้ได้และ push ขึ้น repo ได้ (ทำแล้ว)
- [ ] Node.js (มีแล้ว)
- [ ] Android Studio (มาพร้อม JDK และ SDK Manager)
- [ ] Android SDK + platform-tools (ได้คำสั่ง `adb`)
- [ ] Emulator หนึ่งเครื่อง หรือมือถือ Android ที่เปิด USB debugging
- [ ] ตรวจ: `adb devices` เห็นอุปกรณ์, `java -version` ทำงาน
- [ ] Kiro: เลือก agent `aidlc` ได้, `/aidlc --doctor` ผ่าน

### 0.2 เครื่องมือเฉพาะ framework (เลือกตามผล design ใน AI-DLC อย่าเลือกก่อน)
- [x] Owner เลือก Flutter (Android first, iOS ภายหลังได้) บันทึกใน `project.md` แล้ว
- [ ] ติดตั้ง Flutter SDK แล้ว `flutter doctor` ผ่าน
- [ ] ทำ "hello world" ติดตั้งบนอุปกรณ์ให้ได้

### 0.3 Repo และกฎทีม
- [ ] เพิ่ม `docs/product/requirements.md` และ `README.md` เข้า repo (ยังไม่มีในตอนนี้)
- [ ] `project.md` ตั้งกฎ Demo แล้ว (ทำแล้ว)
- [ ] ตกลงวิธีทำงานของทีม 3 คน: ใครถือ Unit ไหน ใช้ `/aidlc unit status`, `--claim <unit>`
- [ ] ตกลง AI provider และ API key (เก็บใน environment variable, ไม่ commit)
- [ ] `.gitignore` กัน `.env`, build output, keystore
- [ ] commit และ push เฟส 0

เกณฑ์ผ่านเฟส 0: ติดตั้ง hello-world APK ลงอุปกรณ์ได้ และ `/aidlc --doctor` ไม่มี error

---

## เฟส 1: Ideation + Mock หน้าจอคร่าวๆ

เริ่มด้วยคำขอภาษาอังกฤษที่มีเนื้อหาจริง (ตามกฎโปรเจกต์) เพื่อให้เอกสารออกมาเป็นอังกฤษ

```
/aidlc compose "Build the Money Anywhere Android demo described in docs/product/requirements.md. Include rough screen mockups first, then a working end-to-end demo for tracks A, B and C."
```

- [ ] ดูแผน EXECUTE/SKIP ที่ composer เสนอ ต้องมีขั้น rough-mockups และ refined-mockups ถ้าไม่มีให้สั่งแก้ (edit) ก่อน approve
- [ ] approve แผน (Plan Approval เป็นจุดที่ต้องให้คนอนุมัติ)
- [ ] Intent Capture: เป้าหมายตรงกับ section 1 ของ requirements
- [ ] Scope Definition: ครบ 3 track, ไม่รวมของที่ Deferred
- [ ] Rough Mockups: ภาพร่างหน้าจอครบ flow หลัก

Checklist หน้าจอที่ต้องมี (ขั้นต่ำ):
- [ ] หน้าต้อนรับ/เลือกเป้าหมาย
- [ ] หน้ากรอกโปรไฟล์ (ทักษะ, พื้นที่, เวลา, ข้อจำกัด, เป้ารายได้)
- [ ] หน้าผลลัพธ์ AI: รายการโอกาสเรียงลำดับ พร้อมเหตุผลที่ตรง
- [ ] หน้ารายละเอียดโอกาส: แหล่งที่มา, สถานะความสดใหม่, เงื่อนไข, ความไม่แน่นอน, ป้าย DEMO/MOCK
- [ ] หน้าแผนรายได้: รายได้ที่เป็นไปได้, ต้นทุน, รายได้สุทธิโดยประมาณ, ความเสี่ยง
- [ ] หน้า checklist ลงมือทำ พร้อมลิงก์ไปช่องทางทางการ
- [ ] หน้าติดตามความคืบหน้า (แยก "ผู้ใช้แจ้งเอง" ออกจาก "ยืนยันจากภายนอก")
- [ ] สถานะผิดพลาด: ข้อมูลไม่พอ, ไม่พบผล, สัญญาณหลอกลวง, AI ล้มเหลว

เกณฑ์ผ่านเฟส 1: Owner ดูภาพร่างแล้วตอบว่าใช่ หรือแก้หนึ่งรอบ

## เฟส 2: Inception

ขั้น (ผู้นำขั้นอยู่ในคู่มือ `docs/guide/aidlc-commands.md`):
- [ ] Practices Discovery: ยืนยันแนวทางทีม ให้ตรงกับกฎ Demo
- [ ] Requirements Analysis: FR-01..08 ถูกแปลงเป็นข้อกำหนดที่ทดสอบได้
- [ ] User Stories: อย่างน้อย 1 story ต่อ track พร้อม acceptance criteria แบบ Given/When/Then
- [ ] Domain Design: โมเดลโอกาส, โปรไฟล์, แหล่งที่มา, ความคืบหน้า
- [ ] Units Generation: แบ่งงาน 3 คนเป็น Unit ที่ตรวจสอบเองได้
- [ ] Contract Design: API/รูปแบบข้อมูลที่ใช้ร่วมกันระหว่าง Unit
- [ ] Decision: เลือก framework, AI provider, backend, persistence (พร้อมเทียบทางเลือกอย่างน้อยสอง)
- [ ] Delivery Planning: ลำดับ Bolt, Bolt แรกต้องเป็น walking skeleton ที่ build เป็น APK ได้

ตรวจสอบเมื่อจบเฟส:
- [ ] ทุก FR และ AC ใน requirements ผูกกับอย่างน้อยหนึ่ง story หรือ unit
- [ ] ไม่มีข้อกำหนดที่ขัดกันค้างอยู่
- [ ] สมมติฐานทุกข้อถูกบันทึกไว้
- [ ] review แบบ advisory เสร็จหนึ่งรอบ (product-lead สำหรับ requirements/stories, architecture-reviewer สำหรับ design)

## เฟส 3: Mock หน้าจอละเอียด
- [ ] Refined Mockups ครบทุกหน้าในเฟส 1 พร้อมสถานะ loading/empty/error
- [ ] ป้าย DEMO/MOCK และการแยกประเภทข้อมูลปรากฏในหน้าจอ
- [ ] Owner อนุมัติ (หนึ่งรอบแก้) แล้วจึงเริ่มเขียนโค้ด UI

## เฟส 4: Construction (วนทีละ Bolt)

ต่อ Bolt ให้ทำตามลำดับ:
1. [ ] Functional Design ของ unit
2. [ ] Code Generation (โค้ดและเทสต์)
3. [ ] Build and Test
4. [ ] รวมเข้า `main` และ build APK ได้ (known-good)
5. [ ] ติ๊กผลลัพธ์ พร้อม commit hash

ลำดับ Bolt ที่แนะนำ:
- [ ] Bolt 1 Walking skeleton: แอปเปิดได้ → กรอกโปรไฟล์ → เรียก AI จริงหนึ่งครั้ง → แสดงผล (ติดตั้งบนอุปกรณ์)
- [ ] Bolt 2 Track A: ตรวจ/รับเงินคืน พร้อมแหล่งอ้างอิงและกฎคำนวณที่ทำซ้ำได้
- [ ] Bolt 3 Track B: งาน
- [ ] Bolt 4 Track C: รายได้จากทักษะ พร้อมสมมติฐานต้นทุน
- [ ] Bolt 5 Action plan + Money Tracker
- [ ] Bolt 6 Scam signals + failure handling (FR-07, FR-08)

Checklist ต่อ Bolt:
- [ ] ผ่าน build และเทสต์ของ unit
- [ ] ไม่มี mock ที่ถูกแสดงเป็นข้อมูลจริง
- [ ] ไม่มีข้อความรับประกันเงิน งาน หรือสิทธิ์
- [ ] ไม่มี secret หรือข้อมูลส่วนตัวจริงใน commit

## เฟส 5: Package และ Demo (ตรวจกับ AC-01..AC-05)
- [ ] AC-01: 3 สถานการณ์ synthetic (หนึ่งต่อ track) ครบ profile → ผล AI → แหล่งที่มา/สมมติฐาน → checklist → บันทึกความคืบหน้า บนอุปกรณ์จริง
- [ ] AC-02: ยืนยันว่ามีการเรียก AI จริง และข้อมูลจำลองถูกติดป้ายชัด
- [ ] AC-03: ไม่มีผลลัพธ์ใดรับประกันหรือยืนยันสิทธิ์เท็จ
- [ ] AC-04: กรณีลบครบ: ข้อมูลโปรไฟล์ไม่ครบ, ไม่มีผล, โอกาสน่าสงสัย, แหล่งข้อมูลเก่า, AI/ระบบล้มเหลว
- [ ] AC-05: build, test, ติดตั้ง Android และ Demo สดมีหลักฐานผูกกับ commit เดียว
- [ ] AC-06: สมาชิกทั้ง 3 คนรวมงานผ่าน contract และได้แอปเดียวที่ทดสอบแล้ว
- [ ] แผนสำรอง: วิดีโอ Demo ถ่ายไว้ก่อน เผื่อ Demo สดล้ม

## เฟส 6: ส่งมอบ
- [ ] Deck น้อยกว่า 8 สไลด์
- [ ] วิดีโอสำรองยาวไม่เกิน 3 นาที
- [ ] ซ้อม Demo สดอย่างน้อยหนึ่งรอบ
- [ ] `/aidlc-outcomes-pack` สร้าง `OUTCOMES.md`
- [ ] AC-07 บันทึกเป็นสมมติฐานที่ยังไม่ได้ทดสอบกับผู้ใช้

---

## ตัวควบคุมไม่ให้งานวนไปมา
- ถามคำถามเป็นรอบเดียวต่อขั้น ถ้าตอบไม่ได้ ให้เลือก default แล้วบันทึกเป็น assumption
- แก้ไขได้หนึ่งรอบต่อ artifact แล้วไปต่อ
- ถ้าติดเกิน 1 ชั่วโมงในเรื่องเดียว: ตัดขอบเขตเรื่องนั้นให้เล็กลงหรือใช้ mock ที่ติดป้าย แล้วไปต่อ
- ตรวจ `/aidlc --status` ต้นและท้ายทุกเซสชัน
- Commit และ push ทุกจบ Bolt

## ความเสี่ยงที่ต้องจับตา
| ความเสี่ยง | วิธีลด |
|---|---|
| ติดตั้ง Android toolchain ใช้เวลา | ทำเฟส 0 ก่อนและพิสูจน์ด้วย hello-world APK |
| เรียก AI จริงไม่ได้/ช้า/คิดเงิน | ตั้ง AI provider ตั้งแต่เฟส 0 และทำใน Bolt 1 |
| ข้อมูลแหล่งที่มาไม่พอ | ใช้ชุดอ้างอิงขนาดเล็กที่ระบุแหล่ง และ mock ที่ติดป้าย DEMO/MOCK |
| 3 คนรวมงานไม่เข้ากัน | Contract Design ก่อน และ Bolt 1 ต้อง build ได้ |
| Demo สดล้ม | วิดีโอสำรองและ APK known-good |
