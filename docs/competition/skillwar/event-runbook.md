# คู่มือเตรียมวันแข่งสำหรับทีมทางรอด

งานจัด 30 พฤศจิกายน 2569 ที่ห้อง Amber 1–2, BITEC Bang Na ใช้เวลาไทยทั้งหมด ตารางนี้อ้าง Booklet หน้า 2–8 และ 17 ให้ทีมจดคำชี้แจงเรื่องข้อมูลและโจทย์ขยายจากผู้จัดใน `event-brief.md` หลังเริ่มงาน

## เวลาและสิ่งส่งมอบ

| เวลา | งาน | หลักฐาน |
| --- | --- | --- |
| ก่อนวันงาน | เตรียมเครื่อง BYOD, Flutter/Android SDK, Node, USB, HDMI, Kiro และชุดข้อมูล ซ้อม baseline แยกโฟลเดอร์ | เครื่องมือพร้อมและบันทึกข้อจำกัดจากการซ้อม |
| 09:00–09:45 | ลงทะเบียน รับสายรัด ตรวจ Wi-Fi, HDMI และเครื่อง | คนดูแลเครื่องกับคนนำเสนอเห็นหน้าจอเดียวกัน |
| 09:45–10:00 | รับโจทย์ขยายและ Kiro Sandbox Credentials เครดิต $400 ต่อทีม เปิด repo ใหม่หลังเวลาเริ่มตามประกาศ และเริ่มบันทึกกิจกรรม | GitHub creation time, commit หลัง 09:45, Kiro session และรายการ pre-built ที่ใช้ |
| 10:00–11:00 | ใช้ Kiro ทำ core flow แนวตั้งตั้งแต่ข้อความไทยถึงผลค้นหาที่มีที่มา แล้วบันทึกได้ | model call, tool call, UI และแผนที่บันทึก |
| 11:00 checkpoint | ตรวจสองอินพุตและกรณีไม่พบ แก้ blocking issue และแบ่งคนดู build กับ deck | ผล run และ commit บน repo วันงาน |
| 11:00–12:00 | เก็บ provenance, consent, fallback และตรวจตัวกรองเขต | รัน Android และ tests |
| 12:00–13:00 | เปิด GitHub ให้กรรมการ pre-read และซ้อมจับเวลา | ทดสอบสิทธิ์เข้าจากบัญชีหรือหน้าต่างอื่น |
| 13:00–14:00 | Hacking Session 2 ทีมตั้งเป้าภายในให้ freeze ซ้อมครบ 10 นาที export Kiro JSON อัด backup ≤3 นาที และเตรียม deck ก่อน 13:45 | commit ที่ตรงกับ APK/API, ไฟล์ส่งครบ |
| ก่อน 14:00 | ส่ง GitHub repo แบบ Public/Shared, Kiro Activity Log JSON, Backup Demo Video และ Pitch Deck ให้ครบ | เปิดลิงก์ได้จากเครื่องอื่นและเก็บหลักฐานการส่ง |
| 14:45–18:00 | Live demo ตามลำดับสุ่ม | 7 นาที demo พร้อมสไลด์, Q&A 2 นาที, เปลี่ยนทีม 1 นาที |

แบ่งเจ้าของ 3–4 คน คนดู Kiro/model และ log, คนดู Android/build, คนดูข้อมูลกับ QA, และคน pitch/ส่งไฟล์ หากทีมมี 3 คนให้ QA กับผู้ส่งไฟล์ใช้รายการตรวจเดียวกัน

## งานที่เตรียมได้และหลักฐานที่ต้องสร้างวันแข่ง

- หน้า 5 อนุญาต pre-built boilerplate, scaffold, library, framework, เอกสารและ static reference data. ตรวจว่าชิ้นที่เลือกเป็นประเภทใดและบันทึกที่มา ถ้าขอบเขต pre-built ที่จะใช้กว้างกว่ารายการตัวอย่าง ให้ถามผู้จัดก่อนใช้แข่งขัน
- ข้อมูลที่ทีมเตรียมและอยู่นอก static reference หรือ open source ต้องแจ้งกรรมการ ปิดเส้นทางที่ส่งคำตอบ AI ที่เตรียมไว้ล่วงหน้า ให้ทุกผลใน live demo คำนวณจากอินพุตสดและแหล่งที่แจ้งจริง
- หน้า 6–7 กำหนด repo ใหม่ในวันงาน มีหลักฐานการใช้ Kiro ในการพัฒนา และส่ง Activity Log จาก Kiro แบบ JSON. ใช้ Kiro ตลอดช่วงพัฒนาแข่งขัน เก็บ log ของการอ่านโจทย์ ออกแบบ เขียน AI logic, tests, แก้ผล และเชื่อม UI. เครื่องมือทำสไลด์เลือกได้
- สร้าง GitHub repo ใหม่หลังเริ่มแข่งจากไดเรกทอรีว่าง แล้วนำไฟล์ตั้งต้นที่เลือกเข้าไปด้วย exporter หลีกเลี่ยงการ fork เปลี่ยน remote ของ repo เก่า หรือยก Git history เดิมเข้ามา แสดงรายการ pre-built และ source ใน repo ส่งงาน
- เลือก provider และการ deploy ตามที่ผู้จัดและเครื่องรองรับ เครดิต Sandbox ใช้กับ Kiro. เก็บ key ของแอปแยกจากหลักฐานและข้อมูล Git

## สร้าง repo ส่งงานและโหลดข้อมูล

ตัวอย่าง PowerShell รันจากรากของ repo เตรียมงานหลังเริ่มแข่ง

```powershell
$contestPath = 'D:/Kiro/ThangRot-SkillWar'
node docs/competition/skillwar/export-starter.cjs $contestPath
Set-Location $contestPath
git init -b main
git status --short
```

`export-starter.cjs` สร้างโฟลเดอร์ใหม่และเขียน `STARTER-INVENTORY.json` พร้อม SHA-256 ของไฟล์ ใช้ `--with-reference-data` เมื่อเลือกชุด reference เพิ่ม และ `--with-mock-inputs` เฉพาะเมื่อจะแจ้งการใช้ mock ก่อนนำเสนอ ตาม [manifest](starter-manifest.json) ทั้งสอง flag ใช้ร่วมกันได้. สร้าง GitHub repo แบบว่างผ่านบัญชีทีม แล้วเพิ่ม `origin` และ push หลังตรวจเวลาและไฟล์

เปิดโฟลเดอร์ใหม่ใน Kiro ด้วย credential วันงาน วางโจทย์ขยายและทำ [ใบงาน Kiro](kiro-build.md) Commit เป็นช่วงตามงานจริง แล้วอัปเดต README ส่งงานให้มีชื่อทีม วิธีรัน สรุปโจทย์ ชื่อผู้ใช้เป้าหมาย สิ่งที่สร้างวันแข่ง รายการ pre-built, data disclosure และลิงก์สิ่งส่งมอบ

## รัน baseline สำหรับซ้อม

ใช้ checkout ของ repo เตรียมงานที่มีชุดเอกสารนี้และตรวจ commit ด้วย `git log -1 --oneline` หากเทียบพฤติกรรมที่บันทึกไว้ ให้เปิด worktree เพิ่มที่ [commit ฐาน](https://github.com/otonzgd2/Money-Anywhere/tree/8efb63bb57e88fcb8cfd489d155ffe9cba025401) ใช้ Node 24.22.1, Flutter 3.50.1, Dart 3.14.0 และ Android SDK/NDK ตาม Gradle ของแอป

```powershell
Set-Location D:/Kiro/MoneyAnywhere
node --version
flutter --version
flutter doctor -v
npm.cmd --prefix contracts ci
New-Item -ItemType Directory -Force contracts/.data | Out-Null
Copy-Item docs/entities/database-script/demo/catalogue.db contracts/.data/skillwar-catalogue.db
$env:APP_MODE='demo'
$env:DEMO_MODE='1'
$env:GOV_CONNECTED='1'
$env:LIVE='0'
$env:JOB_AUTO_SYNC='0'
$env:JOBICY_SYNC='0'
$env:JOB_DB_FILE=(Resolve-Path contracts/.data/skillwar-catalogue.db).Path
$env:DATA_FILE=Join-Path $PWD 'contracts/.data/skillwar-state.json'
$env:AI_LOG_FILE=Join-Path $PWD 'contracts/.data/skillwar-ai.jsonl'
$env:PORT='8080'
node contracts/mock-server.js
```

`node contracts/mock-server.js` ใช้ตัวแปรจาก shell ในตัวอย่าง หากเลือกใช้ `npm run mock` ให้ตรวจ `.env` เพิ่ม เพราะ `DATA_FILE=` คือ memory และ `AI_LOG_FILE=` คือปิด logging. สำหรับ live AI ตั้ง `AI_BASE_URL`, `AI_MODEL`, `AI_API_KEY` และ `AI_API_STYLE` ตาม provider ใน shell ส่วนตัวก่อนเปิด server. สำหรับ rules-only QA ใช้เครื่องหรือ shell ที่ไม่มี credential แอป. rules-only เป็นวิธีทดสอบ fallback

```powershell
Invoke-RestMethod http://127.0.0.1:8080/v1/health
adb devices -l
adb reverse tcp:8080 tcp:8080
Set-Location app
flutter pub get
flutter test
flutter analyze
flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8080
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

- ใช้ `http://10.0.2.2:8080` สำหรับ Android Emulator ที่ใช้ network mapping. มือถือ USB ใช้ loopback พร้อม `adb reverse`. สำหรับ Wi-Fi ให้กรอก base URL ของ IP เครื่องเซิร์ฟเวอร์ในแอปและตรวจ permission/network. ถ้ามีอุปกรณ์หลายตัวให้ใช้ `adb -s <serial>`
- ให้ Windows checkout กับ `PUB_CACHE` อยู่ไดรฟ์เดียวกัน ถ้า Gradle ค้างที่ Kotlin incremental cache ให้ตั้ง `PUB_CACHE` ให้ตรงกับไดรฟ์ของ checkout แล้ว `flutter clean`, `flutter pub get` และ build ใหม่ เก็บ APK ที่สำเร็จพร้อม SHA
- หากยังเกิด `Could not close incremental caches` ให้เพิ่ม `kotlin.incremental=false` และ `kotlin.compiler.execution.strategy=in-process` ชั่วคราวใน `app/android/gradle.properties` แล้ว build ใหม่ คืนค่าเดิมก่อน stage ไฟล์ วิธีนี้สร้าง debug APK ของ baseline สำเร็จบนเครื่องที่ใช้ตรวจ
- `npm run mock:bangkok` เป็นชุด rules-only ใช้ port `8082` ตามค่าเริ่มต้น และใช้สำเนาของฐาน mock ใน `contracts/.data/` ตั้ง `JOB_DB_FILE` เพื่อเลือกฐานสำเนาของทีม
- เมื่อทีมข้อมูลตรวจสิทธิ์จัดเก็บและแสดงประกาศจาก feed แล้ว ให้ลงทะเบียนผู้ตรวจและวันตรวจจริงในฐานสำเนาด้วย `node contracts/fixtures/register-bkk-curated.js <catalogue.db> "<reviewer>" <YYYY-MM-DD>` จากนั้นตั้ง `JOB_FEEDS_FILE` ให้ใช้ provider `bkk_curated` และ `mock: false` แล้วเปิดด้วย `npm.cmd --prefix contracts run mock` ตามสเปก S0
- ทดสอบ API ด้วย `npm.cmd --prefix contracts test`, `node contracts/test-thang-rot-guard.js`, `node contracts/test-thang-rot-manual.js` และ `node docs/competition/skillwar/capture-api-examples.cjs` จากราก repo สำหรับ capture ใช้ loopback, memory state และ rules

## สาธิตให้จบในเจ็ดนาที

| นาที | ทำบนหน้าจอ | สิ่งที่กรรมการเห็น |
| --- | --- | --- |
| 0:00–1:00 | เล่ากรณีคนบางนาที่รายได้ลดและหางานตามทักษะ | เข้าใจว่าใครใช้และต้องการผลอะไร พร้อมอ้างหลักฐานปัญหาที่ตรวจแล้ว |
| 1:00–2:00 | เปิดหน้าแรก กรอกคำขอจริงด้วยภาษาไทย ระบุเขต เวลา หรือทักษะ | อินพุตจริงและรายการข้อจำกัดที่ระบบรับรู้ |
| 2:00–3:20 | เปิดผล ลิงก์และป้าย provenance จาก tool | AI skills/context เชื่อมผลค้น และใช้แหล่งตามที่แจ้ง |
| 3:20–4:20 | เปลี่ยนบริบทหรือกด “ดูงานอื่น” | เห็นผลเปลี่ยนและคงเงื่อนไขที่ยังใช้ |
| 4:20–5:20 | เลือกผล บันทึกแผน ติ๊กขั้น เปิด Contact | มีการลงมือทำและบันทึกใน API |
| 5:20–6:20 | โยงการตรวจสิทธิหรือข้อมูลเมือง แสดงหลักฐานและแยกที่มาของจำนวนเงิน | Civic Access กับ Urban Living ชัดเจน |
| 6:20–7:00 | บอกผล pilot ที่ตั้งใจวัดและ partner ที่อยากชวนร่วม | เส้นทางใช้งานจริงหลังงานและข้อจำกัดที่ทีมทราบ |

Q&A เตรียมไฟล์ response ที่ตัดข้อมูลระบุตัวตน แสดง `aiStatus: ok`, `toolCalls` และ source/candidate IDs. AI call log ของแอปเก็บ provider/status กับ invocation ID ตามที่ระบบมี ส่วน Kiro Activity Log เป็นหลักฐานการพัฒนา ทั้งสองอย่างใช้ตรวจคนละเรื่อง

Booklet หน้า 14 พูดถึงโครงเด็ค 6 หัวข้อและไม่ได้แจกแจงชื่อหัวข้อในเล่ม ใช้โครงเสนอชั่วคราว 6 หน้า content ได้แก่ ปัญหาและหลักฐาน, persona/use case, solution และ demo path, บทบาท AI และสถาปัตยกรรม, data integrity/UX, pilot และ next steps. แก้ตามโครงผู้จัดถ้ามี สไลด์ปกและขอบคุณอยู่นอกจำนวนเนื้อหา. วิดีโออัดจากระบบที่สร้างวันงานและอินพุตจริง ยาวไม่เกิน 3 นาที ใช้เมื่อจำเป็นและนับหัก 5 คะแนน

## ตรวจส่ง

- [ ] ใหม่ทั้ง GitHub repo และ Git history ไม่มี commit ก่อน 09:45 วันแข่ง
- [ ] ผู้ตรวจเปิด repo, deck และ backup video ได้
- [ ] Live demo แบบ end-to-end รันจากผลงานวันแข่ง พร้อมนำขึ้นเวที
- [ ] Kiro Activity Log เป็น JSON จากการพัฒนาจริง มีงานด้าน AI ให้ตรวจ
- [ ] จดแหล่งอ้างอิง วันตรวจ และข้อมูลจำลองทุกชุด ตรวจ mock label ใน list, detail และ chat
- [ ] APK, backend และ commit ของการสาธิตตรงกัน มีหลักฐานรัน 10 นาที
- [ ] ซ้อม failover, HDMI, ขนาดอักษร และการเปิด Contact
- [ ] ส่งครบก่อน 14:00 และเก็บหลักฐานการส่ง
