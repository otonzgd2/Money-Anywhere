# คู่มือคำสั่ง AI-DLC สำหรับพัฒนาแอปมือถือ (MoneyAnywhere)

## 0. เตรียมก่อนเริ่ม
- Kiro IDE: เลือก agent **aidlc** ที่ช่องแชท แล้วพิมพ์คำสั่ง `/aidlc ...` ทั้งบรรทัดก่อนกด Enter
- Kiro CLI: รัน `kiro-cli --v3` ในโฟลเดอร์โปรเจกต์
- ตรวจระบบ: `/aidlc --doctor`
- ดูสถานะ/ขั้นปัจจุบัน: `/aidlc --status`
- ดูเวอร์ชัน: `/aidlc --version`, ดูวิธีใช้: `/aidlc --help`

## 1. เริ่มงาน (เลือกอย่างใดอย่างหนึ่ง)

| ต้องการ | คำสั่ง |
|---|---|
| ให้ระบบเสนอแผนให้ | `/aidlc <อธิบายแอปที่ต้องการ>` |
| ออกแบบแผนเฉพาะงาน (compose) | `/aidlc compose "<งาน>"` |
| เลือก scope เอง | `/aidlc --scope <ชื่อ> <อธิบายงาน>` |
| เริ่มเฉพาะ Initialization | `/aidlc-init --scope <ชื่อ> <อธิบายงาน>` |

Scope ที่ใช้บ่อย: `express` (เบาสุด), `mvp` (ข้าม operations), `feature` (ครบวงจร), `bugfix`, `security-patch`

**กฎของโปรเจกต์นี้ (Money Anywhere):**
- เอกสารธุรกิจหลักคือ `docs/product/requirements.md` (Owner อนุมัติแล้ว) ใช้เป็น input ของ AI-DLC ห้ามสร้าง intent, state, review หรือไฟล์ของ stage ด้วยมือ
- ให้เริ่ม workflow ด้วยคำขอ **ภาษาอังกฤษ** ที่มีเนื้อหาจริง เพื่อให้เอกสารที่ AI-DLC สร้างเป็นภาษาอังกฤษ (ระบบล็อกภาษาตามที่ใช้ใน session ถ้าไม่มีสัญญาณภาษา จะถามก่อน)
- เป้าหมายคือแอป Android ที่ติดตั้งได้ ส่วน framework, AI provider, infra และ persistence ยังไม่ถูกกำหนด ปล่อยให้เป็นผลของ design ใน AI-DLC
- ขอบเขตธุรกิจ ขอบเขตความเชื่อมั่นของข้อมูล (trust boundary) ค่าใช้จ่าย สิทธิ์เข้าถึง หรือการเผยแพร่ ถ้าจะเปลี่ยน ต้องให้ Owner อนุมัติ

ตัวอย่าง (พิมพ์ทั้งบรรทัดใน agent `aidlc`):
```
/aidlc --scope mvp Build the Money Anywhere Android app described in docs/product/requirements.md. Cover the three MVP tracks (money to check or recover, employment, skill-based income) with a real end-to-end flow: profile -> live AI result -> sourced opportunity -> action checklist -> progress tracking.
```

ตัวเลือกปรับระดับ (ใส่ต่อท้ายได้):
- `--depth <level>` ปรับความละเอียด
- `--test-strategy <level>` ปรับปริมาณการทดสอบ
- `--review <adversarial|advisory|none>` กำหนดระดับ review
- ดูค่าที่รับได้ของแต่ละ flag ด้วย `/aidlc --help`

หมายเหตุ: `/aidlc --scope mvp` รัน 20 จาก 30 ขั้น (ข้าม operations เป็นหลัก) ตาม `/aidlc --help`

## 2. ลำดับขั้นตอนทั้งหมด

ทุกขั้นระบบจะหยุดขออนุมัติ (approval gate) ตอบอนุมัติเพื่อไปต่อ หรือสั่งแก้ได้
เดินต่ออัตโนมัติด้วย `/aidlc` อีกครั้ง หรือรันขั้นเดียวแยกด้วยคำสั่ง `/aidlc-<stage>`

### Phase 1: Ideation (ไอเดียและความเป็นไปได้)
| # | ขั้น | คำสั่งรันแยก | ผู้ทำหลัก | ผลลัพธ์ |
|---|---|---|---|---|
| 1 | Intent Capture | `/aidlc-intent-capture` | product | เป้าหมายและปัญหา |
| 2 | Feasibility | `/aidlc-feasibility` | architect (+compliance) | ความเป็นไปได้/ข้อจำกัด |
| 3 | Market Research | `/aidlc-market-research` | product | วิจัยตลาด |
| 4 | Scope Definition | `/aidlc-scope-definition` | product | ขอบเขตงาน |
| 5 | Rough Mockups | `/aidlc-rough-mockups` | design | ภาพร่างหน้าจอ |
| 6 | Team Formation | `/aidlc-team-formation` | delivery | จัดทีม |
| 7 | Approval Handoff | `/aidlc-approval-handoff` | delivery | อนุมัติส่งต่อเข้า Inception |

### Phase 2: Inception (วางแผนและออกแบบ)
| # | ขั้น | คำสั่งรันแยก | ผู้ทำหลัก | ผลลัพธ์ |
|---|---|---|---|---|
| 8 | Reverse Engineering (เมื่อมีโค้ดเดิม) | `/aidlc-reverse-engineering` | developer, architect | สรุปโค้ดเดิม |
| 9 | Practices Discovery | `/aidlc-practices-discovery` | pipeline-deploy | แนวปฏิบัติทีม (branch, test, deploy) |
| 10 | Requirements Analysis | `/aidlc-requirements-analysis` | product | requirements |
| 11 | User Stories | `/aidlc-user-stories` | product (+design, quality, developer) | stories + acceptance criteria |
| 12 | Domain Design | `/aidlc-domain-design` | architect | โมเดลโดเมน |
| 13 | Units Generation | `/aidlc-units-generation` | architect | แบ่ง unit |
| 14 | Contract Design | `/aidlc-contract-design` | architect | API/สัญญาระหว่างส่วน |
| 15 | Refined Mockups | `/aidlc-refined-mockups` | design | UI ละเอียด |
| 16 | Delivery Planning | `/aidlc-delivery-planning` | delivery | ลำดับ Bolt (รอบการส่งมอบ) |

### Phase 3: Construction (สร้างและทดสอบ)
| # | ขั้น | คำสั่งรันแยก | ผู้ทำหลัก | ผลลัพธ์ |
|---|---|---|---|---|
| 17 | Functional Design | `/aidlc-functional-design` | architect (+quality) | ออกแบบฟังก์ชันรายหน่วย |
| 18 | NFR Requirements | `/aidlc-nfr-requirements` | architect (+quality, devsecops) | ประสิทธิภาพ/ความปลอดภัย |
| 19 | NFR Design | `/aidlc-nfr-design` | architect | วิธีออกแบบรองรับ NFR |
| 20 | Infrastructure Design | `/aidlc-infrastructure-design` | aws-platform (+devsecops) | โครงสร้างพื้นฐาน |
| 21 | Code Generation | `/aidlc-code-generation` | developer | โค้ด + เทสต์ |
| 22 | Build and Test | `/aidlc-build-and-test` | quality | build, ทดสอบ, quality gate |
| 23 | CI Pipeline | `/aidlc-ci-pipeline` | pipeline-deploy | CI |

### Phase 4: Operation (ปล่อยและดูแล)
| # | ขั้น | คำสั่งรันแยก | ผู้ทำหลัก | ผลลัพธ์ |
|---|---|---|---|---|
| 24 | Deployment Pipeline | `/aidlc-deployment-pipeline` | pipeline-deploy | CD |
| 25 | Environment Provisioning | `/aidlc-environment-provisioning` | aws-platform | สร้าง environment |
| 26 | Deployment Execution | `/aidlc-deployment-execution` | pipeline-deploy | ปล่อยจริง (โปรเจกต์นี้ยังไม่รวมการเผยแพร่บน app store ต้องให้ Owner อนุมัติก่อน) |
| 27 | Observability Setup | `/aidlc-observability-setup` | operations | monitoring/alert |
| 28 | Performance Validation | `/aidlc-performance-validation` | quality | ทดสอบประสิทธิภาพ |
| 29 | Incident Response | `/aidlc-incident-response` | operations | เมื่อเกิดเหตุ |
| 30 | Feedback & Optimization | `/aidlc-feedback-optimization` | operations | ปรับปรุงต่อเนื่อง |

หมายเหตุ: scope เบา (เช่น `express`, `mvp`) จะข้ามบางขั้นโดยอัตโนมัติ

## 3. การตรวจแผนและ review (Planning → Review → Dev → QA)

| ช่วง | สิ่งที่เกิด | ผู้ตรวจ |
|---|---|---|
| ร่างแผน (draft plan) | `/aidlc compose "<งาน>"` ได้ตาราง EXECUTE/SKIP ของแต่ละขั้น ต้องตอบ approve / edit / reject | composer |
| วิเคราะห์ requirements/stories | ตรวจความครบ ความทดสอบได้ ตรงเป้าธุรกิจ | **product-lead** (reviewer) |
| ตรวจ design/architecture | ตรวจความสมเหตุสมผล การทำได้จริง ความสอดคล้อง | **architecture-reviewer** |
| SA (architect) | domain design, contract, NFR, units | architect agent |
| Dev | code generation ทีละ unit | developer agent |
| QA | test strategy, build-and-test, performance | quality agent |
| Security | threat model, NFR ความปลอดภัย | devsecops agent |

ปรับระดับ review: `/aidlc --review adversarial` (เข้มสุด) | `advisory` (แนะนำ) | `none` (ไม่ตรวจ)

## 4. คำสั่งควบคุมระหว่างทาง
| ต้องการ | คำสั่ง |
|---|---|
| ข้ามไปขั้นที่ต้องการ | `/aidlc --stage <slug>` |
| ไปยัง phase | `/aidlc --phase <ideation|inception|construction|operation>` |
| รันขั้นเดียวไม่ขยับ workflow หลัก | `/aidlc --stage <slug> --single` |
| ปรับแผนขั้นที่เหลือกลางทาง | `/aidlc compose "<งาน>"` |
| ตั้งค่า | `/aidlc --config [section]` |
| ปิด/เปิดการสรุปยืนยัน | `/aidlc --summary-confirmation on|off` |
| ปิด/เปิดการเรียนรู้ | `/aidlc --learnings on|off` |
| ปิด/เปิด sensors | `/aidlc --sensors on|off` |

## 5. คำสั่งสรุป/ปิดงาน
- `/aidlc-session-cost` สรุปเวลา/จำนวนขั้น (อ่านอย่างเดียว)
- `/aidlc-replay` เล่าเรื่องการทำงานให้คนที่ไม่ได้อยู่ด้วย
- `/aidlc-outcomes-pack` สร้าง `OUTCOMES.md` เอกสารส่งมอบ
- `/aidlc-knowledge` นำเอกสารทีม (PDF, Word, Markdown) เข้า catalog ให้ agent อ้างอิง
- `/aidlc-issue-report` รวบรวมข้อมูลเมื่อระบบทำงานผิดปกติ

## 6. ลำดับใช้งานจริงแบบย่อ (MVP แอปมือถือ)
1. `/aidlc --doctor`
2. `/aidlc --scope mvp <คำขอภาษาอังกฤษอ้าง docs/product/requirements.md>` (หรือ `/aidlc compose "<task>"` แล้ว approve แผน)
3. ตอบคำถามและอนุมัติทีละขั้น: Ideation → Inception (ตรวจ requirements/stories, design)
4. Construction: อนุมัติ design แล้วให้ code generation → build-and-test
   - ทำ Android packaging/install ให้ได้ตั้งแต่ช่วงต้น และเก็บ build ที่ผ่านการรวมแล้วไว้เป็น known-good
   - ทดสอบ flow จริง: profile → ผล AI → โอกาสที่มีแหล่งที่มา → action plan → progress รวมกรณีข้อมูลไม่ครบ และ AI/ข้อมูลใช้ไม่ได้
   - รายงานผลทดสอบพร้อม commit ที่ตรงกัน
5. ตรวจผล: `/aidlc --status`
6. Push ขึ้น git: `git add . ; git commit -m "..." ; git push`
7. ปิดงาน: `/aidlc-outcomes-pack`

## 6.1 ข้อควรระวังด้านข้อมูลและความน่าเชื่อถือ
- ห้ามแสดงข้อมูลสิทธิ์ การจ่ายเงิน การจ้างงาน หรือข้อมูลรัฐแบบ mock ว่าเป็นผลจริงที่ยืนยันแล้ว ให้ติดป้าย DEMO / MOCK
- ห้ามรับประกันเงิน งาน หรือรายได้จากผล AI
- แยกให้ชัดว่าเป็น: ข้อเท็จจริงมีแหล่งที่มา, ค่าประมาณ, การอนุมานของ AI, ข้อมูลที่ผู้ใช้แจ้ง, หรือ mock
- ใช้ตัวตนสมมติ (synthetic) ในการสาธิต และห้าม commit ข้อมูลส่วนบุคคลหรือ secret

## 6.2 งานของทีม 3 คน
- แบ่งงานเป็น Unit ที่ตรวจสอบได้อิสระ และเชื่อมกันผ่าน contract ที่ใช้ร่วมกัน (stage `contract-design`, `units-generation`)
- ให้ AI-DLC เป็นผู้กำหนดการแบ่ง unit และวิธีพัฒนา ถ้าเปลี่ยนขอบเขตธุรกิจหรือ trust boundary ให้ขอ Owner อนุมัติ
- คำสั่ง `unit status`, `--claim <unit>`, `--release <unit>` ใช้จองและดูสถานะ Unit ของทีม (ดู `/aidlc --help`)

## 7. Git (repo: https://github.com/otonzgd2/Money-Anywhere)
```powershell
git add .
git commit -m "ข้อความอธิบาย"
git push
```
โฟลเดอร์ `aidlc/` ควร commit ด้วย (เก็บบันทึกการตัดสินใจ)
