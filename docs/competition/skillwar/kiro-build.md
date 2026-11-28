# งานสร้างทางรอดใน Kiro

ใช้ใบงานนี้หลังได้รับโจทย์ขยายและเปิดโฟลเดอร์ repo ส่งงานใน Kiro แล้ว สร้าง `event-brief.md` บันทึกถ้อยคำโจทย์ ขอบเขตที่เปลี่ยน แหล่งข้อมูลที่ตกลงใช้ และสิ่งที่ทีมใช้เป็น pre-built

## Prompt เริ่มงาน

```text
Build Thang Rot (Money Anywhere), a Thai Android app for a Bangkok resident
whose income changed and who wants to find public support and a local income
opportunity they can act on. Read event-brief.md first. Resolve conflicts in
favor of the official day-of-event brief and record the change by REQ ID.
Read docs/competition/skillwar/{requirements,dev-spec,data-dictionary}.md,
contracts/openapi.yaml, the supplied config schema and QA scenarios.

Implement a working vertical slice first. A user gives a new Thai-language
request, the app requests consent, the assistant uses a configured live model
to call the opportunity search tool, the backend checks and returns a grounded
answer with provenance, and the user can save an option and complete a step.
Keep explicit district, availability and skills in context, including after
a follow-up asking for other jobs. Mark synthetic inputs and results that use
them, per item, in every view. Record why the result changed when the input
changes. Use only source records approved in event-brief.md.

Use deterministic benefit rules and calculation tools for amounts. Preserve
unknown, zero, stale and conflicting facts as distinct. Keep external writes
behind explicit user confirmation. Implement the documented fallback and
display the real AI status. No scripted outcome, precomputed model answer or
production use of sample citizen data. Run the app and tests after each stage.
Report actual checks that passed and anything still open.
```

## Stages และจุดตรวจ

| Stage | ให้ Kiro ทำ | ปิดงานเมื่อ |
| --- | --- | --- |
| S1 | สร้าง shell, config, consent และ REST client | cold start, health, notice, 4 แท็บและ retry ผ่าน |
| S2 | เขียน schema, source repository, district filter, data labels และ tests | source แสดงชื่อ เขตและวันตรวจ, filter เขตก่อนจัดอันดับ, mock มี label, no-match ไม่มีผลแต่ง |
| S3 | เขียน guard, intent/context, model tool, numeric/link validation และ action confirmation | โหมด rules กับ live แยกได้. เปิด actual request/response สองแบบพร้อม tool calls และลอง timeout |
| S4 | ต่อเส้นทาง live, save, plan step, Contact, preview สิทธิและ profile | P03–P09 ผ่านในโหมดที่เกี่ยวข้อง มีหลักฐานใน CLI และ Android |
| S5 | ทำ parity ส่วนเสริม, accessibility, export/delete, docs และ stage checks | ความแตกต่างมีเหตุผล ปิดช่องว่างจาก scorecard และ export Activity Log จริง |

## วิธีจัดงานตามเวลา

ทำ S1–S3 ให้ได้ flow เส้นเดียวก่อน checkpoint 11:00 ทดสอบ P04/P05 ด้วยข้อมูลที่ได้รับอนุญาตก่อนขยายไปหน้ารอง ให้ Kiro เก็บหลักฐานของ AI logic ตั้งแต่ตกลง schema ของ search tool, reason for ranking, source selection และการป้องกันการเขียนซ้ำ รวมถึงผล test ที่เปลี่ยนหลังแก้

ก่อน freeze ขอให้ Kiro รัน API และ app tests แล้วรายงานแต่ละคำสั่งกับ exit status. นำ SHA ที่ได้ไปเขียนในบันทึกสาธิต เมื่อไม่มี live evidence ให้ระบุโหมด rules ตามจริงและแยกผลการทดสอบออกจากข้อขัดข้อง
