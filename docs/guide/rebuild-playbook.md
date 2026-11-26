# Rebuild playbook: สร้างแอป Money Anywhere ใหม่ให้เร็วและพลาดน้อยที่สุด

ใช้ตอนวัน Demo ที่ต้องโชว์ว่าเรา dev แอปนี้ด้วย AI (Kiro) ไฟล์นี้ไม่ได้เริ่มจากศูนย์ ส่วนที่ "คงไว้" (สัญญา API, กฎเงิน, server, นโยบาย AI) ใช้ของเดิมได้เลย ส่วนที่ "สร้างใหม่ต่อหน้ากรรมการ" คือตัวแอป Flutter ใน `app/`

บันทึกจากการ dev จริงวันที่ 26 พ.ย. 2569 (API 0.7.0, Flutter 3.50.1, มือถือ Samsung SM-S948B One UI 9)

## 1. อะไรคงไว้ อะไรสร้างใหม่

| ส่วน | Path | วัน Demo |
|---|---|---|
| ความต้องการและเกณฑ์ผ่าน | `docs/product/requirements.md` | คงไว้ ใช้เป็น input ให้ Kiro |
| สัญญา API | `contracts/openapi.yaml` | คงไว้ แอปพึ่งไฟล์นี้อย่างเดียว |
| กฎเงิน อัตรา แหล่งอ้างอิง | `contracts/fixtures/reference.json` | คงไว้ |
| กฎของผู้ช่วย AI (ไม่ออกนอกเรื่อง) | `contracts/fixtures/assistant-policy.json` | คงไว้ |
| Server เดโม + adapters + tests | `contracts/` | คงไว้ (`npm.cmd run check` ต้องผ่าน) |
| กฎการทำงานของ Kiro | `.kiro/steering/*.md`, `.kiro/hooks/` | คงไว้ Kiro อ่านเองทุกแชท |
| Mock HTML (สำรองถ้ามือถือมีปัญหา) | `docs/mockups/index.html` | คงไว้ |
| แอป Flutter | `app/` | **สร้างใหม่** ตามขั้นที่ 4 (ต้นแบบอยู่ใน git) |

ต้นแบบที่ถูกต้องของแอปอยู่ใน git เสมอ ถ้าโชว์แล้วพลาด ใช้ `git checkout -- app/` กลับไปเวอร์ชันที่ใช้ได้

## 2. เตรียมเครื่อง (ทำก่อนวัน Demo ทั้งหมด ไม่ทำต่อหน้ากรรมการ)

| ของ | ค่าที่ใช้ได้จริง |
|---|---|
| Flutter | 3.50.1 stable (Dart 3.14.0) ที่ `C:\src\flutter` |
| Android SDK | `D:\Android\Sdk` มี `platform-tools`, `platforms;android-36`, `build-tools;36.0.0`, ยอมรับ license แล้ว |
| JDK | JBR ของ Android Studio `C:\Program Files\Android\Android Studio\jbr` (OpenJDK 25) ใช้ได้กับ Gradle ของ template นี้ |
| Gradle cache | `GRADLE_USER_HOME=D:\gradle-home` (drive C เหลือน้อย) |
| pub cache | `PUB_CACHE=D:\pub-cache` |
| PATH | `C:\src\flutter\bin`, `D:\Android\Sdk\platform-tools` |
| AI | `.env` ที่ root: `AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai`, `AI_MODEL=gemini-3.5-flash-lite`, `AI_API_KEY=...` (ไม่ commit) |

เช็คก่อนวัน Demo:

```powershell
flutter doctor            # Android toolchain ต้องเป็น ✓ (คำเตือน Visual Studio ไม่เกี่ยว)
adb devices               # ต้องเห็นเครื่องเป็น "device" ไม่ใช่ "unauthorized"
cd contracts; npm.cmd run check   # ต้องได้ RESULT: PASS
```

**อุ่น cache ไว้ก่อน (สำคัญที่สุดเรื่องเวลา):** build ครั้งแรกใช้ ~4 นาที (วัดได้ 213 วินาที) เพราะโหลด Gradle และ Android NDK r28c ครั้งต่อไปวัดได้ 11 วินาที ติดตั้งลงมือถือ ~20 วินาที ให้ build แอปเต็ม 1 รอบในวันก่อน Demo บนเครื่องที่จะใช้จริง อย่าลบ `D:\gradle-home` และ `D:\pub-cache`

มือถือ (One UI 9 เมนูไทย): การตั้งค่า > ข้อมูลโทรศัพท์ > ข้อมูลซอฟต์แวร์ > แตะ "หมายเลขรุ่น" 7 ครั้ง > กลับไป "ตัวเลือกสำหรับนักพัฒนา" > เปิด "การแก้ไขจุดบกพร่อง USB" ถ้าเปิด "ตัวบล็อกอัตโนมัติ (Auto Blocker)" อยู่ให้ปิดก่อน ไม่งั้นติดตั้งผ่าน USB ไม่ได้ เสียบสายแล้วกด "อนุญาต" บนจอ ตั้งจอไม่ให้ดับระหว่าง Demo

## 3. ลำดับวัน Demo (เป้า ~15 นาที)

| # | ขั้น | คำสั่ง / สิ่งที่บอก Kiro | ผ่านเมื่อ | เวลา |
|---|---|---|---|---|
| 1 | เปิด server | `cd contracts; npm.cmd run mock` | `http://127.0.0.1:8080/v1/health` ได้ 200 และ `ai.provider` = `openai_compatible` | 10 วิ |
| 2 | ต่อมือถือ | `adb reverse tcp:8080 tcp:8080` | `adb reverse --list` เห็น `tcp:8080` | 5 วิ |
| 3 | สร้างโปรเจกต์ | `flutter create --org com.moneyanywhere --project-name money_anywhere --platforms android app` | มีโฟลเดอร์ `app/` | 30 วิ |
| 4 | ให้ Kiro เขียนแอป | ใช้ prompt ในข้อ 5 ทีละไฟล์ | `flutter analyze` ไม่มี issue | 5–8 นาที |
| 5 | เทสต์ | `cd app; flutter test` | All tests passed | 15 วิ |
| 6 | build + ติดตั้ง | `flutter build apk --debug` แล้ว `adb install -r --user 0 build\app\outputs\flutter-apk\app-debug.apk` | ไอคอน Money Anywhere บนมือถือ | 1 นาที (cache อุ่นแล้ว) |
| 7 | โชว์ flow | ตามข้อ 6 | ครบทุกข้อ | 3 นาที |

ทางลัด: `tools\build-and-install.ps1` ทำข้อ 5–6 พร้อมรีสตาร์ต server, `adb reverse` และเปิดแอปให้ในคำสั่งเดียว ดู log ที่ `contracts\.data\build-app.log` เวอร์ชันเครื่องมือทั้งหมดอยู่ใน `docs/guide/dev-setup.md`

## 4. โครงแอปที่ต้องได้ (ต้นแบบใน `app/`)

ตั้งค่าหลัง `flutter create`:

- `pubspec.yaml`: template ของ Flutter 3.50 ใส่ `material_ui: ^1.1.0` มาให้แล้ว import ใช้ `package:material_ui/material_ui.dart` (ไม่ใช่ `flutter/material.dart`)
- `android/app/src/main/AndroidManifest.xml`: เพิ่ม `<uses-permission android:name="android.permission.INTERNET"/>` และใน `<application>` ใส่ `android:label="Money Anywhere"` กับ `android:usesCleartextTraffic="true"` (server เดโมเป็น http)

ไฟล์ใน `app/lib/` เขียนตามลำดับนี้ (ไฟล์หลังพึ่งไฟล์ก่อน):

| ไฟล์ | หน้าที่ | กฎที่ห้ามพลาด |
|---|---|---|
| `api.dart` | เรียก API ด้วย `dart:io` HttpClient, header `X-Device-Id`, แปลง error เป็น `ApiException(status, code, message)`, `consent(ai:)` | base URL จาก `--dart-define=API_BASE_URL` ค่าเริ่ม `http://127.0.0.1:8080` (ใช้กับ `adb reverse`); device id เก็บในไฟล์ cache ของแอป ไม่สุ่มใหม่ทุกครั้งที่เปิด |
| `money.dart` | ฟังก์ชันล้วน: `toFactValue`, `tierOf`, `rankMoney`, `nextQuestion`, `statusLabel`, `dataLabel`, `baht` | เรียงตามความแน่นอนของการได้เงิน; ไม่นับรายการ "ได้อยู่แล้ว"; mock ต้องขึ้นป้าย DEMO / MOCK เสมอ |
| `money_check.dart` | `QuickCheckScreen` ถามทีละข้อผ่าน `POST /v1/money/preview`; `RouteScreen` เส้นทางรับเงิน + บันทึกแผน `POST /v1/tasks` | รับ `knownFacts` แล้ว **ไม่ถามซ้ำ** ข้อที่ตอบแล้ว; ถ้ายินยอมแล้วบันทึกทุกคำตอบทันที และไม่ถามยินยอมซ้ำ |
| `chat.dart` | `ChatSession` (เก็บข้อความ, conversationId) + `ChatScreen` คุยแบบ guided | `ChatSession` ต้องอยู่นอกหน้าจอ (ถือโดยหน้าแรก) ไม่งั้นกด back แล้วแชทหาย; ถ้า server ตอบ 404 ให้เริ่มคุยใหม่เอง |
| `main.dart` | หน้าแรกแบบ "เงินก่อน" | ก่อนตอบ: ปุ่ม AI ใหญ่ + เช็คเงินเอง; หลังตอบ: สรุปเงิน + แผนของฉัน ขึ้นก่อน, ปุ่ม AI เป็น "คุยกับ AI ต่อ", การ์ดเช็คเงินเองเหลือเฉพาะ "ตอบเพิ่มอีก N เรื่อง" และหายไปเมื่อไม่มีข้อค้าง; โหลดข้อมูลใหม่ทุกครั้งที่กลับมาหน้าแรก |
| `common.dart` | `AppState` (api, แชท, `bump()` ให้ทุกแท็บโหลดใหม่, สลับแท็บ), แผ่นความยินยอม, ประกาศ, เปิดลิงก์ภายนอก + ถาม "ยื่นแล้วหรือยัง" ตอนกลับเข้าแอป, การ์ด "ต่อ server ไม่ได้" | ตรงตาม `docs/design/ui-states.md` §4 §6 |
| `home_tab.dart`, `opp_tab.dart`, `plans_tab.dart`, `me_tab.dart` | 4 แท็บ | หน้าแรกเปลี่ยนตามสถานะใน ui-states.md §3 |
| `route_screen.dart`, `task_screen.dart` | เส้นทางรับเงิน, รายละเอียดแผน (ทำขั้นเสร็จ/เลิกทำ/ติดปัญหา/ไว้ทีหลัง/แจ้งผล) | สถานะแผนเปลี่ยนผ่าน `POST /v1/tasks/{id}/events` เท่านั้น |
| `test/widget_test.dart` | unit test | แปลงคำตอบ, เรียงเงิน, ข้ามข้อ, ป้าย mock, กฎขั้นต่อไป, ข้อความเงินของโอกาส |

API ที่แอปใช้ (ทั้งหมดมีใน `openapi.yaml`): `GET /v1/privacy/notice`, `POST /v1/me/consents`, `GET /v1/me/consents`, `GET|PATCH /v1/me/facts`, `POST /v1/money/preview`, `GET /v1/money`, `GET /v1/money/{id}`, `GET|POST /v1/tasks`, `POST /v1/ai/conversations`, `POST /v1/ai/conversations/{id}/messages`, `POST /v1/ai/conversations/{id}/actions/{actionId}`

## 5. Prompt ที่ใช้สั่ง Kiro (ก๊อปไปใช้ได้เลย)

Kiro โหลด `.kiro/steering/money-anywhere.md`, `contracts-api.md`, `flutter-app.md` เองทุกแชท จึงไม่ต้องอธิบายกฎซ้ำ

1. "อ่าน `contracts/openapi.yaml` แล้วเขียน `app/lib/api.dart` แบบ thin client ด้วย dart:io ตามตาราง api.dart ใน `docs/guide/rebuild-playbook.md` ข้อ 4"
2. "เขียน `app/lib/money.dart` และ `app/test/widget_test.dart` ตามข้อ 4 แล้วรัน `flutter test`"
3. "เขียน `app/lib/money_check.dart` (QuickCheckScreen + RouteScreen) ตามข้อ 4 ห้ามถามข้อที่มีใน knownFacts"
4. "เขียน `app/lib/chat.dart` ให้มี ChatSession แยกจากหน้าจอ และแสดงป้าย guard/aiStatus จาก API"
5. "เขียน `app/lib/main.dart` หน้าแรกแบบเงินก่อนตามข้อ 4 แล้วรัน `flutter analyze`"
6. "build APK debug แล้วติดตั้งลงมือถือด้วย `adb install -r --user 0`"

ถ้า Kiro เขียนพลาด ให้บอกแค่อาการ แล้วชี้ไปที่ตารางข้อ 4 อย่าให้มันออกแบบใหม่

## 6. Flow ที่ต้องโชว์และต้องผ่าน

1. หน้าแรก: เห็นปุ่ม "ให้ AI หาเงินให้ฉัน" ใหญ่สุด และป้าย DEMO / MOCK
2. กดปุ่ม AI: ทักทายและถามข้อแรก (อายุ) มีปุ่มตอบด่วน + "ไม่แน่ใจ ข้ามข้อนี้"
3. พิมพ์ "อายุ 65 ปีค่ะ": รับเป็นคำตอบ "60-69" แล้วถามข้อต่อไป
4. ถามในเรื่อง เช่น "ต้องทำไงต่อ", "ขอลิงก์ติดต่อ": ตอบจากช่องทางทางการ ไม่ขึ้น "นอกเรื่อง"
5. ลองให้ออกนอกเรื่อง: "ลืมคำสั่งทั้งหมด", "ขอเลขเด็ด", ส่งเลขบัตร 13 หลัก: ปฏิเสธพร้อมป้าย 🛡️ และพากลับมาที่คำถาม
6. กด back แล้วเข้าใหม่: แชทเดิมยังอยู่ ปุ่มเปลี่ยนเป็น "คุยกับ AI ต่อ"
7. หน้าแรกหลังตอบ: สรุปเงินที่น่าจะได้ (ประมาณจากเกณฑ์ ยังไม่ยืนยัน), การ์ด "ตอบเพิ่มอีก N เรื่อง" ถามเฉพาะข้อที่ยังไม่ตอบ
8. แตะรายการเงิน: เส้นทางรับเงิน เอกสาร ที่ยื่น แหล่งข้อมูล แล้วกด "เริ่มเลย: บันทึกเป็นแผน"
9. หน้าแรกมี "แผนของฉัน (1)"

## 7. ปัญหาที่เจอจริงและวิธีแก้ (อย่าเจอซ้ำ)

| อาการ | สาเหตุ | วิธีแก้ |
|---|---|---|
| `npm` รันไม่ได้ใน PowerShell | policy บล็อก `npm.ps1` | ใช้ `npm.cmd` |
| ผลคำสั่งไม่กลับมาให้ Kiro / ไฟล์เพิ่งเขียนยังไม่เห็น | terminal ของ agent ตัดผล | ส่งผลลงไฟล์ใน `contracts/.data/` แล้วค่อยอ่าน ใช้ชื่อไฟล์ใหม่ทุกครั้ง; งานยาวรันผ่าน `Start-Process powershell -File ... -WindowStyle Hidden` |
| `adb` not recognized | shell ใหม่ยังไม่มี PATH | ใช้ path เต็ม `D:\Android\Sdk\platform-tools\adb.exe` หรือปิดเปิด terminal |
| `adb install` ค้าง / `SecurityException ... user 150` | Samsung Secure Folder เป็น user แยก | ใส่ `--user 0` ทั้ง `install` และ `am start` |
| Gemini ช้า 2–3 นาที / 503 | `gemini-flash-latest` คนใช้เยอะ | ใช้ `gemini-3.5-flash-lite` (1–3 วิ); `gemini-2.5-*` ได้ 404 สำหรับ key ใหม่ |
| Kiro / Claude Pro / ChatGPT Plus เป็น AI ของแอปไม่ได้ | subscription ไม่มี API | ใช้ Gemini ฟรีผ่าน endpoint แบบ OpenAI |
| build ครั้งแรกนาน ~4 นาที | โหลด Gradle + NDK | อุ่น cache ก่อนวัน Demo (ข้อ 2) |
| drive C เต็ม | SDK/Gradle ใหญ่ | ย้ายทุกอย่างไป D (ตารางข้อ 2) |
| แอปต่อ server ไม่ได้ | ไม่ได้ `adb reverse` หรือ server ไม่รัน | `adb reverse tcp:8080 tcp:8080` ทุกครั้งที่เสียบสายใหม่; เช็ค `/v1/health` |
| http ถูกบล็อกบน Android | cleartext ปิดเป็นค่าเริ่ม | `android:usesCleartextTraffic="true"` |
| ถาม "ต้องทำไง", "ขอลิงก์ติดต่อ" แล้วขึ้น "นอกเรื่อง" | guard ใช้รายการคำในขอบเขตแบบตายตัว | API 0.7: เพิ่มคำในขอบเขต; คำถามแบบ "ทำไง/ลิงก์/เบอร์/ติดต่อ" ตอบจากข้อมูลเส้นทางรับเงินโดยตรง ไม่ผ่าน AI |
| AI ตอบ "ต้องทำไง" ด้วยการไล่รายชื่อเงินทุกอย่าง ทั้งที่ยังไม่ได้ตอบสักข้อ | ปล่อยให้ AI ตอบเอง | ตอบแบบกำหนดตายตัว: "ต้องตอบอีก N เรื่องก่อน" |
| "แนะนำร้านกาแฟหน่อย" ถูกบันทึกเป็นคำตอบ | AI แปลงข้อความเป็นตัวเลือกที่ใกล้ที่สุดเสมอ | รับเป็นคำตอบเฉพาะข้อความที่ดูเหมือนคำตอบ (มีตัวเลข, ขึ้นต้น ใช่/ไม่/มี/เคย/ได้/ทำ/ยัง/เป็น/อายุ) |
| ข้อความนอกเรื่องที่ไม่มีคำต้องห้าม AI ตอบเอง (เช่น ช่วยหาร้านกาแฟ) | สั่งใน system prompt ให้ตอบ OFF_TOPIC แต่ Gemini ไม่ทำตาม | ถาม AI สั้นๆ แยกก่อนว่า "เกี่ยว/ไม่เกี่ยว" ถ้าไม่เกี่ยวใช้ข้อความปฏิเสธที่กำหนดไว้ (`ai_scope`) |
| พิมพ์ "ไม่แน่ใจ" แล้วโดนปฏิเสธ | ไม่มีทางข้ามคำถามในแชท | API 0.7: `skip` + ปุ่ม "ไม่แน่ใจ ข้ามข้อนี้" |
| กด back แล้วแชทหาย | state ของแชทอยู่ในหน้าจอ | `ChatSession` ถือโดยหน้าแรก |
| ตอบไปแล้วหน้าแรกไม่เปลี่ยน, เช็คเงินเองถามซ้ำ | หน้าแรกเป็น StatelessWidget, QuickCheck เริ่มจากศูนย์ | หน้าแรกโหลด facts/money/tasks ใหม่หลังกลับมา; QuickCheck รับ `knownFacts` |
| ปิดเปิดแอปแล้วข้อมูลหาย | device id สุ่มใหม่ทุกครั้ง | เก็บ device id ในไฟล์ cache ของแอป |
| JSON ของ policy พัง | มี `"` ซ้อนในข้อความ | ใช้ `'` ในข้อความภาษาไทย |
| ไฟล์ที่ PowerShell เขียนมี BOM | `Set-Content -Encoding utf8` ของ PowerShell 5 | ใช้ `[IO.File]::WriteAllText(path, text, (New-Object Text.UTF8Encoding $false))` |
| screenshot มืด | จอมือถือดับ | ตั้งจอไม่ดับระหว่าง Demo; `adb shell screencap -p /sdcard/s.png` แล้ว `adb pull` |

## 8. แผนสำรองถ้าพลาดต่อหน้ากรรมการ

1. build พัง: `git checkout -- app/` แล้ว build ใหม่ (cache อุ่นแล้ว ~1 นาที)
2. ติดตั้งไม่ได้: APK สำรองที่ build ไว้วันก่อน ติดตั้งบนเครื่องไว้แล้ว เปิดใช้ได้ทันที
3. AI ล่ม / เน็ตหลุด: server ถอยไปใช้โหมดกฎเอง (`aiStatus: fallback_rules`) flow ยังเดินได้ครบ
4. มือถือมีปัญหา: เปิด `docs/mockups/index.html` บนเบราว์เซอร์ โชว์ flow เดียวกัน
